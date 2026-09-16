# frozen_string_literal: true

# PALLAS-CUSTOM: D14 切片2（PRD-20260916-payments-d14b-dispute-deadlines；业务方案 §71.2）——
# `Disputes::AlertDeadlines` —— 争议期限**分档提醒 + 超期处置**的**唯一写入口**。
#
# 与既有 DSP-P7-5 的关系：
#   * 扫描**复用** `Disputes::ScanDeadlines`（只读，唯一筛选口径）；
#   * `DeadlineSweeperJob` 仍按原样发布 `dispute.evidence_due_soon` / `dispute.evidence_overdue`
#     （既有语义不变）；本服务**额外**负责：分档台账（幂等）+ 分档事件 + 策略化超期置 lost。
#
# 语义：
#   * **不遗漏**：达到的档位（T-3 / T-1 / 超期）逐个落台账（首次扫描时跨多档 → 全部补齐，历史档
#     标记 `backfilled` 且**不补发过期提醒**）；
#   * **不重复**：台账唯一键 `(dispute_id, tier)`；只有**本轮新记录的档位**才发事件；
#   * **超期处置**：`auto_lose_on_overdue` 开启时，对「超期 + 未提交证据 + 非终态 + 可行动状态」的
#     争议 `transition_to!('lost')` + `attention_reason = 'evidence_overdue'` + 审计；默认**关闭**。
#
# 店铺隔离（硬边界）：`store:` 显式传入时**只处理该店争议**（`skipped_other_store` 计数留痕）。
#   扫描底座 `ScanDeadlines` 是**全局只读**（DSP-P7-5 契约，不改）；但**写侧**（台账 / 事件 / 置 lost）
#   绝不越店 —— 否则会把 A 店策略套到 B 店争议上（极端情况：替 B 店自动置 lost）。
#   全局 sweeper 仍走 `store: nil`，此时**逐店取策略**处理各自争议。
#
# 铁律：**零资金副作用** —— 不写 funds 时间戳（因此不触发资金入账事件）、不改 Payment/Refund/
# Journal/Order/库存、零 provider 调用。
module PallasTrade
  module Disputes
    class AlertDeadlines
      prepend PallasTrade::ServiceModule::Base

      TIER_EVENT = 'dispute.evidence_deadline_tier'
      # 允许自动置 lost 的状态（provider 已进入裁决的 `submitted` 不在其中 —— 由 provider 裁决）
      AUTO_LOSE_STATES = %w[opened needs_response under_review].freeze
      DEFAULT_LIMIT = PallasTrade::Disputes::ScanDeadlines::DEFAULT_LIMIT
      # 全局 sweeper 的扫描窗口下界（覆盖各店可能配置的更宽档位，如 t7）
      GLOBAL_WINDOW_HOURS = 7 * 24

      # @param store [PallasTrade::Store, nil] 限定店铺（缺省全局，sweeper 用法）
      # @param now [Time]
      # @param limit [Integer, nil] 扫描上限；缺省 = 策略最宽档位窗口对应的默认上限
      # @return [PallasTrade::ServiceModule::Result] success(Hash) / failure(nil, message)
      def call(store: nil, now: Time.current, limit: nil)
        policy = PallasTrade::Disputes::DeadlinePolicy.for(store)
        scan = PallasTrade::Disputes::ScanDeadlines.call(
          window_hours: scan_window_hours(store, policy), now: now, limit: limit || DEFAULT_LIMIT
        )
        return failure(nil, scan.error.to_s) unless scan.success?

        value = scan.value
        candidates = Array(value[:due_soon]) + Array(value[:overdue])
        budget = policy.auto_lose_limit

        summary = {
          scanned: value[:scanned_count], window_hours: value[:window_hours],
          tiers_recorded: 0, alerted: 0, backfilled: 0, auto_lost: 0,
          skipped_submitted: 0, skipped_other_store: 0, failed: 0, policy: policy.snapshot, scanned_at: now
        }

        candidates.each do |item|
          dispute = find_dispute(item)
          next if dispute.nil? || dispute.terminal?

          # 店铺隔离：显式店铺 → 只处理本店争议（扫描是全局只读，写侧绝不越店）
          if store.present? && dispute.store_id != store.id
            summary[:skipped_other_store] += 1
            next
          end

          # 全局运行时**按各店策略**生效（店铺显式传入时才统一用该店策略）
          dispute_policy = store.present? ? policy : PallasTrade::Disputes::DeadlinePolicy.for(dispute.store)

          outcome = alert_dispute(dispute, item, dispute_policy, now)
          summary[:tiers_recorded] += outcome[:recorded]
          summary[:backfilled] += outcome[:backfilled]
          summary[:alerted] += outcome[:alerted] ? 1 : 0

          next unless dispute_policy.auto_lose_on_overdue? && dispute.evidence_due_at && dispute.evidence_due_at < now

          if auto_lose_candidate?(dispute)
            if budget.positive?
              auto_lose!(dispute, item, dispute_policy, now)
              summary[:auto_lost] += 1
              budget -= 1
            end
          else
            summary[:skipped_submitted] += 1
          end
        rescue StandardError => e
          summary[:failed] += 1
          Rails.logger.error(
            "[Disputes::AlertDeadlines] failed for dispute #{item[:dispute_id]}: #{e.class} #{e.message}"
          )
        end

        log_summary(summary)
        success(summary)
      end

      private

      # 扫描窗口：显式店铺 → 该店策略最宽档；全局 → 至少 7 天（覆盖各店可能配置的更宽档位）
      def scan_window_hours(store, policy)
        return policy.max_window_hours if store.present?

        [policy.max_window_hours, GLOBAL_WINDOW_HOURS].max
      end

      def find_dispute(item)
        id = prefixed_id_to_id(item[:dispute_id])
        return nil if id.nil?

        PallasTrade::Dispute.find_by(id: id)
      end

      def prefixed_id_to_id(prefixed_id)
        return nil if prefixed_id.blank?
        return prefixed_id if prefixed_id.is_a?(Integer)

        text = prefixed_id.to_s
        return text.to_i if text.match?(/\A\d+\z/)
        return nil unless PallasTrade::PrefixedId.prefixed_id?(text)

        PallasTrade::PrefixedId.decode_prefixed_id(text)
      rescue StandardError
        nil
      end

      # 落台账（幂等）+ 只对新档位发事件
      # @return [Hash] { recorded:, backfilled:, alerted: }
      def alert_dispute(dispute, item, policy, now)
        reached = policy.reached_tiers(hours_remaining: item[:hours_remaining])
        current = policy.latest_tier(hours_remaining: item[:hours_remaining])
        recorded = 0
        backfilled = 0
        alerted = false

        reached.each do |tier|
          newest = tier == current
          alert = create_alert(dispute, item, tier, policy, now, backfilled: !newest)
          next if alert.nil?

          recorded += 1
          if newest
            alerted = true
            publish_tier_event(dispute, item, tier)
          else
            backfilled += 1
          end

          record_audit(dispute, item, tier, alert, policy)
        end

        { recorded: recorded, backfilled: backfilled, alerted: alerted }
      end

      # @return [PallasTrade::DisputeDeadlineAlert, nil] nil = 该档已存在（幂等）
      def create_alert(dispute, item, tier, policy, now, backfilled:)
        alert = PallasTrade::DisputeDeadlineAlert.new(
          dispute_id: dispute.id,
          store_id: dispute.store_id,
          tier: tier,
          alerted_at: now,
          evidence_due_at: dispute.evidence_due_at,
          hours_remaining: item[:hours_remaining],
          metadata: {
            'backfilled' => backfilled,
            'missing_evidence' => item[:missing_evidence],
            'evidence_unavailable' => item[:evidence_unavailable],
            'policy' => policy.snapshot
          }
        )
        alert.save!
        alert
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
        nil
      end

      def publish_tier_event(dispute, item, tier)
        return unless PallasTrade::Events.enabled?

        PallasTrade::Events.publish(TIER_EVENT, {
          'id' => dispute.prefixed_id,
          'tier' => tier,
          'state' => dispute.state,
          'due_at' => dispute.evidence_due_at&.iso8601,
          'hours_remaining' => item[:hours_remaining],
          'missing_evidence' => item[:missing_evidence]
        })
      end

      def record_audit(dispute, item, tier, alert, policy)
        PallasTrade::Audit.record(
          action: 'dispute_deadline_tier_recorded',
          actor: 'system',
          resource: dispute,
          after: {
            tier: tier,
            backfilled: alert.backfilled?,
            evidence_due_at: dispute.evidence_due_at&.iso8601,
            hours_remaining: item[:hours_remaining],
            missing_evidence: item[:missing_evidence],
            policy: policy.snapshot
          }
        )
      end

      # 可自动置 lost：未提交证据 + 状态可行动（`submitted` 交给 provider 裁决）
      def auto_lose_candidate?(dispute)
        return false unless AUTO_LOSE_STATES.include?(dispute.state.to_s)
        return false if dispute.evidence_submitted_at.present?
        return false if dispute.evidence_submissions.exists?

        true
      end

      def auto_lose!(dispute, item, policy, now)
        dispute.transition_to!('lost', at: now)
        if dispute.attention_reason.blank?
          dispute.update!(attention_reason: PallasTrade::Disputes::DeadlineAlertSubscriber::OVERDUE_REASON)
        end

        PallasTrade::Audit.record(
          action: 'dispute_auto_lost_overdue',
          actor: 'system',
          resource: dispute,
          after: {
            state: dispute.state,
            evidence_due_at: dispute.evidence_due_at&.iso8601,
            hours_remaining: item[:hours_remaining],
            evidence_submitted_at: dispute.evidence_submitted_at&.iso8601,
            policy: policy.snapshot
          }
        )
      end

      def log_summary(summary)
        Rails.logger.info(
          JSON.generate({
            event: 'disputes.alert_deadlines',
            scanned: summary[:scanned],
            tiers_recorded: summary[:tiers_recorded],
            alerted: summary[:alerted],
            backfilled: summary[:backfilled],
            auto_lost: summary[:auto_lost],
            skipped_submitted: summary[:skipped_submitted],
            failed: summary[:failed]
          })
        )
      end
    end
  end
end
