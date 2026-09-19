module PallasTradeStripe
  class PaymentIntentPresenter
    SETUP_FUTURE_USAGE = 'off_session'
    # D15 切片3：强制挑战取值（Stripe 卡入口）
    THREE_D_SECURE_REQUEST = 'any'

    def initialize(amount:, order:, customer: nil, payment_method_id: nil, off_session: false, capture_method: nil,
                   three_d_secure: false)
      @amount = amount
      @order = order
      @customer = customer
      @ship_address = order.ship_address
      @payment_method_id = payment_method_id
      @off_session = off_session
      @capture_method = capture_method
      @three_d_secure = three_d_secure == true
    end

    def call
      payload = if payment_method_id.present?
                  saved_payment_method_payload
                else
                  new_payment_method_payload
                end

      payload = payload.deep_merge(basic_payload)
      payload = payload.merge(capture_method: PallasTradeStripe::Gateway::PaymentIntents::MANUAL_CAPTURE_METHOD) if manual_capture?

      # PALLAS-CUSTOM (2026-09-19, PRD-20260919-checkout-express-always-visible-and-pi-params 回归修复):
      # ⛔ 这里曾合并顶层 `billing_details` —— Stripe 侧 PaymentIntent 的该字段是**只读**的
      # （仅 retrieve 返回，创建/更新会 400 `parameter_unknown: billing_details`，
      # 于是所有卡/钱包支付在「建会话」阶段就失败）。
      # 账单详情的三条合法通路（全部保留，本方法不再输出该键）：
      #   ① 客户端确认时 PM 级 `payment_method.billing_details`（CardPaymentForm / 钱包）；
      #   ② Checkout Session 模式的 `payment_intent_data.billing_details`（CheckoutSessionPresenter）；
      #   ③ 支付完成后由 `charge.billing_details` 回读快照。
      # 回归守卫见 spec/presenters/payment_intent_presenter_spec.rb（白名单断言）。
      return payload unless ship_address

      # we don't validate address1, but it's required by Stripe
      if ship_address.invalid? || ship_address.address1.blank?
        ship_address.errors.clear
        return payload
      end

      payload.merge(ship_address_payload)
    end

    # PALLAS-CUSTOM (2026-09-19, PRD-20260919-checkout-billing-details-passthrough)：
    # 与 CheckoutSessionPresenter 同源（共享 `BillingDetailsPresenter`）；不可用 → nil。
    # ⚠️ 仅供**其它合法载体**（如 `payment_method_data` / `payment_intent_data`）复用，
    # 绝不可再并入 PaymentIntent 顶层参数。
    def billing_details_payload
      @billing_details_payload ||= begin
        details = PallasTradeStripe::BillingDetailsPresenter.new(order: order).call
        details ? { billing_details: details } : nil
      end
    end

    def ship_address_payload
      {
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
    end

    private

    attr_reader :order, :amount, :customer, :ship_address, :payment_method_id, :capture_method

    def manual_capture?
      capture_method.to_s == PallasTradeStripe::Gateway::PaymentIntents::MANUAL_CAPTURE_METHOD
    end

    def basic_payload
      {
        amount: amount,
        customer: customer,
        currency: order.currency,
        statement_descriptor_suffix: statement_descriptor_suffix,
        automatic_payment_methods: {
          enabled: true
        },
        transfer_group: order.number,
        metadata: {
          pallastrade_order_id: order.id
        }
      }
    end

    def statement_descriptor_suffix
      PallasTradeStripe::StatementDescriptorSuffixPresenter.new(order_description: order.number).call
    end

    def new_payment_method_payload
      card_options = { setup_future_usage: SETUP_FUTURE_USAGE }
      # D15 切片3：本单要求认证 → 强制 3DS（Stripe 卡入口）
      card_options[:request_three_d_secure] = THREE_D_SECURE_REQUEST if three_d_secure?

      {
        payment_method_options: {
          card: card_options,
          sepa_debit: {
            setup_future_usage: SETUP_FUTURE_USAGE
          }
        }
      }
    end

    def three_d_secure?
      @three_d_secure == true
    end

    def saved_payment_method_payload
      {
        payment_method: payment_method_id,
        off_session: @off_session,
        confirm: @off_session # confirm is required for off_session payments
      }
    end
  end
end
