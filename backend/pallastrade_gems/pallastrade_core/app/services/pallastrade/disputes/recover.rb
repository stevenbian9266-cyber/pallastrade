# frozen_string_literal: true

# PALLAS-CUSTOM: DSP-P7-6 (PRD-20260912-payments-dsp-p7-6-dispute-recovery)
#
# Disputes::Recover —— 单条 Dispute 的**收敛动作**（源计划 §47–§53 / P7-0 FR-006）。
#
# 输入**必须是 Facts**（源计划 §48）：本地 Dispute + provider 当前只读快照（`fetch: true`）
#   + FinancialFact + Journal + Reconciliation。决策只有五种：repair lifecycle / repair financial fact /
#   repair journal / repair reconciliation / manual review —— 本服务用封闭枚举 `DECISIONS` 表达，
#   其中「repair financial fact」在本架构下**不可自动**（资金时间戳不可凭空生成，见下）：
#
#   - `stale_local`（provider 已到终态、本地未达）→ `transition_to!` **单调前进**（漏事件兜底，§52）
#   - `journal_missing` → `FinancialLedger::PostDispute` **幂等补记**（恰好一次）
#   - `conflict` / 孤儿账行 / 金额不符 / 资金时间戳缺失 / 既有 attention → 标人工（§48 manual review）
#
# **铁律（源计划 §49/§50 —— 本服务永不执行）**：
#   1. 不因 lost/mismatch/withdrawal **重新扣款**；不创建/更新 `Payment` / `PaymentSession` / `Refund`；
#   2. **不自动 Refund**、不提交证据、不调用 provider 任何写方法（`fetch_dispute_details` 为只读契约）；
#   3. 不改 `Order` / `CommerceTransaction` / `Shipment` / `Inventory` / `StockReservation`；
#   4. 不改写或删除既有 `FinancialLedgerEntry`（append-only）——`amount_mismatch` 只交人工；
#   5. 状态**只能单调前进**（`Dispute#transition_to!` 既有约束），绝不倒退，绝不用 `Time.current`
#      伪造资金时间戳（会让幂等键漂移 → 重复入账，FR-P73-07）。
#
# 幂等（源计划 §53 双层幂等）：`transition_to!` 同状态返回 false；`PostDispute` 幂等键唯一；
#   `attention_reason` **只补不覆盖**；已 `manual_review` 且有 attention 的行不再重复标记
#   （`manual_review_pending`）——同一事实重复执行收敛恒为 `noop` / `manual_review_pending`。
#
# 只读降级（FIN-INV-09 不猜）：provider 无只读契约 → `unsupported`；provider 报错 → `unavailable`；
#   两者**零写**且不落 attention（暂时故障不该被钉成人工工单）。
module PallasTrade
  module Disputes
    class Recover
      prepend PallasTrade::ServiceModule::Base

      # 决策封闭枚举（stable assertable）
      DECISIONS = %w[
        noop
        lifecycle_repaired
        journal_repaired
        lifecycle_and_journal_repaired
        manual_review_flagged
        manual_review_pending
        unavailable
        unsupported
      ].freeze

      # 动作状态：planned = dry-run 计划 / applied = 已执行 / skipped = 幂等原语拒绝（带封闭原因）
      # / blocked = 状态机拒绝
      ACTION_STATUSES = %w[planned applied skipped blocked].freeze

      # provider 只读裁决 → 降级决策（零写）
      DEGRADED_DECISION_BY_RESOLUTION = {
        'unsupported' => 'unsupported',
        'unavailable' => 'unavailable'
      }.freeze

      # provider 状态**蕴含**的资金移动（仅用于「缺证据」人工标记，**永不**据此入账或补时间戳）
      WITHDRAWAL_PROVIDER_STATUSES = %w[lost].freeze
      REINSTATEMENT_PROVIDER_STATUSES = %w[won].freeze

      # 期望账行类型 → 事件作用域事实类型（P7-3 命名纪律：两套清单同名）
      JOURNAL_FACT_TYPE_BY_ENTRY_TYPE = {
        'DISPUTE_FUNDS_WITHDRAWN' => 'DISPUTE_FUNDS_WITHDRAWN',
        'DISPUTE_FUNDS_REINSTATED' => 'DISPUTE_FUNDS_REINSTATED'
      }.freeze

      # @param dispute [PallasTrade::Dispute]
      # @param fetch [Boolean] true = 先取 provider 只读快照（生命周期收敛的前提；false 时零网络）
      # @param apply [Boolean] false = dry-run（返回**计划**决策与动作，数据库零变化）
      # @param now [Time] 观测时刻（注入便于测试）
      # @return [PallasTrade::ServiceModule::Result] success(Hash) / failure
      def call(dispute:, fetch: true, apply: true, now: Time.current)
        return failure(nil, 'Dispute not found') if dispute.nil?

        fact_result = PallasTrade::Disputes::ResolveFact.call(dispute: dispute, fetch: fetch)
        return failure(dispute, fact_result.error) unless fact_result.success?

        fact = fact_result.value
        # 复用**同一份**权威快照派生的事实（零重复 provider I/O，且不依赖本地元数据：
        # 仅靠本地 `private_metadata['provider_status']` 会在缺元数据时把可证事实降为 AMBIGUOUS → 漏补账）
        reconciliation_result = PallasTrade::Reconciliations::ReconcileDispute.call(dispute: dispute,
                                                                                    dispute_fact: fact)
        return failure(dispute, reconciliation_result.error) unless reconciliation_result.success?

        reconciliation = reconciliation_result.value
        state_before = dispute.state
        already_flagged = manual_review_pending?(dispute)
        degraded = DEGRADED_DECISION_BY_RESOLUTION[fact.resolution]
        actions = degraded ? [] : converge(dispute, fact, reconciliation, apply: apply)
        decision = degraded || decision_for(actions, already_flagged: already_flagged)

        record_audit(dispute, decision, actions, state_before, now) if apply && applied?(actions)

        success(dispute_id: dispute.prefixed_id,
                state_before: state_before,
                state_after: dispute.reload.state,
                dry_run: !apply,
                decision: decision,
                actions: actions,
                fact: fact_summary(fact),
                reconciliation: reconciliation_summary(reconciliation),
                attention_reason: dispute.attention_reason,
                manual_review: dispute.manual_review?,
                observed_at: now)
      end

      private

      # 收敛编排：状态 → 账行 → 人工（每一步都幂等且可 dry-run）
      #
      # `observed_state` 固定为**观测时刻**的状态：生命周期修复会先改状态，若用修复后的状态判定
      # 人工通道，会把「本来就在人工态」的行当成新冲突重新标一遍（自激振荡）。
      def converge(dispute, fact, reconciliation, apply:)
        actions = []
        observed_state = dispute.state

        lifecycle = lifecycle_plan(dispute, fact)
        actions << apply_lifecycle(dispute, lifecycle, apply: apply) if lifecycle

        missing_journal_entries(reconciliation).each do |entry_type|
          actions << apply_journal_repair(dispute, entry_type, fact, apply: apply)
        end

        manual = manual_review_plan(dispute, fact, reconciliation, actions, observed_state: observed_state)
        actions << apply_manual_review(dispute, manual, apply: apply) if manual

        actions
      end

      # ---- 1) 生命周期收敛（唯一允许的状态写） ---------------------------------

      # @return [Hash, nil] { from:, to: } —— nil = 不收敛（降级 / 已一致 / 非权威来源 / 非单调）
      def lifecycle_plan(dispute, fact)
        expected = PallasTrade::Disputes::ProviderPayload::STATE_BY_PROVIDER_STATUS[fact.provider_status.to_s]
        return nil if expected.blank?
        return nil if expected == dispute.state
        return nil unless lifecycle_repair_allowed?(dispute, fact, expected)

        { from: dispute.state, to: expected }
      end

      def lifecycle_repair_allowed?(dispute, fact, expected)
        # webhook（私有元数据里的 provider_status）**不是权威**（P7-0 §20）：只有本次只读快照才算
        return false unless fact.source == 'provider_fetch'

        forward = rank(expected) >= rank(dispute.state)
        return true if fact.resolution == 'stale_local' && forward
        # 人工态：只允许收敛到 provider **终态**（人工未处理完的非终态一律不动）
        return true if dispute.manual_review? && PallasTrade::Dispute::TERMINAL_STATES.include?(expected)

        false
      end

      def rank(state)
        PallasTrade::Dispute::STATE_ORDER.fetch(state, 0)
      end

      def apply_lifecycle(dispute, plan, apply:)
        action = lifecycle_action(plan, 'planned')
        return action unless apply

        dispute.transition_to!(plan[:to])
        lifecycle_action(plan, 'applied')
      rescue PallasTrade::Dispute::InvalidTransition
        # 状态机拒绝（理论上被 lifecycle_plan 守卫拦住）→ 保留事实 + 交人工，绝不丢事实
        lifecycle_action(plan, 'blocked').merge('reason' => 'invalid_transition')
      end

      def lifecycle_action(plan, status)
        { 'type' => 'lifecycle_repair', 'from' => plan[:from], 'to' => plan[:to], 'status' => status }
      end

      # ---- 2) 账行补记（唯一允许的账本写；幂等恰好一次） -----------------------

      # 期望账行 = funds 时间戳集合（P7-3 口径）；缺失即补记
      def missing_journal_entries(reconciliation)
        return [] unless reconciliation[:classification] == 'journal_missing'

        expected = Array(reconciliation[:expected_entries]).map { |e| e[:entry_type] }.compact
        present = Array(reconciliation[:entries]).map { |e| e[:entry_type] }.compact
        expected.uniq - present
      end

      # dry-run 只做「计划」标注（skip 判定属执行期事实，由 `PostDispute.skip_reason_for` 封闭枚举给出）
      def apply_journal_repair(dispute, entry_type, fact, apply:)
        fact_type = JOURNAL_FACT_TYPE_BY_ENTRY_TYPE.fetch(entry_type)
        action = { 'type' => 'journal_repair', 'entry_type' => entry_type, 'fact_type' => fact_type }
        return action.merge('status' => 'planned') unless apply

        result = PallasTrade::FinancialLedger::PostDispute.call(dispute: dispute, fact_type: fact_type,
                                                                dispute_fact: fact)
        return action.merge('status' => 'blocked', 'reason' => 'posting_error') unless result.success?

        value = result.value
        return action.merge('status' => 'skipped', 'reason' => value[:reason]) if value[:skipped]

        action.merge('status' => 'applied', 'entry_id' => value[:entry].prefixed_id)
      end

      # ---- 3) 人工复核通道（attention 只补不覆盖 + manual_review 状态） --------

      def manual_review_plan(dispute, fact, reconciliation, actions, observed_state:)
        # 观测时就已在人工态且有 attention → 已有人看，不再重复标记（幂等：manual_review_pending）
        return nil if observed_state == 'manual_review' && dispute.attention_reason.present?

        reason = manual_review_reason(dispute, fact, reconciliation, actions, observed_state: observed_state)
        return nil if reason.nil?

        { attention_reason: reason,
          write_attention: dispute.attention_reason.blank?,
          from_state: observed_state }
      end

      # @return [String, nil] 封闭枚举（既有 attention 原样保留，永不覆盖）
      def manual_review_reason(dispute, fact, reconciliation, actions, observed_state:)
        return dispute.attention_reason if dispute.attention_reason.present?
        return 'provider_conflict' if blocked_lifecycle?(actions)
        # `ResolveFact` 对 `manual_review` 一律判 conflict（人工态即冲突态）→ 不据此重复点名，
        # 否则每次巡检都会给自己加噪；真实的账行/资金缺口仍然照报
        return 'provider_conflict' if fact.resolution == 'conflict' && observed_state != 'manual_review'
        return 'journal_gap' if %w[orphan_entry amount_mismatch].include?(reconciliation[:classification])
        return 'journal_gap' if skipped_journal_repair?(actions)
        return 'funds_evidence_missing' if funds_evidence_missing?(dispute, fact)

        nil
      end

      def blocked_lifecycle?(actions)
        actions.any? { |a| a['type'] == 'lifecycle_repair' && a['status'] == 'blocked' }
      end

      def skipped_journal_repair?(actions)
        actions.any? { |a| a['type'] == 'journal_repair' && a['status'] == 'skipped' }
      end

      # provider 终局显示资金已移动，而本地连 funds 时间戳都没有（缺事件）→ 交人工，
      # **不猜时间戳**（猜了幂等键会漂移，且等于凭空造事实）。
      # 仅在 `aligned`（provider 与本地都到终局且一致）时判定，避免 webhook 在途窗口误报。
      def funds_evidence_missing?(dispute, fact)
        return false unless fact.source == 'provider_fetch'
        return false unless fact.resolution == 'aligned'

        status = fact.provider_status.to_s
        return true if WITHDRAWAL_PROVIDER_STATUSES.include?(status) && dispute.funds_withdrawn_at.blank?
        return true if REINSTATEMENT_PROVIDER_STATUSES.include?(status) && dispute.funds_reinstated_at.blank?

        false
      end

      def apply_manual_review(dispute, plan, apply:)
        action = { 'type' => 'manual_review', 'attention_reason' => plan[:attention_reason],
                   'from_state' => plan[:from_state] }
        return action.merge('status' => 'planned') unless apply

        dispute.update!(attention_reason: plan[:attention_reason]) if plan[:write_attention]
        dispute.transition_to!('manual_review') unless dispute.state == 'manual_review'

        action.merge('status' => 'applied', 'to_state' => dispute.state)
      end

      # ---- 决策与审计 ---------------------------------------------------------

      def decision_for(actions, already_flagged:)
        return 'manual_review_flagged' if actions.any? { |a| a['type'] == 'manual_review' }

        lifecycle = repaired?(actions, 'lifecycle_repair')
        journal = repaired?(actions, 'journal_repair')
        return 'lifecycle_and_journal_repaired' if lifecycle && journal
        return 'lifecycle_repaired' if lifecycle
        return 'journal_repaired' if journal
        return 'manual_review_pending' if already_flagged

        'noop'
      end

      # planned（dry-run 计划）与 applied 都算「有动作」——dry-run 返回与真实执行一致的决策标签
      def repaired?(actions, type)
        actions.any? { |a| a['type'] == type && %w[planned applied].include?(a['status']) }
      end

      def applied?(actions)
        actions.any? { |a| a['status'] == 'applied' }
      end

      def manual_review_pending?(dispute)
        dispute.manual_review? && dispute.attention_reason.present?
      end

      # 审计：仅保留**最近一次**（非数组累积，避免 jsonb 膨胀）；无动作不写（不刷新行语义）
      def record_audit(dispute, decision, actions, state_before, now)
        metadata = (dispute.private_metadata || {}).merge(
          'recovery' => {
            'at' => now.utc.iso8601,
            'decision' => decision,
            'actions' => actions,
            'from' => state_before,
            'to' => dispute.state
          }
        )
        dispute.update!(private_metadata: metadata)
      end

      def fact_summary(fact)
        { fact_type: fact.fact_type, status: fact.status, resolution: fact.resolution,
          provider_status: fact.provider_status, source: fact.source }
      end

      def reconciliation_summary(reconciliation)
        { classification: reconciliation[:classification], reasons: reconciliation[:reasons] }
      end
    end
  end
end
