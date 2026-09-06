# frozen_string_literal: true

# PALLAS-CUSTOM: FIN-P4-1 (PRD-20260905-payments-fin-p4-1)
#
# FinancialFacts::CaptureEvidencePolicy —— 冻结每类资金载体的 captured predicate
# （FR-4P1-08~14；FIN-INV-02/03：completed ≠ captured；授权 ≠ 捕获）。
#
# 禁止用裸 `payment.completed?` 作为所有 provider 的 CASH_CAPTURED 统一判定（FR-4P1-08）。
# PSP_CASH captured 证据（本地、只读，不发 provider 网络请求）：
#   - 单订单 Stripe auto-capture / manual capture 成功：payment.completed? 且存在 PaymentCaptureEvent
#     （confirm!(auto)/purchase! 在 complete 时写 capture event；capture!（manual）成功时写 capture event）
#   - 组合 Payment（挂 payment_combination，Settlement 直接 complete! 不写 capture event）：
#     payment.completed? 且组合 succeeded（FR-4P1-11）
#   - 授权未捕获：payment.pending? → :authorized_only（FR-4P1-10）
#   - 证据冲突/缺失：:ambiguous（FR-4P1-14，绝不选“最方便”状态）
#   - 终态失败/void/invalid/未开始：:unpaid
#
# verdict 集合：:captured | :authorized_only | :unpaid | :ambiguous（FR-4P1-13 的 legacy unsupported
# 由 ResolvePayment 基于 instrument/capability 输出 UNSUPPORTED，不在此判定）。
module PallasTrade
  module FinancialFacts
    class CaptureEvidencePolicy
      prepend PallasTrade::ServiceModule::Base

      # 已冻结 captured predicate 的本地解析 provider（STI type 前缀/全名）。
      # Stripe 与 Bogus（测试）具备；Adyen/PayPal legacy 本包不提供 captured predicate → 由 Resolver 输出 unsupported。
      LOCAL_CAPTURE_RESOLUTION_TYPES = [
        'PallasTradeStripe::Gateway',
        'PallasTrade::Gateway::Bogus'
      ].freeze

      # @param payment [PallasTrade::Payment]
      # @return [PallasTrade::ServiceModule::Result]
      #   success({ verdict:, evidence: [Symbol], captured_amount: [Numeric, nil] })
      def call(payment:)
        return failure(nil, 'Payment not found') if payment.nil?
        return failure(payment, 'Payment method missing') if payment.payment_method.nil?

        success(evaluate(payment))
      end

      # 本地 captured 解析能力（FR-4P1-32/33/35）——provider adapter boundary，不引 SDK。
      # @return [Boolean]
      def self.local_capture_resolution_supported?(payment_method)
        return false if payment_method.nil?

        LOCAL_CAPTURE_RESOLUTION_TYPES.include?(payment_method.type)
      end

      # provider reconciliation capability（FR-4P1-32~35）。本包未实现任何 PSP financial
      # reconciliation（FIN-P4-5 才做）→ 真实 PSP 一律 UNSUPPORTED，StoreCredit/Offline 为 NOT_APPLICABLE。
      # @return [String] PROVIDER_RECONCILIATION_SUPPORTED / PROVIDER_RECONCILIATION_UNSUPPORTED / NOT_APPLICABLE
      def self.provider_reconciliation_capability(payment_method)
        return 'NOT_APPLICABLE' if payment_method.nil?
        return 'NOT_APPLICABLE' if payment_method.is_a?(PallasTrade::PaymentMethod::StoreCredit)
        return 'NOT_APPLICABLE' if payment_method.is_a?(PallasTrade::PaymentMethod::Check)

        'PROVIDER_RECONCILIATION_UNSUPPORTED'
      end

      private

      def evaluate(payment)
        if payment.completed?
          captured_evidence(payment)
        elsif payment.pending?
          # pending = authorized but not captured（payments SKILL 状态机；FR-4P1-10）
          { verdict: :authorized_only, evidence: [:payment_pending_authorized], captured_amount: nil }
        elsif payment.processing?
          { verdict: :ambiguous, evidence: [:payment_processing_inflight], captured_amount: nil }
        elsif %w[failed void invalid].include?(payment.state)
          { verdict: :unpaid, evidence: [:"payment_#{payment.state}"], captured_amount: nil }
        elsif payment.checkout?
          { verdict: :unpaid, evidence: [:payment_checkout_not_started], captured_amount: nil }
        else
          { verdict: :ambiguous, evidence: [:unrecognized_payment_state], captured_amount: nil }
        end
      end

      # completed 不等于 captured：必须有组合入账证据或 capture event，否则证据冲突 → ambiguous。
      def captured_evidence(payment)
        if combination_payment?(payment)
          return { verdict: :ambiguous, evidence: [:combination_payment_missing], captured_amount: nil } if payment.payment_combination.nil?
          return { verdict: :ambiguous, evidence: [:combination_not_succeeded], captured_amount: nil } unless payment.payment_combination.succeeded?

          return { verdict: :captured, evidence: [:payment_completed, :combination_succeeded], captured_amount: payment.amount }
        end

        events = payment.capture_events.to_a
        if events.any?
          # partial capture：capture_events 累计为真实捕获额；空/0 兜底回 payment.amount（含 reason）
          sum = events.sum { |e| e.amount.to_d }
          captured = sum.positive? ? sum.to_f : payment.amount.to_f
          { verdict: :captured, evidence: [:payment_completed, :capture_event_present], captured_amount: captured }
        else
          { verdict: :ambiguous, evidence: [:completed_without_capture_evidence], captured_amount: nil }
        end
      end

      def combination_payment?(payment)
        payment.payment_combination_id.present?
      end
    end
  end
end
