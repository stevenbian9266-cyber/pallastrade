module PallasTradeStripe
  class Gateway < ::PallasTrade::Gateway
    module PaymentSessions
      extend ActiveSupport::Concern

      def session_required?
        true
      end

      def payment_session_class
        PallasTrade::PaymentSessions::Stripe
      end

      def create_payment_session(order:, amount: nil, external_data: {})
        mode = external_data[:mode] || external_data['mode']
        return create_payment_intent_session(order: order, amount: amount) if mode.to_s == 'payment_intent'

        total = amount.presence || order.total_minus_store_credits
        amount_in_cents = PallasTrade::Money.new(total, currency: order.currency).cents

        raise PallasTrade::Core::GatewayError, I18n.t('pallastrade.stripe.payment_session_errors.zero_amount') if amount_in_cents.zero?

        customer = fetch_or_create_customer(order: order)
        return_url = external_data[:return_url] || external_data['return_url']

        # PALLAS-CUSTOM (2026-08-29, PRD-20260829-payments): migrate from
        # PaymentIntents to Checkout Sessions (ui_mode: elements) per
        # https://docs.stripe.com/payments/payment-element/migration-ewcs.
        session_payload = CheckoutSessionPresenter.new(
          amount_in_cents: amount_in_cents,
          order: order,
          customer: customer&.profile_id,
          return_url: return_url,
          capture_method: stripe_capture_method
        ).call

        stripe_session = send_request { |opts| Stripe::Checkout::Session.create(session_payload, opts) }

        payment_session_class.create!(
          order: order,
          payment_method: self,
          amount: total,
          currency: order.currency,
          status: 'pending',
          external_id: stripe_session.id,
          customer: order.user,
          customer_external_id: customer&.profile_id,
          external_data: {
            'client_secret' => stripe_session.client_secret
          }.compact
        )
      end

      # PALLAS-CUSTOM (2026-08-31, PRD-20260831-payments-stripe-自绘卡支付表单):
      # 自绘卡字段（自写 number/expiry/cvc）需要 PaymentIntent 的 `pi_..._secret`
      # 供 `stripe.confirmCardPayment` 消费——Checkout Session 的 `cs_..._secret`
      # 只能用于 PaymentElement。external_id 存 `pi_` id，`external_data.mode`
      # 标记为 `payment_intent` 供模型/complete/webhook 区分模式。
      def create_payment_intent_session(order:, amount: nil)
        total = amount.presence || order.total_minus_store_credits
        amount_in_cents = PallasTrade::Money.new(total, currency: order.currency).cents

        raise PallasTrade::Core::GatewayError, I18n.t('pallastrade.stripe.payment_session_errors.zero_amount') if amount_in_cents.zero?

        customer = fetch_or_create_customer(order: order)
        response = create_payment_intent(amount_in_cents, order, customer_profile_id: customer&.profile_id)
        payment_intent = response.params

        payment_session_class.create!(
          order: order,
          payment_method: self,
          amount: total,
          currency: order.currency,
          status: 'pending',
          external_id: payment_intent['id'],
          customer: order.user,
          customer_external_id: customer&.profile_id,
          external_data: {
            'client_secret' => payment_intent['client_secret'],
            'mode' => 'payment_intent'
          }.compact
        )
      end

      # Checkout Sessions are immutable after creation (amount / line items can't
      # be updated in place) — when the amount changes we recreate the Stripe
      # session and rebind the local record. Otherwise just merge external_data.
      # PaymentIntent-mode sessions (自绘卡字段) keep their mode on recreate.
      def update_payment_session(payment_session:, amount: nil, external_data: {})
        if amount.present? && amount != payment_session.amount
          mode = payment_session.external_data&.dig('mode')
          replacement = if mode.to_s == 'payment_intent'
                          create_payment_intent_session(order: payment_session.order, amount: amount)
                        else
                          create_payment_session(
                            order: payment_session.order,
                            amount: amount,
                            external_data: external_data
                          )
                        end
          payment_session.update!(
            external_id: replacement.external_id,
            external_data: replacement.external_data,
            amount: replacement.amount
          )
          return
        end

        if external_data.present?
          payment_session.update!(
            external_data: (payment_session.external_data || {}).merge(external_data.stringify_keys)
          )
        end
      end

      # Retrieves a Stripe Checkout Session (expanded with its PaymentIntent).
      #
      # PALLAS-CUSTOM (2026-08-31, bugfix): stripe gem 18.x `retrieve(id, opts)`
      # treats the 2nd argument as request options (converted to HTTP headers) —
      # mixing `expand: ['payment_intent']` (an Array) in there makes net-http
      # fail with `undefined method 'strip' for an instance of Array`, so
      # `complete_payment_session` always errored and no Payment was ever
      # recorded (order stayed balance_due after a successful charge).
      # API params must be passed as the first arg hash (`{ id:, expand: [...] }`)
      # exactly like `PaymentIntent.retrieve` / `SetupIntent.retrieve` below.
      def retrieve_checkout_session(session_id)
        send_request do |opts|
          Stripe::Checkout::Session.retrieve({ id: session_id, expand: ['payment_intent'] }, opts)
        end
      end

      # Completes a payment session by verifying with Stripe, creating the
      # Payment record, and patching wallet address data.
      #
      # Does NOT complete the order — that is handled by Carts::Complete
      # (called by the storefront or by the webhook handler).
      #
      # PALLAS-CUSTOM (2026-08-31, PRD-20260831-payments-stripe-自绘卡支付表单):
      # PaymentIntent 模式（external_id 为 `pi_`）直接 retrieve PaymentIntent，
      # 不再经过 Checkout Session（cs_）解析。
      def complete_payment_session(payment_session:, params: {})
        stripe_pi = if payment_session.payment_intent_mode?
                      payment_session.stripe_payment_intent
                    else
                      retrieve_checkout_session(payment_session.external_id).payment_intent
                    end
        raise PallasTrade::Core::GatewayError, 'Payment session has no PaymentIntent yet' unless stripe_pi

        verify_payment_intent_matches!(stripe_pi, payment_session.amount_in_cents, payment_session.currency)

        if payment_intent_accepted?(stripe_pi)
          payment_session.process if payment_session.can_process?

          charge = payment_session.stripe_charge

          # Patch wallet billing address (Apple Pay, Google Pay)
          patch_wallet_address(payment_session.order, charge) if charge.present?

          # Create the Payment record
          payment_session.find_or_create_payment!

          # `else` covers requires_capture (manual capture), processing (delayed-notification
          # banks), and requires_action (bank transfer awaiting funds) — all auth-only states.
          payment = payment_session.payment
          if payment.present? && !payment.completed?
            if payment_intent_successful?(stripe_pi)
              payment.process!
            else
              payment.authorize!
            end
          end

          payment_session.complete unless payment_session.completed?
        else
          payment_session.fail if payment_session.can_fail?
        end
      end

      private

      def payment_intent_successful?(stripe_pi)
        stripe_pi.status == 'succeeded'
      end

      # Patches the order's billing address with data from the Stripe charge.
      # Needed for quick checkout (Apple Pay/Google Pay) where the storefront
      # doesn't have the billing address before payment confirmation.
      def patch_wallet_address(order, charge)
        return if charge.blank?

        billing_details = charge.billing_details
        address = billing_details.address

        order.email ||= billing_details.email
        order.save! if order.email_changed?

        # Skip if billing address is already valid
        return if order.bill_address.present? && order.bill_address.valid?

        country_iso = address.country
        country = (country_iso.present? && PallasTrade::Country.by_iso(country_iso)) ||
                  order.store.default_market&.default_country ||
                  PallasTrade::Country.by_iso('US')

        order.bill_address ||= PallasTrade::Address.new(country: country, user: order.user)
        order.bill_address.quick_checkout = true

        first_name = billing_details.name&.split(' ')&.first || order.ship_address&.first_name || order.user&.first_name
        last_name = billing_details.name&.split(' ')&.last || order.ship_address&.last_name || order.user&.last_name

        order.bill_address.first_name ||= first_name
        order.bill_address.last_name ||= last_name
        order.bill_address.phone ||= billing_details.phone
        order.bill_address.address1 ||= address.line1
        order.bill_address.address2 ||= address.line2
        order.bill_address.city ||= address.city
        order.bill_address.zipcode ||= address.postal_code

        state_name = address.state
        if country.states_required?
          order.bill_address.state = country.states.find_all_by_name_or_abbr(state_name)&.first
        else
          order.bill_address.state_name = state_name
        end
        order.bill_address.state_name ||= state_name

        if order.bill_address.invalid?
          return if order.ship_address.blank?

          order.bill_address = order.ship_address
        end

        order.bill_address.save! if order.bill_address&.changed?
        order.save!

        copy_bill_info_to_user(order) if order.user.present?
      end

      def copy_bill_info_to_user(order)
        user = order.user
        user.first_name ||= order.bill_address.first_name
        user.last_name ||= order.bill_address.last_name
        user.phone ||= order.bill_address.phone
        user.bill_address_id ||= order.bill_address.id
        user.save! if user.changed?
      end
    end
  end
end
