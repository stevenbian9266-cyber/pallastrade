# frozen_string_literal: true

# PALLAS-CUSTOM: DSP-P7-3 (PRD-20260912-payments-dsp-p7-3-dispute-posting-and-reconcile)
#
# Reconciliations::ReconcileDispute —— Dispute ↔ 本地 Journal 的**只读**对账（FR-P73-10）。
#
# 定位：`ReconcilePayment` / `ReconcileRefund` 的争议域同类；**不做** provider 源级核对
#   （那是 P7-4 Evidence / P7-2 `fetch_dispute_details` 的职责），只回答：
#   「该 dispute 迄今可证的**现金移动**，是否都已在不可变 Journal 中恰好一次、金额币种一致」。
#
# 期望账行 = funds 时间戳集合（**不是**「当前最强事实」）：
#   - `funds_withdrawn_at`  → 期望一条 `DISPUTE_FUNDS_WITHDRAWN`（负数）
#   - `funds_reinstated_at` → 期望一条 `DISPUTE_FUNDS_REINSTATED`（正数）
#   - 终态（won/lost）属**非现金事实**，永不派生账行；否则一个已 `won` 的争议会被误判缺账
#     （P7-2 `fact_type_for` 终态优先，见 `ResolveDispute` 的 fact_type 提示说明）。
#
# 分类（封闭枚举，稳定可断言）：
#   - `aligned`        所有期望账行存在且金额/币种一致
#   - `journal_missing` 期望账行缺失（subscriber 丢失 / 吞异常窗口 → P7-5 补记输入）
#   - `amount_mismatch` 期望账行存在但金额或币种不符
#   - `orphan_entry`   有账行但当前事实不可证（未证实 / 未知来源）→ 需人工
#   - `not_applicable` 无期望账行且无账行（非现金事实 / 未证实事实：无入账义务）
#
# 只读/幂等（FR-P73-10/11）：零写、零 provider 网络 I/O、纯函数可重跑（AC-P73-10 快照断言）。
module PallasTrade
  module Reconciliations
    class ReconcileDispute
      prepend PallasTrade::ServiceModule::Base

      CLASSIFICATIONS = %w[aligned journal_missing amount_mismatch orphan_entry not_applicable].freeze
      # 本对账不触网：仅比对本域事实与本地账本
      CAPABILITY = 'JOURNAL_LOCAL_ONLY'
      # funds 时间戳 → 期望账行类型（唯一映射来源）
      EXPECTATION_BY_ATTRIBUTE = {
        'funds_withdrawn_at' => 'DISPUTE_FUNDS_WITHDRAWN',
        'funds_reinstated_at' => 'DISPUTE_FUNDS_REINSTATED'
      }.freeze

      # @param dispute [PallasTrade::Dispute]
      # @return [PallasTrade::ServiceModule::Result] success(Hash) / failure(dispute, message)
      def call(dispute:)
        return failure(nil, 'Dispute not found') if dispute.nil?

        resolution = PallasTrade::Disputes::ResolveFact.call(dispute: dispute)
        return failure(dispute, resolution.error) unless resolution.success?

        fact = PallasTrade::FinancialFacts::ResolveDispute.call(dispute: dispute).value
        entries = PallasTrade::FinancialLedgerEntry.where(dispute_id: dispute.id).order(:effective_at, :id)
        expectations = expectations_for(dispute, fact)
        verdict = classify(fact, entries, expectations)

        success(result({ dispute: dispute, fact: fact, resolution: resolution.value,
                         entries: entries, expectations: expectations, verdict: verdict }))
      end

      private

      def expectations_for(dispute, fact)
        amount = fact&.amount.to_d.abs

        EXPECTATION_BY_ATTRIBUTE.filter_map do |attribute, entry_type|
          next if dispute.public_send(attribute).blank?

          # 方向约定（FR-P73-08）：扣回为流出（负）、返还为流入（正）
          signed = entry_type == 'DISPUTE_FUNDS_WITHDRAWN' ? -amount : amount
          { entry_type: entry_type, amount: signed }
        end
      end

      # @return [Array(String, Array<String>)] [classification, reasons]
      def classify(fact, entries, expectations)
        unless fact&.confirmed?
          reason = fact.nil? ? 'fact_unavailable' : PallasTrade::FinancialLedger::PostDispute.skip_reason_for(fact)
          return ['orphan_entry', ['ORPHAN_ENTRY', reason].compact] if entries.any?

          return ['not_applicable', [reason].compact]
        end

        return ['orphan_entry', ['UNEXPECTED_ENTRY']] if expectations.empty? && entries.any?
        return ['not_applicable', ['NO_CASH_FACT']] if expectations.empty?

        missing = expectations.reject { |exp| entry_for(entries, exp[:entry_type]) }
        return ['journal_missing', missing.map { |exp| "JOURNAL_POSTING_MISSING_#{exp[:entry_type]}" }] if missing.any?

        mismatch = expectations.filter_map { |exp| mismatch_reason(exp, entries, fact) }.first
        return ['amount_mismatch', [mismatch]] if mismatch

        ['aligned', []]
      end

      def entry_for(entries, entry_type)
        entries.find { |entry| entry.entry_type == entry_type }
      end

      def mismatch_reason(expectation, entries, fact)
        entry = entry_for(entries, expectation[:entry_type])
        return nil if entry.nil?

        if fact.currency.present? && entry.currency.present? &&
            fact.currency.to_s.upcase != entry.currency.to_s.upcase
          return 'CURRENCY_MISMATCH'
        end
        return 'AMOUNT_MISMATCH' if entry.amount.to_d.abs.round(4) != expectation[:amount].abs.round(4)

        nil
      end

      # @param context [Hash] 单参上下文（避免超长参数表；都是本次对账的局部事实）
      def result(context)
        classification, reasons = context[:verdict]
        dispute = context[:dispute]
        fact = context[:fact]

        {
          classification: classification,
          dispute_id: dispute.prefixed_id,
          local_state: dispute.state,
          resolution: context[:resolution].resolution,
          fact_type: fact&.fact_type,
          fact_status: fact&.status,
          skip_reason: fact.nil? ? 'fact_unavailable' : PallasTrade::FinancialLedger::PostDispute.skip_reason_for(fact),
          expected_entries: context[:expectations],
          entries: context[:entries].map { |entry| entry_summary(entry) },
          reasons: reasons,
          capability: CAPABILITY,
          observed_at: Time.current
        }
      end

      def entry_summary(entry)
        {
          id: entry.prefixed_id,
          entry_type: entry.entry_type,
          amount: entry.amount,
          currency: entry.currency,
          state: entry.state,
          effective_at: entry.effective_at
        }
      end
    end
  end
end
