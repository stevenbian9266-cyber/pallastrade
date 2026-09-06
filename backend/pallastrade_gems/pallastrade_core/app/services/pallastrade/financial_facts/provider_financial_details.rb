# frozen_string_literal: true

# PALLAS-CUSTOM: FIN-P4-5 (PRD-20260906-payments-fin-p4-5)
#
# ProviderFinancialDetails —— provider 只读财务明细的**transient 值对象**（不落库、无 AR）。
#
# 语义（P4 §30-35）：
#   - 由 gateway `fetch_financial_details(payment_session:)` 返回的归一 Hash 构造（from_hash 白名单）。
#   - 记录 provider 权威财务 snapshot：references（payment pi_ / charge ch_ / balance_transaction txn_ /
#     refunds re_）+ gross / refund_total / fee / net + settlement_status + observed_at + raw evidence reference。
#   - fee/net/refund_total 可空：PI 未捕获/无 BalanceTransaction/无退款 → nil（不猜，FIN-INV-09）。
#   - 金额以 decimal（元）归一（Stripe cents 由 gateway 层换算）；currency 随附。
#   - 本 VO 是 **Reconciliation Fact**（P4 §35）：fee/net 不直接进 Journal（PSP_FEE/PSP_NET_SETTLEMENT
#     RESERVED 不变）；由 FIN-P4-6 Source Reconciliation 消费/持久化。
#
# 构造后 freeze（不可变，与 FinancialFact 一致）。
module PallasTrade
  module FinancialFacts
    class ProviderFinancialDetails
      SETTLEMENT_STATUSES = %w[
        settled pending requires_capture processing requires_action unpaid canceled failed expired
      ].freeze

      ATTRIBUTES = %i[
        provider provider_payment_reference provider_charge_reference
        provider_balance_transaction_reference provider_refund_references
        gross_amount gross_currency refund_total refund_currency
        fee_amount fee_currency net_amount net_currency
        settlement_status observed_at raw_reference
      ].freeze

      attr_reader(*ATTRIBUTES)

      # @param attrs [Hash] 仅接受 ATTRIBUTES 白名单键；构造后 freeze
      def initialize(**attrs)
        unknown = attrs.keys - ATTRIBUTES
        raise ArgumentError, "Unknown ProviderFinancialDetails attributes: #{unknown.join(', ')}" if unknown.any?

        ATTRIBUTES.each { |a| instance_variable_set("@#{a}", attrs.fetch(a, nil)) }
        freeze
      end

      # 从 gateway 归一 Hash 构造（同样白名单；字符串键兼容）。
      def self.from_hash(hash)
        return nil if hash.nil?

        normalized = hash.each_with_object({}) do |(k, v), acc|
          key = k.to_sym
          acc[key] = v if ATTRIBUTES.include?(key)
        end
        new(**normalized)
      end

      def settled?
        settlement_status.to_s == 'settled'
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
