# frozen_string_literal: true

# PALLAS-CUSTOM: FIN-P4-1 (PRD-20260905-payments-fin-p4-1)
#
# FinancialFacts::OwnershipResolver —— Payment/Refund → CommerceTransaction 的可靠归属解析
# （FR-4P1-22~25；FIN-INV-11/12）。
#
# 统一 call 入口（ServiceModule::Base 约定）：call(payment: …) 或 call(refund: …)。
# 可靠性顺序（FR-4P1-22/29）：
#   1. 显式传入的 transaction context
#   2. Payment → PaymentSession（payment_session.transaction_id → commerce_transactions）
#   3. Payment → PaymentCombination（commerce_transactions.payment_combination_id）
#   4. 无可靠路径 → transaction: nil（不伪造 ownership）
#
# 禁止用 Payment#transaction_id / response_code / pi_ / cs_ 等 PSP reference 推断 CommerceTransaction
# （FR-4P1-23）。本类只走 AR 关联，天然满足。
module PallasTrade
  module FinancialFacts
    class OwnershipResolver
      prepend PallasTrade::ServiceModule::Base

      # @param payment [PallasTrade::Payment, nil]
      # @param refund [PallasTrade::Refund, nil]
      # @param explicit_transaction [PallasTrade::CommerceTransaction, nil]
      # @return [PallasTrade::ServiceModule::Result]
      #   success({ transaction: [CommerceTransaction, nil],
      #             path: :explicit|:payment_session|:payment_combination|:none|:no_payment })
      def call(payment: nil, refund: nil, explicit_transaction: nil)
        if payment.present?
          resolve(explicit_transaction, session_transaction(payment), combination_transaction(payment))
        elsif refund.present?
          resolve_for_refund(refund, explicit_transaction)
        else
          failure(nil, 'Payment or refund required')
        end
      end

      private

      def resolve_for_refund(refund, explicit_transaction)
        payment = refund.payment
        return success(transaction: nil, path: :no_payment) if payment.nil?

        resolve(explicit_transaction, session_transaction(payment), combination_transaction(payment))
      end

      def resolve(explicit_transaction, session_transaction, combination_transaction)
        return success(transaction: explicit_transaction, path: :explicit) if explicit_transaction.present?
        return success(transaction: session_transaction, path: :payment_session) if session_transaction.present?
        return success(transaction: combination_transaction, path: :payment_combination) if combination_transaction.present?

        success(transaction: nil, path: :none)
      end

      def session_transaction(payment)
        payment.payment_session&.commerce_transaction
      end

      def combination_transaction(payment)
        payment.payment_combination&.commerce_transaction
      end
    end
  end
end
