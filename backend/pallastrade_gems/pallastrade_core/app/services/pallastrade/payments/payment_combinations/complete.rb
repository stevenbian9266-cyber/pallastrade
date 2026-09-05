# frozen_string_literal: true

# PALLAS-CUSTOM: 合并支付载体服务（PRD-20260827 P4）——能力层服务，默认不接入任何流程（P5 收银台接线）
module PallasTrade
  module Payments
    module PaymentCombinations
      # 幂等完成一次合并支付（**legacy 适配器**：仅用于无 durable CommerceTransaction 的
      # 存量/回退组合）。
      #
      # TXN-P2 (2026-09-05)：组合已 txn 化——新组合在 `Create` 即建 CommerceTransaction
      # （combined_payment），PSP 成功统一走 `Transactions::OnPaymentSuccess` →
      # `Transactions::Finalize`（Finalize 组合分支自含入账 Settlement + 成员完成，
      # 失败 → recovery_required 而非 SettleJob）。本服务保留入账 primitive 的调用，
      # 供 legacy 非 txn 组合（Strangler：不一次性删除旧 service，P2 §56）。
      #
      # 阶段 1 入账已提取到 `PaymentCombinations::Settlement`（幂等 primitive）。
      #
      # @param combination [PallasTrade::PaymentCombination]
      # @param payment_session [PallasTrade::PaymentSession, nil] 支付会话（webhook 路径传入）
      # @return [PallasTrade::ServiceModule::Result] success(combination) / failure(combination, message)
      class Complete
        prepend PallasTrade::ServiceModule::Base

        def call(combination: nil, payment_session: nil)
          combination ||= payment_session&.payment_combination
          return failure(nil, 'Payment combination not found') if combination.nil?
          return failure(combination, 'Combination is not payable') unless payable?(combination)

          # —— 阶段 1：入账支付（幂等 primitive；已 succeeded 短路）——
          result = PallasTrade::Payments::PaymentCombinations::Settlement.call(
            combination: combination, payment_session: payment_session
          )
          return result unless result.success?

          # —— 阶段 2：逐个订单完成（事务外，失败补偿，不回滚已入账支付）——
          combination.reload.payment_splits.includes(:order).each do |split|
            complete_member_order!(combination, split)
          end

          success(combination.reload)
        end

        private

        def payable?(combination)
          combination.pending? || combination.processing? || combination.succeeded?
        end

        # 完成单个成员订单；失败不抛（已入账支付保留），标 balance_due + 入补偿队列。
        # RISK-01（2026-09-04）：完成 primitive 按 standard/legacy 分流——standard 成员
        # （pending/paid）必须走 Carts::Complete，legacy Checkout::Complete 无法完成它们。
        def complete_member_order!(combination, split)
          order = split.order
          return if order.nil? || order.completed?

          PallasTrade::Payments::CombinationMemberComplete.call(order: order)
          return if order.reload.completed?

          # 完成失败：不回滚已入账支付；订单标 balance_due + 入队重试
          order.update_columns(payment_state: 'balance_due') unless order.payment_state == 'balance_due'
          PallasTrade::Payments::CombinationSettleJob.perform_later(combination.id, order.id)
        rescue StandardError => e
          Rails.error.report(e, context: { combination_id: combination.id, order_id: order.id },
                                source: 'PallasTrade.payments.combination_complete')
          order.update_column(:payment_state, 'balance_due') if order.present?
          PallasTrade::Payments::CombinationSettleJob.perform_later(combination.id, order.id) if order.present?
        end
      end
    end
  end
end
