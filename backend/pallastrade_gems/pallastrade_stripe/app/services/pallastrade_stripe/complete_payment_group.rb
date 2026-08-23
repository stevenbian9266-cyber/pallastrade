# PALLAS-CUSTOM: 多订单合并支付（PRD-20260823-checkout-多订单拆分与合并支付）
#
# Completes every member order of a Stripe-backed payment group after a successful
# PaymentIntent. The primary order reuses the existing CompleteOrder service (which
# patches quick-checkout customer information from the charge); the remaining orders
# follow the same create-payment → process/authorize → complete sequence. Idempotent
# for duplicate webhooks and job retries.
module PallasTradeStripe
  class CompletePaymentGroup
    def initialize(payment_session:)
      @payment_session = payment_session
    end

    attr_reader :payment_session

    def call
      payment_group = payment_session.payment_group
      return payment_group if payment_group.completed?

      primary_order = payment_group.primary_order

      # Primary order: reuse the full CompleteOrder path (customer info + payment + completion)
      CompleteOrder.new(payment_intent: payment_session).call unless primary_order.nil?

      # Remaining member orders
      payment_group.orders.where.not(id: primary_order&.id).each do |order|
        next if (order.completed? && order.paid?) || order.canceled?

        order.with_lock do
          next if (order.reload.completed? && order.paid?) || order.canceled?

          payment = payment_session.find_or_create_payment_for_order!(order)

          if payment_session.successful?
            payment.process!
          else
            payment.authorize!
          end

          PallasTrade::Dependencies.checkout_complete_service.constantize.call(order: order) unless order.completed?
        end
      end

      payment_group.completed_at ||= Time.current
      payment_group.complete if payment_group.can_complete?
      payment_group.reload
    end
  end
end
