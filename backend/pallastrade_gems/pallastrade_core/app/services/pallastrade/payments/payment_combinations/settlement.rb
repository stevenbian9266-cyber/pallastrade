# frozen_string_literal: true

# PALLAS-CUSTOM: TXN-P2 (2026-09-05, PRD-20260905-checkout-paymentcombination-txn-化)
#
# PaymentCombinations::Settlement —— 组合"入账支付"幂等 primitive（阶段 1）。
# 由 `Transactions::Finalize` 组合分支（txn 化组合）与 `PaymentCombinations::Complete`
# （legacy 适配器）共用。
#
# 语义（从原 PaymentCombinations::Complete 提取，保持一致）：
#   - 一个组合一个 Payment（挂组合 order_id=nil，order_id nil）完成；session 完成；
#   - 各 PaymentSplit 记账（captured 按 amount_due 比例分摊、payment 回填）；
#   - 各成员订单 payment_total / payment_state 更新（paid / balance_due）；
#   - combination → succeeded（幂等：已 succeeded 直接短路）。
# 资金先入账、后成员完成（INV-03：PSP success + local incomplete = recovery_required）。
module PallasTrade
  module Payments
    module PaymentCombinations
      class Settlement
        prepend PallasTrade::ServiceModule::Base

        # @param combination [PallasTrade::PaymentCombination]
        # @param payment_session [PallasTrade::PaymentSession, nil]
        # @return [PallasTrade::ServiceModule::Result] success(combination) / failure(combination, message)
        def call(combination: nil, payment_session: nil)
          combination ||= payment_session&.payment_combination
          return failure(nil, 'Payment combination not found') if combination.nil?
          return failure(combination, 'Combination is not payable') unless payable?(combination)

          combination.with_lock do
            combo = combination.reload
            next if combo.succeeded? # 幂等：已入账

            record_payment!(combo, payment_session)
            combo.succeed!
          end

          success(combination.reload)
        end

        private

        def payable?(combination)
          combination.pending? || combination.processing? || combination.succeeded?
        end

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
      end
    end
  end
end
