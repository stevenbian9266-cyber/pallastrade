module PallasTradeStripe
  # Builds the Stripe Checkout Session payload for the Payment Element
  # (ui_mode: "elements") — the migration target from PaymentIntents
  # (PRD-20260829-payments, https://docs.stripe.com/payments/payment-element/migration-ewcs).
  #
  # Checkout Sessions manage taxes/shipping/discounts/currency conversion and
  # require far less code than PaymentIntents. The PaymentElement is initialized
  # with the session's client_secret and confirmed via `stripe.confirmPayment`.
  class CheckoutSessionPresenter
    SETUP_FUTURE_USAGE = 'off_session'

    def initialize(amount_in_cents:, order:, customer: nil, return_url: nil, capture_method: nil)
      @amount_in_cents = amount_in_cents
      @order = order
      @customer = customer
      @return_url = return_url
      @capture_method = capture_method
      @ship_address = order.ship_address
    end

    def call
      payload = {
        mode: 'payment',
        ui_mode: 'elements',
        line_items: line_items,
        payment_intent_data: payment_intent_data,
        metadata: {
          pallastrade_order_id: order.id
        }
      }
      payload[:customer] = customer if customer.present?
      # PALLAS-CUSTOM (2026-08-31, bugfix): Stripe Payment Element (Checkout
      # Session, ui_mode: elements) requires an email on the session to
      # confirm — without `customer_email`, `checkout.confirm()` rejects with
      # "An email address is required to confirm this Checkout Session".
      payload[:customer_email] = order.email if order.email.present?
      payload[:return_url] = return_url if return_url.present?
      payload[:payment_intent_data][:capture_method] = PallasTradeStripe::Gateway::PaymentIntents::MANUAL_CAPTURE_METHOD if manual_capture?
      payload = payload.deep_merge(ship_address_payload) if shipping_present?

      payload
    end

    private

    attr_reader :order, :amount_in_cents, :customer, :return_url, :capture_method, :ship_address

    # PallasTrade collects shipping in its own checkout UI; Stripe only needs a
    # single aggregated line item for the amount (which may be a merged
    # PaymentCombination total, not a single order's line items).
    def line_items
      [{
        quantity: 1,
        price_data: {
          currency: order.currency,
          unit_amount: amount_in_cents,
          product_data: { name: order.number }
        }
      }]
    end

    # Preserves the PaymentIntent semantics PallasTrade relies on:
    # transfer_group (order-level accounting) + setup_future_usage off_session
    # (saved cards) + metadata.
    def payment_intent_data
      data = {
        transfer_group: order.number,
        metadata: { pallastrade_order_id: order.id },
        setup_future_usage: SETUP_FUTURE_USAGE
      }
      data
    end

    def manual_capture?
      capture_method.to_s == PallasTradeStripe::Gateway::PaymentIntents::MANUAL_CAPTURE_METHOD
    end

    def shipping_present?
      ship_address.present? && ship_address.address1.present?
    end

    def ship_address_payload
      {
        payment_intent_data: {
          shipping: {
            address: {
              city: ship_address.city,
              country: ship_address.country_iso,
              line1: ship_address.address1,
              line2: ship_address.address2,
              postal_code: ship_address.zipcode,
              state: ship_address.state_abbr
            },
            name: ship_address.full_name
          }
        }
      }
    end
  end
end
