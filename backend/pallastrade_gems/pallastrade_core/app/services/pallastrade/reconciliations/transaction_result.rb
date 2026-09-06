# frozen_string_literal: true

# PALLAS-CUSTOM: FIN-P4-7 (PRD-20260906-payments-fin-p4-7)
#
# Reconciliations::TransactionResult —— CommerceTransaction 级核对结果的 **transient 只读 VO**。
#
# 语义（P4 §39/§42）：
#   - status ∈ PENDING / MATCHED / MISMATCH / NEEDS_ATTENTION / NOT_APPLICABLE / UNSUPPORTED（§39）。
#   - reasons[] ∈ §42 交易级原因码：ALLOCATION_MISMATCH / REFUND_MISMATCH / AMOUNT_MISMATCH /
#     COMMERCIAL_AMOUNT_MISMATCH / JOURNAL_POSTING_MISSING / SETTLEMENT_PENDING /
#     PROVIDER_UNAVAILABLE / PROVIDER_CONTRACT_UNSUPPORTED / …（源级原因由各 SourceResult 承载）。
#   - summary（TransactionFinancialSummary §25）承载交易级金额聚合；source_reconciliations[]
#     承载逐 payment/refund 的源级 SourceResult（供 P4-8 admin 展示明细）。
#   - 只读：本 VO 是 reconcile 纯函数输出，不触发任何本地写 / provider mutation / 自动资金动作。
#   - 不落表（§25 首版不必落表；P4-8 决定 reconciliation 持久化形态）。构造后 freeze。
module PallasTrade
  module Reconciliations
    class TransactionResult
      STATUSES = %w[PENDING MATCHED MISMATCH NEEDS_ATTENTION NOT_APPLICABLE UNSUPPORTED].freeze

      STATUSES.each { |s| const_set(s, s) }

      ATTRIBUTES = %i[
        transaction_id status reasons summary source_reconciliations
        provider_gross_amount provider_currency provider_fee provider_net observed_at
      ].freeze

      attr_reader(*ATTRIBUTES)

      def initialize(transaction_id:, status:, reasons: [], summary: nil, source_reconciliations: [],
                     provider_gross_amount: nil, provider_currency: nil, provider_fee: nil, provider_net: nil,
                     observed_at: nil)
        @transaction_id = transaction_id
        @status = status
        @reasons = Array(reasons).freeze
        @summary = summary
        @source_reconciliations = Array(source_reconciliations).freeze
        @provider_gross_amount = provider_gross_amount&.to_d&.round(2)
        @provider_currency = provider_currency.to_s.presence
        @provider_fee = provider_fee&.to_d&.round(2)
        @provider_net = provider_net&.to_d&.round(2)
        @observed_at = observed_at || Time.current
        freeze
      end

      def matched?
        status == MATCHED
      end

      def mismatch?
        status == MISMATCH
      end

      def pending?
        status == PENDING
      end

      def needs_attention?
        status == NEEDS_ATTENTION
      end

      def not_applicable?
        status == NOT_APPLICABLE
      end

      def unsupported?
        status == UNSUPPORTED
      end

      def to_h
        ATTRIBUTES.index_with { |a| public_send(a) }
      end

      def as_json(*)
        to_h
      end
    end
  end
end
