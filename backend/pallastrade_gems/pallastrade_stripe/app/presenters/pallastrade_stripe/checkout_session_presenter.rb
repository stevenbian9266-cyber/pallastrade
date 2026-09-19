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
    # D15 切片3：强制挑战（Stripe 卡入口在要求认证时的取值）
    THREE_D_SECURE_REQUEST = 'any'

    def initialize(amount_in_cents:, order:, customer: nil, return_url: nil, capture_method: nil,
                   three_d_secure: false)
      @amount_in_cents = amount_in_cents
      @order = order
      @customer = customer
      @return_url = return_url
      @capture_method = capture_method
      @ship_address = order.ship_address
      # D15 切片3：本单是否要求强制 3DS/SCA（由 `Payments::ThreeDSecure::Required` 判定）
      @three_d_secure = three_d_secure == true
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
      # BUT `customer` and `customer_email` are mutually exclusive params —
      # Stripe rejects the request if both are set ("You may only specify one
      # of these parameters"). When a Stripe `customer` exists (logged-in user
      # via fetch_or_create_customer) it already carries the email, so only
      # pass `customer_email` for guests (no customer).
      payload[:customer_email] = order.email if customer.blank? && order.email.present?
      payload[:return_url] = return_url if return_url.present?
      payload[:payment_intent_data][:capture_method] = PallasTradeStripe::Gateway::PaymentIntents::MANUAL_CAPTURE_METHOD if manual_capture?
      payload = payload.deep_merge(ship_address_payload) if shipping_present?

      payload
    end

    private

    attr_reader :order, :amount_in_cents, :customer, :return_url, :capture_method, :ship_address, :three_d_secure

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
      # D15 切片3：强制 3DS/SCA —— Stripe 只在卡入口认这个参数
      # （https://docs.stripe.com/payments/3d-secure/strong-customer-authentication#manual-server-side）
      if three_d_secure?
        data[:payment_method_options] = { card: { request_three_d_secure: THREE_D_SECURE_REQUEST } }
      end
      # PALLAS-CUSTOM (2026-09-19, PRD-20260919-checkout-express-always-visible-and-pi-params 回归修复·真机验证):
      # ⛔ 这里曾合并 `billing_details` —— Stripe 同样拒绝 `payment_intent_data[billing_details]`
      # （dev 真机 400 `parameter_unknown: payment_intent_data[billing_details]`，2026-09-19）。
      # 账单详情**没有**服务端上行参数：只能由客户端确认时经 PM 级
      # `payment_method.billing_details` 下发，支付完成后由 `charge.billing_details` 回读。
      data
    end

    def manual_capture?
      capture_method.to_s == PallasTradeStripe::Gateway::PaymentIntents::MANUAL_CAPTURE_METHOD
    end

    # D15 切片3：要求认证（由调用方按 `Payments::ThreeDSecure::Required` 结论传入）
    def three_d_secure?
      three_d_secure == true
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
