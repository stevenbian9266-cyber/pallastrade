# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      module Store
        module Checkout
          # CHK-P1-1A: Server-driven CheckoutView serializer（只读）。
          #
          # 只做格式化：金额/状态全部来自 CheckoutView（其委托 Order 权威列），
          # 不做任何领域计算（不 requote / retax / repricing / 不推进状态机）。
          # 金额契约与现有 Store Order/Cart serializer 一致（major-unit decimal string；
          # display_* 为展示格式化字符串）；hide_prices 门控金额为 null。
          class CheckoutSerializer < PallasTrade::Api::V3::BaseSerializer
            include PallasTrade::Api::V3::DiscountRendering

            typelize id: :string, number: :string, state: :string, status: :string,
                     payment_state: [:string, { nullable: true }], shipment_state: [:string, { nullable: true }],
                     email: [:string, { nullable: true }], currency: :string,
                     submitted_at: [:string, { nullable: true }], completed_at: [:string, { nullable: true }],
                     version: :number, price_version: [:string, { nullable: true }],
                     expires_at: [:string, { nullable: true }],
                     ready: :boolean, missing_requirements: 'Array<string>',
                     item_total: [:string, { nullable: true }], display_item_total: [:string, { nullable: true }],
                     delivery_total: [:string, { nullable: true }], display_delivery_total: [:string, { nullable: true }],
                     adjustment_total: [:string, { nullable: true }], display_adjustment_total: [:string, { nullable: true }],
                     discount_total: [:string, { nullable: true }], display_discount_total: [:string, { nullable: true }],
                     tax_total: [:string, { nullable: true }], display_tax_total: [:string, { nullable: true }],
                     included_tax_total: [:string, { nullable: true }], display_included_tax_total: [:string, { nullable: true }],
                     additional_tax_total: [:string, { nullable: true }], display_additional_tax_total: [:string, { nullable: true }],
                     total: [:string, { nullable: true }], display_total: [:string, { nullable: true }],
                     amount_due: [:string, { nullable: true }], display_amount_due: [:string, { nullable: true }],
                     discounts: PallasTrade::Api::V3::DiscountRendering::DISCOUNT_LINE_TYPE,
                     taxes: 'Array<{ id: string, amount: string | null, currency: string }>',
                     credits: '{ gift_cards: Array<{ id: string, code: string, amount: string | null, ' \
                              'display_amount: string | null }>, store_credit: { amount: string | null, ' \
                              'display_amount: string | null } | null }',
                     capabilities: '{ can_edit_address: boolean, can_change_shipping: boolean, ' \
                                   'can_apply_promotion: boolean, can_pay: boolean }',
                     billing_mode: :string,
                     payment: '{ available_payment_methods: Array<{ id: string, name: string, ' \
                              'description: string | null, type: string, session_required: boolean, ' \
                              'source_required: boolean, kind: string, frontend_kind: string, ' \
                              'option_id: string, method_key: string, display_name: string, ' \
                              'client_config: { provider: string, environment: string | null, ' \
                              'publishable: Record<string, string>, session_token: string | null } }> }',
                     shipping_address: { nullable: true }, billing_address: { nullable: true }

            attribute :id, &:id
            attributes :number, :state, :status, :payment_state, :shipment_state, :email, :currency

            attribute :submitted_at do |view|
              view.order.submitted_at&.iso8601
            end

            attribute :completed_at do |view|
              view.order.completed_at&.iso8601
            end

            # CHK-P1-2：正式输出版本/过期字段（checkout_version 内容版本、price_version 金额指纹、报价过期）
            attribute :version, &:checkout_version

            attribute :price_version, &:price_version

            # CHK-P1-3：Server Readiness（只读聚合，委托 CheckoutView/Readiness）
            attributes :ready, :missing_requirements

            attribute :expires_at do |view|
              view.order.checkout_expires_at&.iso8601
            end

            # Nulled for gated (prices_hidden) guests，与 cart/order serializer 一致。
            money_attributes :item_total, :display_item_total,
                             :delivery_total, :display_delivery_total,
                             :adjustment_total, :display_adjustment_total,
                             :discount_total, :display_discount_total,
                             :tax_total, :display_tax_total,
                             :included_tax_total, :display_included_tax_total,
                             :additional_tax_total, :display_additional_tax_total,
                             :total, :display_total,
                             :amount_due, :display_amount_due

            one :shipping_address, resource: proc { PallasTrade.api.address_serializer }
            one :billing_address, resource: proc { PallasTrade.api.address_serializer }
            many :items, resource: proc { PallasTrade.api.line_item_serializer }
            many :fulfillments, resource: proc { PallasTrade.api.fulfillment_serializer }

            attribute :discounts do |view|
              discounts_payload(view.order)
            end

            attribute :taxes do |view|
              next if params[:hide_prices]

              view.taxes.map { |t| { id: t.id, amount: t.amount, currency: t.currency } }
            end

            # CHK-P1-1 §17 缺口补齐（PRD-20260914-checkout B1）：礼品卡/店铺余额、能力位、
            # 支付方式（服务端权威）、账单语义派生值。金额一律遵守 hide_prices 门控。
            attribute :credits do |view|
              {
                gift_cards: credits_gift_cards(view),
                store_credit: credits_store_credit(view)
              }
            end

            attributes :capabilities, :billing_mode

            attribute :payment do |view|
              {
                available_payment_methods: view.available_payment_methods.map { |pm| payment_method_payload(pm) }
              }
            end

            private

            def credits_gift_cards(view)
              view.gift_cards.map do |card|
                {
                  id: card[:id],
                  code: card[:code],
                  amount: params[:hide_prices] ? nil : card[:amount],
                  display_amount: params[:hide_prices] ? nil : card[:display_amount]
                }
              end
            end

            def credits_store_credit(view)
              store_credit = view.store_credit
              return nil if store_credit.nil?
              return { amount: nil, display_amount: nil } if params[:hide_prices]

              store_credit
            end

            def payment_method_payload(payment_method)
              {
                id: payment_method.prefixed_id,
                name: payment_method.name,
                description: payment_method.description,
                type: payment_method.class.api_type,
                session_required: payment_method.session_required?,
                source_required: payment_method.source_required?,
                # PALLAS-CUSTOM: PAY-OPT-1（切片2）—— 与 store PaymentMethodSerializer 契约一致。
                kind: payment_method.default_option_kind,
                frontend_kind: payment_method.default_option_frontend_kind,
                # PALLAS-CUSTOM: D16 切片1（PRD-20260916-payments-d16-payment-method-presentation）——
                # 入口级展示元数据（§76.1）：运营配置的「门店显示名」到得了前台；
                # `option_id` 作行键、`method_key` 作入口维度。单一读模型：
                # PallasTrade::PaymentMethod#effective_payment_option（禁止在 serializer 里回落）。
                option_id: payment_method.option_identifier,
                method_key: payment_method.effective_payment_option['kind'] || payment_method.default_option_kind,
                display_name: payment_method.option_display_name,
                # PALLAS-CUSTOM: D10（PRD-20260915-payments-d10-client-config 切片1）——
                # 前台密钥下发（业务方案 §68.4/§76.1）：服务端下发 **publishable 级**凭据，
                # 前端「先读 API、回落 NEXT_PUBLIC_*」，摆脱构建期内联依赖。
                # 唯一组装点：PallasTrade::PaymentMethods::ClientConfig（secret 永不下发）。
                client_config: PallasTrade::PaymentMethods::ClientConfig.call(payment_method)
              }
            end
          end
        end
      end
    end
  end
end
