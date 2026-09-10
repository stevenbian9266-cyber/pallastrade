# frozen_string_literal: true

# PRD-20260910-promotions-promo-batch3b-redemption-hardening (FR-003/FR-004)
#
# 核销事件的兜底接线（async，幂等，失败仅记日志不阻塞资金链路）：
#   * `commerce_transaction.payment_confirmed` —— 资金已确认的交易，对其订单执行
#     FinalizeOrder（幂等）：覆盖「走了支付确认但没走 order.complete」的核销缺失。
#   * `refund.succeeded` —— 订单被**全额**退款时释放核销（归还 usage 名额）；
#     部分退款保留 committed（防“分次小额退款刷回名额”）。
module PallasTrade
  module Promotions
    class RedemptionSubscriber < PallasTrade::Subscriber
      subscribes_to 'commerce_transaction.payment_confirmed', 'refund.succeeded'

      on 'commerce_transaction.payment_confirmed', :handle_payment_confirmed
      on 'refund.succeeded', :handle_refund_succeeded

      def handle_payment_confirmed(event)
        transaction = find_transaction(event.payload)
        return if transaction.nil?

        transaction.orders.find_each do |order|
          # PRD-20260910-promo-batch4a：先冻结展示事实（快照），再写核销。
          # force: 事件本身即资金确认信号，此时订单状态机可能尚未推进。
          PallasTrade::Promotions::Snapshot::Freeze.call(order, force: true)
          PallasTrade::Promotions::Redemption::FinalizeOrder.call(order)
        end
      rescue StandardError => e
        Rails.logger.error(
          "[Promotions::RedemptionSubscriber] finalize failed for transaction payload " \
          "#{event.payload.inspect}: #{e.class} #{e.message}"
        )
      end

      def handle_refund_succeeded(event)
        refund = find_refund(event.payload)
        return if refund.nil?
        return unless refund.succeeded?

        order = order_for(refund)
        return if order.nil?
        return unless fully_refunded?(order)

        PallasTrade::Promotions::Redemption::ReleaseOrder.call(order, reason: 'refunded')
      rescue StandardError => e
        Rails.logger.error(
          "[Promotions::RedemptionSubscriber] release failed for refund payload " \
          "#{event.payload.inspect}: #{e.class} #{e.message}"
        )
      end

      private

      def find_transaction(payload)
        id = payload.try(:[], 'id') || payload.try(:[], :id)
        return if id.blank?

        if id.to_s.start_with?('txn_')
          PallasTrade::CommerceTransaction.find_by_param(id)
        else
          PallasTrade::CommerceTransaction.find_by(id: id)
        end
      end

      def find_refund(payload)
        id = payload.try(:[], 'id') || payload.try(:[], :id)
        return if id.blank?

        if id.to_s.start_with?('re_')
          PallasTrade::Refund.find_by_param(id)
        else
          PallasTrade::Refund.find_by(id: id)
        end
      end

      def order_for(refund)
        refund.target_order || refund.payment&.order
      end

      # 全额退款判定：该订单支付总额已被成功退款覆盖（且退款额 > 0）。
      def fully_refunded?(order)
        payment_total = order.payment_total.to_f
        return false unless payment_total.positive?

        refunded = refunded_total_for(order)
        refunded.positive? && (payment_total - refunded) <= 0.001
      end

      def refunded_total_for(order)
        refunds = PallasTrade::Refund.where(state: 'succeeded').
                  where(target_order_id: order.id).
                  or(PallasTrade::Refund.where(state: 'succeeded').
                     where(payment_id: order.payments.select(:id)))

        refunds.sum(:amount).to_f
      end
    end
  end
end
