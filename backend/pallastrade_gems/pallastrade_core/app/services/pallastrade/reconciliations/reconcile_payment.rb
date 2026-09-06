# frozen_string_literal: true

# PALLAS-CUSTOM: FIN-P4-6 (PRD-20260906-payments-fin-p4-6)
#
# Reconciliations::ReconcilePayment —— Payment ↔ PSP 源级只读核对（P4 §62/§37 第一层）。
#
# 语义：
#   - local captured 唯一判定入口 = FIN-P4-1 `CaptureEvidencePolicy`（FIN-INV-02：禁止裸 payment.completed?）。
#   - provider 侧 = FIN-P4-5 `fetch_financial_details`（只读；cs_/pi_ 双模式）。
#   - 状态（§39）：MATCHED（local == provider settled 或两侧一致未结算）/ MISMATCH（金额/币种不符）/
#     PENDING（settlement pending，AC-4020 不误报）/ NEEDS_ATTENTION（provider 不可用、本地/提供方单侧缺失、
#     unlinked legacy）/ NOT_APPLICABLE（StoreCredit/Check，§40）/ UNSUPPORTED（无契约 legacy，§41）。
#   - 只读/幂等（§44/AC-4023/4024）：零本地写、零 provider mutation、绝不自动 charge/refund；纯函数可重跑。
module PallasTrade
  module Reconciliations
    class ReconcilePayment
      prepend PallasTrade::ServiceModule::Base

      # @param payment [PallasTrade::Payment]
      # @return [PallasTrade::ServiceModule::Result] success(SourceResult) / failure(payment, message)
      def call(payment:)
        return failure(nil, 'Payment not found') if payment.nil?

        pm = payment.payment_method
        return success(not_applicable(payment, :payment)) if not_applicable?(pm)
        return success(unsupported(payment, pm)) unless financial_details_supported?(pm)

        reconcile(payment, pm)
      end

      private

      def reconcile(payment, pm)
        session = payment.payment_session
        verdict = PallasTrade::FinancialFacts::CaptureEvidencePolicy.call(payment: payment).value
        local_captured = verdict[:verdict] == :captured
        local_amount = local_captured ? verdict[:captured_amount] : nil

        # 无 provider session 锚点 → 无法核对（不猜）；本地已 captured 也一并标注意（unlinked legacy）
        return success(attention(payment, :payment, 'UNLINKED_LEGACY_PAYMENT', local_amount, nil)) if session.nil?

        provider = fetch_details(payment, pm, session)
        return success(provider) if provider.is_a?(PallasTrade::Reconciliations::SourceResult)

        settlement = provider[:settlement_status].to_s
        provider_gross = provider[:gross_amount]
        provider_ref = provider[:provider_payment_reference]

        if local_captured
          return success(pending(payment, provider, local_amount)) unless settlement == 'settled'
          return success(attention(payment, :payment, 'PROVIDER_PAYMENT_MISSING', local_amount, provider)) if provider_ref.blank?

          compare(payment, provider, local_amount)
        elsif settlement == 'settled'
          success(attention(payment, :payment, 'LOCAL_PAYMENT_MISSING', nil, provider))
        else
          # 两侧一致未结算（authorization-only 等正常态）→ MATCHED
          success(matched(payment, provider))
        end
      end

      # provider 异常 → NEEDS_ATTENTION/PROVIDER_UNAVAILABLE（reconciliation 非支付流：捕获不 raise，可重跑）。
      # @return [Hash] provider financial details 或 SourceResult（PROVIDER_UNAVAILABLE）
      def fetch_details(payment, pm, session)
        pm.fetch_financial_details(payment_session: session)
      rescue PallasTrade::Core::GatewayError, (defined?(Stripe::StripeError) ? Stripe::StripeError : StandardError) => e
        attention(payment, :payment, 'PROVIDER_UNAVAILABLE', nil, nil, e)
      end

      def compare(payment, provider, local_amount)
        provider_amount = provider[:gross_amount]
        provider_currency = provider[:gross_currency].to_s.upcase
        local_currency = payment.currency.to_s.upcase

        if provider_currency.present? && local_currency.present? && provider_currency != local_currency
          return success(result(SourceResult::MISMATCH, :payment, payment.prefixed_id, ['CURRENCY_MISMATCH'],
                              local_amount, payment.currency, provider))
        end

        if provider_amount.nil? || local_amount.nil? || provider_amount.to_d.round(2) != local_amount.to_d.round(2)
          return success(result(SourceResult::MISMATCH, :payment, payment.prefixed_id, ['AMOUNT_MISMATCH'],
                              local_amount, payment.currency, provider))
        end

        success(matched(payment, provider, local_amount))
      end

      # ---- builders ------------------------------------------------------

      def result(status, source_type, source_id, reasons, local_amount, local_currency, provider, provider_error = nil)
        PallasTrade::Reconciliations::SourceResult.new(
          source_type: source_type,
          source_id: source_id,
          status: status,
          reasons: Array(reasons),
          local_amount: local_amount,
          local_currency: local_currency,
          provider_gross_amount: provider&.dig(:gross_amount),
          provider_currency: provider&.dig(:gross_currency),
          provider_settlement_status: provider&.dig(:settlement_status),
          provider_payment_reference: provider&.dig(:provider_payment_reference),
          provider_charge_reference: provider&.dig(:provider_charge_reference),
          provider_fee: provider&.dig(:fee_amount),
          provider_net: provider&.dig(:net_amount),
          provider_error: provider_error&.message,
          observed_at: Time.current
        )
      end

      def matched(payment, provider, local_amount = nil)
        result(SourceResult::MATCHED, :payment, payment.prefixed_id, [],
               local_amount || payment.amount, payment.currency, provider)
      end

      def pending(payment, provider, local_amount)
        result(SourceResult::PENDING, :payment, payment.prefixed_id, ['SETTLEMENT_PENDING'],
               local_amount, payment.currency, provider)
      end

      def attention(payment, source_type, reason, local_amount, provider, provider_error = nil)
        result(SourceResult::NEEDS_ATTENTION, source_type, payment.prefixed_id, [reason],
               local_amount, payment.currency, provider, provider_error)
      end

      def not_applicable(payment, source_type)
        result(SourceResult::NOT_APPLICABLE, source_type, payment.prefixed_id, [], nil, payment.currency, nil)
      end

      def unsupported(payment, pm)
        result(SourceResult::UNSUPPORTED, :payment, payment.prefixed_id, ['PROVIDER_CONTRACT_UNSUPPORTED'],
               nil, payment.currency, nil)
      end

      # ---- capability ----------------------------------------------------

      def not_applicable?(pm)
        pm.nil? || pm.is_a?(PallasTrade::PaymentMethod::StoreCredit) || pm.is_a?(PallasTrade::PaymentMethod::Check)
      end

      def financial_details_supported?(pm)
        PallasTrade::FinancialFacts::CaptureEvidencePolicy.implements_financial_details?(pm)
      end
    end
  end
end
