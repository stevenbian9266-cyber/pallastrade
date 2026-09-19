module PallasTradeStripe
  class Gateway < ::PallasTrade::Gateway
    module PaymentIntents
      extend ActiveSupport::Concern

      DELAYED_NOTIFICATION_PAYMENT_METHOD_TYPES = %w[sepa_debit us_bank_account].freeze
      BANK_PAYMENT_METHOD_TYPES = %w[customer_balance us_bank_account].freeze
      MANUAL_CAPTURE_METHOD = 'manual'.freeze

      # PALLAS-CUSTOM (2026-09-19, PRD-20260919-checkout-express-always-visible-and-pi-params 回归修复):
      # PaymentIntent 顶层载荷白名单 + 只读键黑名单。背景：`billing_details` 在 Stripe 侧是
      # **只读**字段（仅 retrieve 返回），一旦被合进创建参数就会 400 `parameter_unknown`，
      # 直接打死全部卡/钱包支付（2026-09-19 线上 dev 事故）。这里在发请求前断言，
      # 宁可本地抛出也不允许非法参数再次到达 Stripe。
      PAYMENT_INTENT_TOP_LEVEL_KEYS = %i[
        amount application_fee_amount automatic_payment_methods capture_method confirm currency
        customer description metadata off_session on_behalf_of payment_method payment_method_data
        payment_method_options payment_method_types receipt_email setup_future_usage shipping
        statement_descriptor statement_descriptor_suffix transfer_data transfer_group
      ].freeze

      # Stripe 只读 / 非输入字段：出现在创建或更新参数里一律视为编程错误。
      PAYMENT_INTENT_READ_ONLY_KEYS = %i[
        billing_details charges client_secret id latest_charge next_action status
      ].freeze

      def payment_intent_accepted?(payment_intent)
        payment_intent.status.in?(payment_intent_accepted_statuses(payment_intent))
      end

      def payment_intent_delayed_notification?(payment_intent)
        payment_method = payment_intent.payment_method
        return false unless payment_method.respond_to?(:type)

        payment_intent.payment_method.type.in?(DELAYED_NOTIFICATION_PAYMENT_METHOD_TYPES)
      end

      def payment_intent_charge_not_required?(payment_intent)
        payment_intent_bank_payment_method?(payment_intent)
      end

      def payment_intent_bank_payment_method?(payment_intent)
        payment_method = payment_intent.payment_method
        return false unless payment_method.respond_to?(:type)

        payment_intent.payment_method.type.in?(BANK_PAYMENT_METHOD_TYPES)
      end

      def payment_intent_requires_capture?(payment_intent)
        payment_intent.status == 'requires_capture'
      end

      def payment_intent_manual_capture?(payment_intent)
        payment_intent.respond_to?(:capture_method) && payment_intent.capture_method == MANUAL_CAPTURE_METHOD
      end

      # Creates a Stripe payment intent for the order
      #
      # @param amount_in_cents [Integer] the amount in cents
      # @param order [PallasTrade::Order] the order to create a payment intent for
      # @param payment_method_id [String] Stripe payment method id to use, eg. a card token
      # @param off_session [Boolean] whether the payment intent is off session
      # @param customer_profile_id [String] Stripe customer profile id to use, eg.  cus_123
      # @return [PallasTrade::PaymentResponse] the response from the payment intent creation
      def create_payment_intent(amount_in_cents, order, payment_method_id: nil, off_session: false, customer_profile_id: nil, idempotency_key: nil, three_d_secure: false)
        payload = PallasTradeStripe::PaymentIntentPresenter.new(
          amount: amount_in_cents,
          order: order,
          customer: customer_profile_id || fetch_or_create_customer(order: order)&.profile_id,
          payment_method_id: payment_method_id,
          off_session: off_session,
          capture_method: stripe_capture_method,
          # D15 切片3：强制 3DS/SCA（受卡入口能力门控，在上层已判定）
          three_d_secure: three_d_secure
        ).call

        # 纵深防线：非法键在本地拦截（见 PAYMENT_INTENT_READ_ONLY_KEYS 说明）。
        assert_legal_payment_intent_payload!(payload)

        protect_from_error do
          response = send_request(idempotency_key: idempotency_key) { |opts| Stripe::PaymentIntent.create(payload, opts) }

          success(response.id, response)
        end
      end

      # Updates a Stripe payment intent for the order
      #
      # @param payment_intent_id [String] Stripe payment intent id
      # @param amount_in_cents [Integer] the amount in cents
      # @param order [PallasTrade::Order] the order to update the payment intent for
      # @param payment_method_id [String] Stripe payment method id to use, eg. a card token
      # @return [PallasTrade::PaymentResponse] the response from the payment intent update
      def update_payment_intent(payment_intent_id, amount_in_cents, order, payment_method_id = nil)
        protect_from_error do
          payload = PallasTradeStripe::PaymentIntentPresenter.new(
            amount: amount_in_cents,
            order: order,
            customer: fetch_or_create_customer(order: order)&.profile_id,
            payment_method_id: payment_method_id
          ).call.slice(:amount, :currency, :payment_method, :shipping, :customer)

          # 纵深防线：与创建同源（slice 已足够，但仍显式断言）。
          assert_legal_payment_intent_payload!(payload)

          response = send_request { |opts| Stripe::PaymentIntent.update(payment_intent_id, payload, opts) }

          success(response.id, response)
        end
      end

      def retrieve_payment_intent(payment_intent_id)
        send_request { |opts| Stripe::PaymentIntent.retrieve({ id: payment_intent_id, expand: ['payment_method'] }, opts) }
      end

      def confirm_payment_intent(payment_intent_id, idempotency_key: nil)
        send_request(idempotency_key: idempotency_key) { |opts| Stripe::PaymentIntent.confirm(payment_intent_id, {}, opts) }
      end

      def capture_payment_intent(payment_intent_id, amount_in_cents, idempotency_key: nil)
        send_request(idempotency_key: idempotency_key) { |opts| Stripe::PaymentIntent.capture(payment_intent_id, { amount_to_capture: amount_in_cents }, opts) }
      end

      # Cancels a Stripe payment intent
      #
      # @param payment_intent_id [String] Stripe payment intent ID, eg. pi_123
      def cancel_payment_intent(payment_intent_id, idempotency_key: nil)
        send_request(idempotency_key: idempotency_key) { |opts| Stripe::PaymentIntent.cancel(payment_intent_id, {}, opts) }
      end

      # Ensures a Stripe payment intent exists for PallasTrade payment
      #
      # @param payment [PallasTrade::Payment] the payment to ensure a payment intent exists for
      # @param amount_in_cents [Integer] the amount in cents
      # @param payment_source [PallasTrade::CreditCard | PallasTrade::PaymentSource] the payment source to use
      # @return [PallasTrade::Payment] the payment with the payment intent
      def ensure_payment_intent_exists_for_payment(payment, amount_in_cents = nil, payment_source = nil, idempotency_key: nil)
        return payment if payment.response_code.present?

        amount_in_cents ||= payment.display_amount.cents
        payment_source ||= payment.source

        response = create_payment_intent(
          amount_in_cents,
          payment.order,
          payment_method_id: payment_source.gateway_payment_profile_id,
          off_session: true,
          customer_profile_id: payment_source.gateway_customer_profile_id,
          idempotency_key: idempotency_key
        )

        payment.update_columns(
          response_code: response.authorization,
          updated_at: Time.current
        )

        payment
      end

      private

      # PALLAS-CUSTOM (2026-09-19, PRD-20260919-checkout-express-always-visible-and-pi-params):
      # PaymentIntent 顶层载荷断言 —— 只读键（billing_details/charges/...）与白名单外键
      # 均直接抛出，不再把非法参数送到 Stripe。返回原载荷方便链式调用。
      def assert_legal_payment_intent_payload!(payload)
        keys = payload.keys.map(&:to_sym)

        read_only = keys & PAYMENT_INTENT_READ_ONLY_KEYS
        if read_only.any?
          raise ArgumentError,
                "Stripe PaymentIntent payload contains read-only keys: #{read_only.join(', ')} " \
                '(billing_details must be set via a PaymentMethod or payment_intent_data)'
        end

        unknown = keys - PAYMENT_INTENT_TOP_LEVEL_KEYS
        if unknown.any?
          raise ArgumentError, "Stripe PaymentIntent payload contains unsupported keys: #{unknown.join(', ')}"
        end

        payload
      end

      def stripe_capture_method
        auto_capture? ? nil : MANUAL_CAPTURE_METHOD
      end

      def payment_intent_accepted_statuses(payment_intent)
        statuses = %w[succeeded]
        statuses << 'requires_capture' if payment_intent_manual_capture?(payment_intent)
        statuses << 'processing' if payment_intent_delayed_notification?(payment_intent)
        statuses << 'requires_action' if payment_intent_charge_not_required?(payment_intent)
        statuses
      end
    end
  end
end
