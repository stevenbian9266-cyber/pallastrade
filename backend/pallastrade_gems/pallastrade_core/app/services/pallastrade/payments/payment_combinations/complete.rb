# frozen_string_literal: true

# PALLAS-CUSTOM: 合并支付载体服务（PRD-20260827 P4）——能力层服务，默认不接入任何流程（P5 收银台接线）
module PallasTrade
  module Payments
    module PaymentCombinations
      # 幂等完成一次合并支付。
      #
      # 关键设计（吸取 2026-08 PaymentGroup 失败教训：单事务多订单完成，部分失败整体回滚
      # → 钱扣了单没完成）：
      #   1) **先入账支付**（组合事务内）：组合 → succeeded；一个 Payment 挂组合（order_id=nil）
      #      完成；各 PaymentSplit 记账（captured 按比例分摊、payment 回填）；各订单
      #      payment_total / payment_state 更新。此事务提交后资金已安全入账。
      #   2) **再逐个订单完成**（事务外，每订单独立）：CombinationMemberComplete 分流——
      #      standard 成员走 Carts::Complete（pay!+finalize!），legacy 成员走
      #      Checkout::Complete（COMPATIBILITY）；某订单失败**不回滚已入账支付**，
      #      订单标 balance_due + 入 CombinationSettleJob 重试（资金始终 >= 订单状态）。
      #
      # 幂等：组合已 succeeded / 订单已完成 → 跳过；Webhook 与前端回调双路径、job 重试均安全。
      #
      # @param combination [PallasTrade::PaymentCombination]
      # @param payment_session [PallasTrade::PaymentSession, nil] 支付会话（webhook 路径传入）
      # @return [PallasTrade::ServiceModule::Result] success(combination) / failure(combination, message)
      class Complete
        prepend PallasTrade::ServiceModule::Base

        def call(combination: nil, payment_session: nil)
          combination ||= payment_session&.payment_combination
          return failure(nil, 'Payment combination not found') if combination.nil?
          return failure(combination, 'Combination is not payable') unless combination.pending? || combination.processing? || combination.succeeded?

          # —— 阶段 1：入账支付（组合事务）——
          combination.with_lock do
            if combination.reload.succeeded?
              next success(combination) # 幂等：已入账
            end

            record_payment!(combination, payment_session)
            combination.succeed!
          end

          # —— 阶段 2：逐个订单完成（事务外，失败补偿，不回滚已入账支付）——
          combination.reload.payment_splits.includes(:order).each do |split|
            complete_member_order!(combination, split)
          end

          success(combination)
        end

        private

        # 入账支付：找/建组合 Payment（挂组合 order_id=nil）→ 完成 → splits 记账 → 订单状态更新
        def record_payment!(combination, payment_session)
          payment = find_combination_payment(combination, payment_session)
          payment.complete! if payment.present? && !payment.completed?
          payment_session&.complete if payment_session&.can_complete?

          combination.payment_splits.includes(:order).each do |split|
            order = split.order
            next if order.nil?

            captured = captured_share(combination, split)
            split.update_column(:captured_amount, captured) if split.captured_amount.to_d != captured.to_d
            split.update_column(:payment_id, payment.id) if payment && split.payment_id != payment.id

            order.update_columns(
              payment_total: captured,
              payment_state: captured >= order.total.to_f ? 'paid' : 'balance_due'
            )
          end
        end

        # 组合支付：优先复用 session 已建 payment（webhook 路径），否则新建（挂组合 order_id=nil）
        def find_combination_payment(combination, payment_session)
          existing = payment_session&.payment
          if existing
            if existing.order_id.present? || existing.payment_combination_id != combination.id
              # 把 session 建在订单上的 payment 转移到组合（order_id → nil）
              existing.update!(order_id: nil, payment_combination: combination)
            end
            return existing
          end

          combination.payments.first || combination.payments.create!(
            payment_method: payment_session&.payment_method,
            amount: combination.amount,
            response_code: payment_session&.external_id,
            skip_source_requirement: true
          )
        end

        # 该订单在组合中的分摊额：按 amount_due 比例 × 组合实收（全额支付时 == amount_due）
        def captured_share(combination, split)
          order = split.order
          return 0 if order.nil?

          total_unpaid = combination.payment_splits.to_a.sum { |s| s.order ? s.order.amount_due.to_f : 0 }
          return 0 if total_unpaid.zero?

          (order.amount_due.to_f / total_unpaid * combination.amount.to_f).round(2)
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
