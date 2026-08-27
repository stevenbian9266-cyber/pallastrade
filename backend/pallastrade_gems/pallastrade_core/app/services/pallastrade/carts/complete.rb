# In PallasTrade 6 this servoice will complete the PallasTrade::Cart, and create a PallasTrade::Order
# created based on the contents of the cart.
module PallasTrade
  module Carts
    class Complete
      prepend PallasTrade::ServiceModule::Base

      # Completes the cart and creates a PallasTrade::Order based on its contents.
      # @return [PallasTrade::Order]
      def call(cart:)
        return success(cart) if cart.completed?
        return failure(cart, 'Order is canceled') if cart.canceled?
        # Enforced here (not only in the controller) so every completion path —
        # API, payment-session webhook — honors the channel's guest-checkout gate.
        return failure(cart, PallasTrade.t(:guest_checkout_not_allowed)) if cart.guest_checkout_disallowed?

        cart.with_lock do
          process_payments!(cart) if cart.payment_required?

          return failure(cart, cart.errors.full_messages.to_sentence) if cart.errors.any?

          advance_to_complete!(cart)

          if cart.reload.complete?
            PallasTrade::StockReservations::Release.call(order: cart)
            # Order lifecycle P5 (2026-08-27): 自动拆单（flag 灰度）——支付确认后按策略拆分，
            # 失败不影响订单完成（AutoSplit 内部 rescue）。默认 [] 关闭，零行为变化。
            PallasTrade::Carts::AutoSplit.call(order: cart)
            success(cart)
          else
            failure(cart, cart.errors.full_messages.to_sentence.presence || 'Could not complete checkout')
          end
        end
      end

      private

      def process_payments!(cart)
        # If payments were already processed by the payment session
        # (e.g. Stripe charged the card during complete_payment_session),
        # skip re-processing. Only process unprocessed (checkout state) payments.
        return if cart.payment_total >= cart.total
        return if cart.payments.valid.any?(&:completed?) && cart.unprocessed_payments.empty?

        cart.process_payments!
      end

      def advance_to_complete!(cart)
        cart.next until cart.complete? || cart.errors.present?
      end
    end
  end
end
