module PallasTradeStripe
  class CreatePayment
    def initialize(order:, payment_intent:, gateway: nil, tax_transaction: nil, amount: nil)
      @order = order
      @gateway = gateway || order.store.stripe_gateway
      @payment_intent = payment_intent
      @tax_transaction = tax_transaction
      @amount = amount || order.total_minus_store_credits
    end

    def call
      stripe_charge = payment_intent.stripe_charge

      if stripe_charge.present?
        source = PallasTradeStripe::CreateSource.new(
          order: order,
          stripe_payment_method_details: stripe_charge.payment_method_details,
          stripe_payment_method_id: stripe_charge.payment_method,
          stripe_billing_details: stripe_charge.billing_details,
          gateway: gateway
        ).call
      elsif payment_intent.charge_not_required?
        stripe_payment_intent = payment_intent.stripe_payment_intent
        source = PallasTradeStripe::CreateSource.new(
          order: order,
          stripe_payment_method_details: stripe_payment_intent.payment_method,
          stripe_payment_method_id: stripe_payment_intent.payment_method.id,
          stripe_billing_details: nil,
          gateway: gateway
        ).call
      end

      # sometimes a job is re-tried and creates a double payment record so we need to avoid it!
      # PALLAS-CUSTOM (2026-08-31, bugfix): after the Checkout Sessions migration
      # `payment_intent.stripe_id` is the `cs_` Checkout Session id, but
      # `Payment#response_code` must hold the underlying `pi_` PaymentIntent id —
      # `Gateway#handle_authorize_or_purchase` and `Gateway#credit` both call
      # Stripe with `payment.response_code` as a PaymentIntent id ("No such
      # payment_intent: 'cs_test_...'" otherwise), so the Payment was created
      # but never `process!`-ed and the order stayed balance_due.
      payment = order.payments.find_or_initialize_by(
        payment_method_id: gateway.id,
        response_code: payment_intent.stripe_payment_intent&.id || payment_intent.stripe_id,
        amount: amount
      )

      # P0-1 (2026-09-02): 显式关联 originating PaymentSession（payment_intent 即
      # PaymentSessions::Stripe duck-type）。cs_ 模式下 response_code=pi_ 而
      # session.external_id=cs_，正式关联不依赖二者相等。
      if payment_intent.is_a?(PallasTrade::PaymentSession)
        payment.payment_session = payment_intent
      end

      payment.source = source if source.present?
      payment.stripe_tax_transaction_id = tax_transaction
      payment.stripe_charge_id = stripe_charge&.id

      payment.save!
      payment
    end

    private

    attr_reader :order, :gateway, :payment_intent, :tax_transaction, :source, :amount
  end
end
