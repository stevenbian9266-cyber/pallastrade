# frozen_string_literal: true

# PALLAS-CUSTOM: FIN-P4-6 (PRD-20260906-payments-fin-p4-6)
#
# Reconciliations::ReconcileRefund —— Refund ↔ PSP 源级只读核对（P4 §62/§37）。
#
# 语义：
#   - local Refund（amount/currency/transaction_id=provider refund reference）↔ provider Refund
#     （`PaymentMethod#fetch_refund_details`，FIN-P4-6 新增只读契约；Stripe Refund.retrieve / Bogus 替身）。
#   - 状态（§39/§42）：MATCHED（金额/币种/引用一致）/ MISMATCH（REFUND_MISMATCH/AMOUNT_MISMATCH/
#     CURRENCY_MISMATCH）/ PENDING（provider refund 尚未 succeeded）/ NEEDS_ATTENTION（provider 不可用 /
#     本地 refund 无 transaction_id → UNLINKED_LEGACY_PAYMENT）/ NOT_APPLICABLE（StoreCredit/Check）/
#     UNSUPPORTED（无契约 legacy）。
#   - 只读/幂等（§44/AC-4023/4024）：零写、绝不自动 refund/charge；纯函数可重跑。
module PallasTrade
  module Reconciliations
    class ReconcileRefund
      prepend PallasTrade::ServiceModule::Base

      # @param refund [PallasTrade::Refund]
      # @return [PallasTrade::ServiceModule::Result] success(SourceResult) / failure(refund, message)
      def call(refund:)
        return failure(nil, 'Refund not found') if refund.nil?

        pm = refund.payment&.payment_method
        return success(not_applicable(refund)) if not_applicable?(pm)
        return success(unsupported(refund)) unless self.class.implements_refund_details?(pm)
        return success(attention(refund, 'UNLINKED_LEGACY_PAYMENT', nil)) if refund.transaction_id.blank?

        provider = fetch_refund_details(refund, pm)
        return success(provider) if provider.is_a?(PallasTrade::Reconciliations::SourceResult)

        return success(pending(refund, provider)) if provider[:status].present? && provider[:status].to_s != 'succeeded'

        compare(refund, provider)
      end

      # capability：fetch_refund_details 的 method owner 非 base PaymentMethod = 真实现。
      def self.implements_refund_details?(payment_method)
        return false unless payment_method.respond_to?(:fetch_refund_details)

        payment_method.method(:fetch_refund_details).owner != PallasTrade::PaymentMethod
      end

      private

      # @return [Hash] provider refund details 或 SourceResult（PROVIDER_UNAVAILABLE）
      def fetch_refund_details(refund, pm)
        pm.fetch_refund_details(refund: refund)
      rescue PallasTrade::Core::GatewayError, (defined?(Stripe::StripeError) ? Stripe::StripeError : StandardError) => e
        attention(refund, 'PROVIDER_UNAVAILABLE', nil, e)
      end

      def compare(refund, provider)
        local_currency = refund.currency.to_s.upcase
        provider_currency = provider[:currency].to_s.upcase
        if provider_currency.present? && local_currency.present? && provider_currency != local_currency
          return success(result(SourceResult::MISMATCH, refund, ['CURRENCY_MISMATCH'], provider))
        end

        if provider[:amount].nil? || refund.amount.nil? ||
           provider[:amount].to_d.round(2) != refund.amount.to_d.round(2)
          return success(result(SourceResult::MISMATCH, refund, ['REFUND_MISMATCH'], provider))
        end

        success(result(SourceResult::MATCHED, refund, [], provider))
      end

      # ---- builders ------------------------------------------------------

      def result(status, refund, reasons, provider, provider_error = nil)
        PallasTrade::Reconciliations::SourceResult.new(
          source_type: :refund,
          source_id: refund.prefixed_id,
          status: status,
          reasons: Array(reasons),
          local_amount: refund.amount,
          local_currency: refund.currency,
          provider_gross_amount: provider&.dig(:amount),
          provider_currency: provider&.dig(:currency),
          provider_settlement_status: provider&.dig(:status),
          provider_payment_reference: provider&.dig(:provider_refund_reference),
          provider_charge_reference: nil,
          provider_error: provider_error&.message,
          observed_at: Time.current
        )
      end

      def pending(refund, provider)
        result(SourceResult::PENDING, refund, ['SETTLEMENT_PENDING'], provider)
      end

      def attention(refund, reason, provider, provider_error = nil)
        result(SourceResult::NEEDS_ATTENTION, refund, [reason], provider, provider_error)
      end

      def not_applicable(refund)
        result(SourceResult::NOT_APPLICABLE, refund, [], nil)
      end

      def unsupported(refund)
        result(SourceResult::UNSUPPORTED, refund, ['PROVIDER_CONTRACT_UNSUPPORTED'], nil)
      end

      def not_applicable?(pm)
        pm.nil? || pm.is_a?(PallasTrade::PaymentMethod::StoreCredit) || pm.is_a?(PallasTrade::PaymentMethod::Check)
      end
    end
  end
end
