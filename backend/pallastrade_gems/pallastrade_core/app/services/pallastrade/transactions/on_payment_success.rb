# frozen_string_literal: true

# PALLAS-CUSTOM: TXN-P2-5 (PRD-20260904-payments-txn-p2-5)
#
# Transactions::OnPaymentSuccess —— Transaction Payment Handler 首版（P2 源文档
# §21/AC-2015）。资金已在本会话/本入口验证成功（本地 payment 落账后调用），
# 统一决定"订单/交易怎么完成"：
#
#   ① session 挂 PaymentCombination → PaymentCombinations::Complete（组合
#      adapter 保留；先入账→逐成员完成→补偿队列）
#   ② session 挂 CommerceTransaction（TXN-P2-2 起）→ 锁内 confirm_payment!
#      （payment_pending→payment_confirmed，AC-2009）→ Transactions::Finalize
#      （统一完成参与者 + transaction → completed）
#   ③ 无 transaction（legacy/存量）→ 原 Carts::Complete 行为（carts_complete_service
#      unless order.completed?），Strangler 下行为不变
#
# 幂等：Finalize/session.completed 短路；不创建新 Payment（INV-04）。
module PallasTrade
  module Transactions
    class OnPaymentSuccess
      prepend PallasTrade::ServiceModule::Base

      # @param payment_session [PallasTrade::PaymentSession]
      # @return Result success({ mode: :combination | :finalized | :legacy_completed,
      #                          transaction: nil | CommerceTransaction })
      def call(payment_session:)
        return failure(nil, 'Payment session not found') if payment_session.nil?

        if payment_session.payment_combination.present?
          result = PallasTrade::Payments::PaymentCombinations::Complete.call(payment_session: payment_session)
          return result unless result.success?

          return success(mode: :combination, transaction: payment_session.commerce_transaction)
        end

        transaction = payment_session.commerce_transaction
        if transaction.nil?
          order = payment_session.order
          PallasTrade::Dependencies.carts_complete_service.constantize.call(cart: order) unless order.nil? || order.completed?
          return success(mode: :legacy_completed, transaction: nil)
        end

        confirm_and_finalize(transaction)
      end

      private

      def confirm_and_finalize(transaction)
        transaction.with_lock do
          tx = transaction.reload
          return success(mode: :finalized, transaction: tx) if tx.state == 'completed'

          tx.confirm_payment! if tx.state == 'payment_pending'
          # recovery_required/manual_review/canceled → 交 Recover/人工（不动）
          unless %w[payment_confirmed finalizing].include?(tx.state)
            return failure(tx, {
                             code: 'commerce_transaction_not_finalizable',
                             state: tx.state,
                             message: "Transaction '#{tx.state}' is not finalizable on payment success"
                           })
          end
        end

        result = PallasTrade::Transactions::Finalize.call(transaction: transaction)
        return result unless result.success?

        success(mode: :finalized, transaction: transaction.reload)
      end
    end
  end
end
