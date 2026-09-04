# frozen_string_literal: true

# PALLAS-CUSTOM: TXN-P2-5 (PRD-20260904-payments-txn-p2-5)
#
# Transactions::Finalize —— canonical unified finalization（P2 源文档 §23/§56）。
# 对**已确认资金**的 CommerceTransaction 统一完成参与者订单：
#   payment_confirmed → finalizing（begin_finalizing）→ 锁外逐参与者 finalize
#   （复用 Payments::CombinationMemberComplete：standard→Carts::Complete /
#   legacy→Checkout::Complete，INV-08 幂等）→ complete！
#   recovery_required（已由 Recover 判定 PAID）→ retry_finalizing → 同上。
#
# Strangler（§56）：不删旧 service；本服务是 orchestration boundary，参与者
# 完成委托订单级原语。失败 → mark_recovery_required! + last_error
# （INV-03：PSP success + local incomplete = recovery_required），资金不回滚。
# 幂等（INV-08）：已 completed → success 短路；失败参与者不中断其余。
module PallasTrade
  module Transactions
    class Finalize
      prepend PallasTrade::ServiceModule::Base

      # 可 finalize 前置状态（资金已确认；recovery_required 需调用方已判定 paid）
      FINALIZABLE_STATES = %w[payment_confirmed finalizing recovery_required].freeze

      # @param transaction [PallasTrade::CommerceTransaction]
      # @return Result success({ action: :finalized, transaction: }) |
      #         failure({ code: 'commerce_transaction_not_finalizable' | 'finalize_failed', ... })
      def call(transaction:)
        return failure(nil, 'Transaction not found') if transaction.nil?

        transaction.with_lock do
          tx = transaction.reload
          # 幂等短路：已完成
          return success(action: :finalized, transaction: tx) if tx.state == 'completed'
          unless FINALIZABLE_STATES.include?(tx.state)
            return failure(tx, {
                             code: 'commerce_transaction_not_finalizable',
                             state: tx.state,
                             message: "Cannot finalize transaction from state '#{tx.state}'"
                           })
          end

          if tx.state == 'payment_confirmed'
            tx.begin_finalizing!
          elsif tx.state == 'recovery_required'
            tx.retry_finalizing!
          end
        end

        # 锁外逐参与者 finalize（provider/长操作不占交易行锁）
        failures = finalize_participants(transaction)

        transaction.with_lock do
          tx = transaction.reload
          # 幂等短路：锁间隙另一进程已完成
          return success(action: :finalized, transaction: tx) if tx.state == 'completed'

          unless failures.empty?
            tx.update_columns(last_error_class: 'PallasTrade::Transactions::Finalize',
                              last_error_code: 'finalize_failed',
                              last_error_message: failures.first.to_s)
            tx.mark_recovery_required! if tx.state == 'finalizing'
            return failure(tx, { code: 'finalize_failed',
                                 message: 'Some participant orders could not be finalized' })
          end

          tx.complete!
          success(action: :finalized, transaction: tx.reload)
        end
      end

      private

      # 锁外逐参与者完成（订单级幂等原语，INV-08）；成功者标记 completion_status。
      # 单参与者异常不中断其余；失败汇总（资金不回滚）。
      def finalize_participants(transaction)
        transaction.transaction_orders.includes(:order).filter_map do |torder|
          order = torder.order
          next if order.nil? || order.completed?

          begin
            result = PallasTrade::Payments::CombinationMemberComplete.call(order: order)
          rescue StandardError => e
            next "order #{order.number || order.id} finalize error: #{e.class}"
          end

          if result.success? && order.reload.completed?
            torder.update_column(:completion_status, 'completed') if torder.completion_status != 'completed'
            nil
          else
            "order #{order.number || order.id} finalize failed"
          end
        end
      end
    end
  end
end
