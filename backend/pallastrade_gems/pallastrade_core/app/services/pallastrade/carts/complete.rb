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
          # Order lifecycle P8 (2026-08-28): 下单前置校验（风控/黑名单/防刷单，flag 灰度）——
          # 支付处理前拦截，命中返回 { code:, message: } 统一业务错误。
          preflight = PallasTrade::Checkout::Preflight.call(order: cart)
          return preflight unless preflight.success?

          process_payments!(cart) if cart.payment_required?

          return failure(cart, cart.errors.full_messages.to_sentence) if cart.errors.any?

          # Order lifecycle P8 (2026-08-28): 锁库存 :payment 模式——支付确认后真正锁定
          # （cart 操作阶段只校验不落 reservation，见 StockReservations::Reserve validate_only）。
          if payment_reservation_strategy? && cart.payment_total.to_f > 0
            reserve_result = PallasTrade::StockReservations::Reserve.call(order: cart)
            return failure(cart, reserve_result.error) if reserve_result.failure?
          end

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

      # P8：锁库存时机 —— :payment = 支付确认后锁（默认 :order = 下单/cart 操作时锁）
      def payment_reservation_strategy?
        PallasTrade::Config[:stock_reservation_strategy].to_s == 'payment'
      end

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
