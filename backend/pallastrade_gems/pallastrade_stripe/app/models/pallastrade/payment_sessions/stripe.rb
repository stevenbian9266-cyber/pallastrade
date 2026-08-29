module PallasTrade
  class PaymentSessions::Stripe < PaymentSession
    delegate :api_options, to: :payment_method

    # Duck-type interface consumed by the CompleteOrder and CreatePayment services
    def stripe_id
      external_id
    end

    def client_secret
      external_data&.dig('client_secret')
    end

    def ephemeral_key_secret
      external_data&.dig('ephemeral_key_secret')
    end

    # PALLAS-CUSTOM (2026-08-29, PRD-20260829-payments): external_id is now a
    # `cs_` Checkout Session id. We retrieve the session (expanded with its
    # PaymentIntent) and delegate to the underlying intent — keeping the
    # CompleteOrder/CreatePayment duck-type contract unchanged.
    def stripe_checkout_session
      @stripe_checkout_session ||= payment_method.retrieve_checkout_session(external_id)
    end

    def stripe_payment_intent
      @stripe_payment_intent ||= stripe_checkout_session.payment_intent
    end

    def stripe_charge
      @stripe_charge ||= begin
        latest_charge = stripe_payment_intent&.latest_charge
        latest_charge.present? ? payment_method.retrieve_charge(latest_charge) : nil
      end
    end

    # Checkout Session payment_status: 'paid' | 'unpaid' | 'no_payment_required'
    def checkout_session_payment_status
      stripe_checkout_session.payment_status
    end

    def accepted?
      payment_method.payment_intent_accepted?(stripe_payment_intent)
    end

    def successful?
      checkout_session_payment_status == 'paid'
    end

    def charge_not_required?
      payment_method.payment_intent_charge_not_required?(stripe_payment_intent)
    end

    def find_or_create_payment!(metadata = {})
      return unless persisted?
      return payment if payment.present?

      PallasTradeStripe::CreatePayment.new(
        order: order,
        payment_intent: self,
        gateway: payment_method,
        amount: amount
      ).call
    end
  end
end
