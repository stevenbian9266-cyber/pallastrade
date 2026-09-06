# frozen_string_literal: true

# PALLAS-CUSTOM: FIN-P4-1 (PRD-20260905-payments-fin-p4-1)
#
# FinancialFacts::InstrumentClassifier —— 根据 PaymentMethod 返回标准资金载体分类
# （FR-4P1-05~07）：
#   PSP_CASH     —— gateway 型（Stripe/Adyen/PayPal/Bogus/Custom…，provider_class 可调用）
#   STORE_CREDIT —— PallasTrade::PaymentMethod::StoreCredit
#   OFFLINE      —— PallasTrade::PaymentMethod::Check（后台人工/线下）
#   UNKNOWN      —— 未知/legacy，禁止默认归类 PSP_CASH（FR-4P1-07）
#
# 判定基于对象类型与 provider_class 鸭子类型，不引用任何 Stripe/Adyen SDK 类（NFR Provider 隔离）。
module PallasTrade
  module FinancialFacts
    class InstrumentClassifier
      prepend PallasTrade::ServiceModule::Base

      # @param payment_method [PallasTrade::PaymentMethod, nil]
      # @return [PallasTrade::ServiceModule::Result] success({ instrument_class:, provider: })
      #   provider = payment_method.type（STI 类名，如 'PallasTradeStripe::Gateway'）
      def call(payment_method:)
        return failure(nil, 'Payment method not found') if payment_method.nil?

        success(
          instrument_class: classify(payment_method),
          provider: payment_method.type
        )
      end

      private

      def classify(payment_method)
        return PallasTrade::FinancialFact::STORE_CREDIT if payment_method.is_a?(PallasTrade::PaymentMethod::StoreCredit)
        return PallasTrade::FinancialFact::OFFLINE if payment_method.is_a?(PallasTrade::PaymentMethod::Check)

        psp_gateway?(payment_method) ? PallasTrade::FinancialFact::PSP_CASH : PallasTrade::FinancialFact::UNKNOWN
      end

      # gateway 子类实现 provider_class 并返回自身；base PaymentMethod / Check / StoreCredit
      # 未覆写 → raise NotImplementedError。Base 判定防止把非 gateway 的 payment method 误归 PSP_CASH。
      def psp_gateway?(payment_method)
        payment_method.provider_class
        true
      rescue NotImplementedError
        false
      end
    end
  end
end
