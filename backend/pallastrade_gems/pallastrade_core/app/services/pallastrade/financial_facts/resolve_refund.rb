# frozen_string_literal: true

# PALLAS-CUSTOM: FIN-P4-1 (PRD-20260905-payments-fin-p4-1)
#
# FinancialFacts::ResolveRefund —— 把单个 Refund 解析为标准 FinancialFact（FR-4P1-26~31）。
#
# 语义：
#   - Refund 创建即同步 perform!（after_create）；成功时持久化 provider refund reference
#     （refunds.transaction_id = re_/provider ref，FR-4P1-27）。transaction_id 存在 → REFUND_SUCCEEDED/CONFIRMED。
#   - 失败执行会 raise（无持久化成功行）；但历史/手工记录可能 transaction_id 缺失 →
#     NONE + AMBIGUOUS（不猜成功，FR-4P1-27/INV-09）。
#   - amount 为独立事实；multiple/partial refund 每次分别解析（FR-4P1-28），不聚合。
#   - provider 字段标准化：refund.transaction_id → provider_refund_reference（FR-4P1-31）。
#   - ownership：Refund → Payment → PaymentSession / PaymentCombination → CommerceTransaction（FR-4P1-29）；
#     组合退款的 Order target 经 reimbursement 链推导只用于 evidence，不复制一笔退款到多 Order（FR-4P1-30）。
#
# 只读边界（FR-4P1-38）：不创建/更新/删除记录，不执行任何 refund side effect。
module PallasTrade
  module FinancialFacts
    class ResolveRefund
      prepend PallasTrade::ServiceModule::Base

      # @param refund [PallasTrade::Refund]
      # @param transaction [PallasTrade::CommerceTransaction, nil] 显式 ownership context（可选）
      # @return [PallasTrade::ServiceModule::Result] success(PallasTrade::FinancialFact)
      def call(refund:, transaction: nil)
        return failure(nil, 'Refund not found') if refund.nil?

        ownership = PallasTrade::FinancialFacts::OwnershipResolver.call(
          refund: refund, explicit_transaction: transaction
        )
        return failure(refund, ownership.error) unless ownership.success?

        success(build_fact(refund, ownership.value))
      end

      private

      def build_fact(refund, ownership)
        payment = refund.payment
        instrument_class = instrument_class_for(payment)
        base = {
          instrument_class: instrument_class,
          commerce_transaction_id: ownership[:transaction]&.prefixed_id,
          order_id: refund.order&.prefixed_id,
          payment_id: payment&.prefixed_id,
          refund_id: refund.prefixed_id,
          payment_session_id: payment&.payment_session&.prefixed_id,
          payment_combination_id: payment&.payment_combination&.prefixed_id,
          provider: payment&.payment_method&.type,
          provider_payment_reference: payment&.response_code.presence || payment&.payment_session&.external_id.presence,
          provider_refund_reference: refund.transaction_id.presence,
          effective_at: refund.created_at
        }

        if refund.transaction_id.present?
          fact(base, PallasTrade::FinancialFact::REFUND_SUCCEEDED, PallasTrade::FinancialFact::CONFIRMED,
               refund.amount, currency_of(refund), [:refund_provider_reference_present], nil)
        else
          fact(base, PallasTrade::FinancialFact::NONE, PallasTrade::FinancialFact::AMBIGUOUS,
               nil, currency_of(refund), [:refund_success_not_provable], 'refund_success_not_provable')
        end
      end

      def instrument_class_for(payment)
        return PallasTrade::FinancialFact::UNKNOWN if payment.nil? || payment.payment_method.nil?

        PallasTrade::FinancialFacts::InstrumentClassifier.call(payment_method: payment.payment_method).value[:instrument_class]
      end

      def currency_of(refund)
        refund.currency.to_s.presence # Refund#currency delegate to payment（组合 payment 经 combination）
      end

      def fact(base, fact_type, status, amount, currency, evidence, reason_code)
        PallasTrade::FinancialFact.new(
          **base.merge(
            fact_type: fact_type,
            status: status,
            amount: amount,
            currency: currency,
            evidence: Array(evidence),
            reason_code: reason_code
          )
        )
      end
    end
  end
end
