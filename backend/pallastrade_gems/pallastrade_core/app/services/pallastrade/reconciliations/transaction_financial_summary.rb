# frozen_string_literal: true

# PALLAS-CUSTOM: FIN-P4-7 (PRD-20260906-payments-fin-p4-7)
#
# Reconciliations::TransactionFinancialSummary —— CommerceTransaction 级财务摘要（§25）的
# **transient 只读 VO**。
#
# 字段（P4 §25）：
#   commercial_amount / cash_captured / store_credit_applied / offline_payment_recorded /
#   gross_value_received / refund_total / net_customer_value / allocation_total /
#   unallocated_amount / currency / provider_fee / provider_net / reconciliation_status。
#
# 语义：
#   - gross_value_received = cash_captured + store_credit_applied + offline_payment_recorded
#     （资金流入总额，INV-05：ORDER_ALLOCATION 非 cash，不计入）。
#   - net_customer_value = gross_value_received − refund_total。
#   - unallocated_amount = cash_captured − allocation_total（组合拆分后仍未归属 order 的现金；
#     单订单无 split 时为 cash_captured —— 由 ReconcileTransaction 语义决定是否核对）。
#   - short_paid?（cash_captured < commercial_amount）/ overpaid?（cash_captured > commercial_amount）
#     —— AC-4016 short payment 是合法业务态，不是 ledger error。
#   - 只读：本 VO 是 reconcile 纯函数输出，不触发任何本地写 / provider mutation / 自动资金动作。
#   - 不落表（§25 首版不必落表；P4-8 决定持久化形态）。构造后 freeze。
module PallasTrade
  module Reconciliations
    class TransactionFinancialSummary
      # 构造字段（attr_reader + initialize 白名单）
      CORE_ATTRIBUTES = %i[
        commercial_amount cash_captured store_credit_applied offline_payment_recorded
        refund_total allocation_total currency provider_fee provider_net reconciliation_status
      ].freeze
      # 派生 helper（to_h/as_json 追加；不参与构造）
      DERIVED = %i[gross_value_received net_customer_value unallocated_amount].freeze
      OUTPUT_ATTRIBUTES = (CORE_ATTRIBUTES + DERIVED).freeze

      attr_reader(*CORE_ATTRIBUTES)

      def initialize(commercial_amount:, cash_captured:, store_credit_applied:, offline_payment_recorded:,
                     refund_total:, allocation_total:, currency:, provider_fee: nil, provider_net: nil,
                     reconciliation_status: nil)
        @commercial_amount = commercial_amount.to_d.round(2)
        @cash_captured = cash_captured.to_d.round(2)
        @store_credit_applied = store_credit_applied.to_d.round(2)
        @offline_payment_recorded = offline_payment_recorded.to_d.round(2)
        @refund_total = refund_total.to_d.round(2)
        @allocation_total = allocation_total.to_d.round(2)
        @currency = currency.to_s.presence
        @provider_fee = provider_fee&.to_d&.round(2)
        @provider_net = provider_net&.to_d&.round(2)
        @reconciliation_status = reconciliation_status
        freeze
      end

      # 资金流入总额（ORDER_ALLOCATION 非 cash，不计入——INV-05/AC-4013）
      def gross_value_received
        (cash_captured + store_credit_applied + offline_payment_recorded).round(2)
      end

      # 客户净值 = 流入 − 退款
      def net_customer_value
        (gross_value_received - refund_total).round(2)
      end

      # 组合拆分后仍未归属 order 的现金
      def unallocated_amount
        (cash_captured - allocation_total).round(2)
      end

      def short_paid?
        cash_captured < commercial_amount
      end

      def overpaid?
        cash_captured > commercial_amount
      end

      def to_h
        OUTPUT_ATTRIBUTES.index_with { |a| public_send(a) }
      end

      def as_json(*)
        to_h
      end
    end
  end
end
