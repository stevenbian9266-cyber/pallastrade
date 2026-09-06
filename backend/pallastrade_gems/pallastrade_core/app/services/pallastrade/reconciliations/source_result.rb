# frozen_string_literal: true

# PALLAS-CUSTOM: FIN-P4-6 (PRD-20260906-payments-fin-p4-6)
#
# Reconciliations::SourceResult —— 源级（Payment/Refund ↔ PSP）核对结果的**transient 只读 VO**。
#
# 语义（P4 §39/§42）：
#   - status ∈ PENDING / MATCHED / MISMATCH / NEEDS_ATTENTION / NOT_APPLICABLE / UNSUPPORTED。
#   - reasons[] ∈ §42 原因码（AMOUNT_MISMATCH/CURRENCY_MISMATCH/LOCAL_PAYMENT_MISSING/
#     PROVIDER_PAYMENT_MISSING/REFUND_MISMATCH/SETTLEMENT_PENDING/PROVIDER_UNAVAILABLE/
#     PROVIDER_CONTRACT_UNSUPPORTED/UNLINKED_LEGACY_PAYMENT/AMBIGUOUS_CAPTURE…）。
#   - 只读：本 VO 是 reconcile 纯函数输出，不触发任何本地写 / provider mutation / 自动资金动作。
#   - 不落表（P4 §34：可作为 reconciliation JSON snapshot，P4-7/8 决定持久化形态）。
# 构造后 freeze。
module PallasTrade
  module Reconciliations
    class SourceResult
      STATUSES = %w[PENDING MATCHED MISMATCH NEEDS_ATTENTION NOT_APPLICABLE UNSUPPORTED].freeze

      STATUSES.each { |s| const_set(s, s) }

      ATTRIBUTES = %i[
        source_type source_id status reasons
        local_amount local_currency
        provider_gross_amount provider_currency provider_settlement_status
        provider_payment_reference provider_charge_reference
        provider_fee provider_net
        provider_error observed_at
      ].freeze

      attr_reader(*ATTRIBUTES)

      def initialize(**attrs)
        unknown = attrs.keys - ATTRIBUTES
        raise ArgumentError, "Unknown SourceResult attributes: #{unknown.join(', ')}" if unknown.any?

        ATTRIBUTES.each { |a| instance_variable_set("@#{a}", attrs.fetch(a, nil)) }
        @provider_fee = @provider_fee&.to_d&.round(2)
        @provider_net = @provider_net&.to_d&.round(2)
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
