# frozen_string_literal: true

# PALLAS-CUSTOM: FIN-P4-1 (PRD-20260905-payments-fin-p4-1)
#
# FinancialFacts::RetryPaymentSafetyPolicy —— 冻结 retry-payment 资金安全策略（FR-4P1-36/37）。
#
# 策略（RETRY_PAYMENT_FINANCIAL_SAFETY_POLICY）：
#   在旧 PaymentSession / provider reference 仍存在“可权威确认空间”时，新 PaymentSession/charge
#   前不得仅凭“本地未完成”判定安全重试 —— 必须先经 provider authoritative verification
#   （P2 Transactions::PaymentFactResolver 的 provider_query 已具备等价验证；本包只固化 policy，
#   不重写 P2 Recovery，FR-4P1-37）。
#
# 本类为纯查询策略（只读、无副作用、无 Result 包装），供 Recovery/reconciliation 消费方调用与测试。
module PallasTrade
  module FinancialFacts
    module RetryPaymentSafetyPolicy
      POLICY_NAME = 'RETRY_PAYMENT_FINANCIAL_SAFETY_POLICY'.freeze

      # 旧 attempt 是否存在可权威确认的 provider 空间 → 新 charge 前必须验证旧资金事实。
      # @param payment [PallasTrade::Payment, nil]
      # @return [Boolean]
      def self.requires_provider_verification_before_retry?(payment)
        return false if payment.nil?
        return false if payment.completed? # 已成功，无重试场景
        return false if payment.payment_method&.store_credit? # store credit 无 PSP provider 空间
        return false if payment.payment_method.is_a?(PallasTrade::PaymentMethod::Check) # offline 无 PSP provider 空间

        # session 仍持有 provider external_id，或 payment 已获 provider response_code（pi_/cs_）→ 有权威确认空间
        return true if payment.payment_session&.external_id.present?
        return true if payment.response_code.present?

        false
      end
    end
  end
end
