# frozen_string_literal: true

# PALLAS-CUSTOM: TXN-P2-4 (PRD-20260904-payments-txn-p2-4)
#
# Transactions::Recover —— Recovery Engine 的权威状态解析与执行（P2 源文档
# §26-§31；AC-2011..2014；INV-01..08）。第一原则：**绝不 rescue→盲重试
# finalize，必须先确认资金事实**（§26）——每一步都经
# Transactions::PaymentFactResolver 判定（TXN-P2-3）后再行动。
#
# 分支（§27）：
#   UNPAID        → recovery_required → payment_pending（retry_payment，
#                   回到可支付态，不重复扣款——无资金入账）
#   AMBIGUOUS     → manual_review（不猜；finalizing 态先转 recovery_required）
#   PAID          → 参与者订单全部 completed → repair_completed（不重复完成）
#                 → 存在 incomplete → 锁外幂等 finalize 各参与者（复用
#                   Payments::CombinationMemberComplete：standard→Carts::Complete /
#                   legacy→Checkout::Complete；INV-08）→ retry_finalizing + complete
#
# 幂等（§29/AC-2013）：with_lock + 状态守卫 + recovery_attempts 计数 +
# last_error 记录；finalize 委托幂等原语。资金不回滚（INV-04/07）；
# decline 语义不变（INV-05，payment_pending 保持）。
module PallasTrade
  module Transactions
    class Recover
      prepend PallasTrade::ServiceModule::Base

      RECOVERABLE_STATES = %w[recovery_required finalizing].freeze

      # @param transaction [PallasTrade::CommerceTransaction]
      # @return Result success({ action: :retry_payment | :manual_review |
      #                          :repair_completed | :finalized,
      #                          transaction: }) | failure({ code:, ... })
      def call(transaction:)
        return failure(nil, 'Transaction not found') if transaction.nil?

        outcome = plan(transaction)
        return outcome unless outcome == :finalize

        finalize(transaction)
      end

      private

      # 锁内：守卫 + attempt 计数 + resolver 权威判定 + 快路径分支。
      # 返回 Result（已完成/失败）或 :finalize 标记（PAID+incomplete，
      # 释放锁后执行 finalize——provider/长操作在锁外，参考
      # PaymentCombinations::Complete 阶段 2 设计）。
      def plan(transaction)
        transaction.with_lock do
          tx = transaction.reload
          unless RECOVERABLE_STATES.include?(tx.state)
            return failure(tx, {
                             code: 'commerce_transaction_not_recoverable',
                             state: tx.state,
                             message: "Cannot recover transaction from state '#{tx.state}'"
                           })
          end

          tx.update_columns(recovery_attempts: tx.recovery_attempts + 1)

          resolution = PallasTrade::Transactions::PaymentFactResolver.call(transaction: tx, provider_query: true)
          return record_and_fail(tx, 'resolution_failed', resolution.error) unless resolution.success?

          case resolution.value[:verdict]
          when :unpaid
            return failure(tx, { code: 'commerce_transaction_unpaid_in_finalizing' }) if tx.state == 'finalizing'

            tx.retry_payment!
            success(action: :retry_payment, transaction: tx.reload)
          when :ambiguous
            tx.mark_recovery_required! if tx.state == 'finalizing'
            tx.manual_review!
            success(action: :manual_review, transaction: tx.reload)
          else # :paid
            if all_participants_completed?(tx)
              tx.repair_completed!
              return success(action: :repair_completed, transaction: tx.reload)
            end

            :finalize
          end
        end
      end

      # TXN-P2-5：PAID+incomplete 的完成统一收口到 Transactions::Finalize（canonical
      # orchestration boundary，§56）；Recover 只负责 resolver 判定与资金事实分支。
      def finalize(transaction)
        result = PallasTrade::Transactions::Finalize.call(transaction: transaction)
        return result if result.success?

        code = result.error.value[:code] if result.error.respond_to?(:value) && result.error.value.is_a?(Hash)
        failure(transaction, { code: code.presence || 'finalize_failed',
                               message: 'Participant finalization failed' })
      end

      def all_participants_completed?(transaction)
        transaction.transaction_orders.includes(:order).all? do |torder|
          order = torder.order
          order.present? && order.completed?
        end
      end

      # plan 已对本次 attempt 计数（recovery_attempts+1），失败只写 last_error 元数据
      # （record_recovery_failure 会再次计数，供外部失败标记使用，这里不调用）。
      def record_and_fail(transaction, code, error)
        transaction.update_columns(last_error_class: 'PallasTrade::Transactions::Recover', last_error_code: code)
        failure(transaction, { code: code, message: error.to_s })
      end
    end
  end
end
