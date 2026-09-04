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
                     discounts: 'Array<{ id: string, amount: string | null, currency: string }>',
                     taxes: 'Array<{ id: string, amount: string | null, currency: string }>',
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
              next if params[:hide_prices]

              view.discounts.map { |d| { id: d.id, amount: d.amount, currency: d.currency } }
            end

            attribute :taxes do |view|
              next if params[:hide_prices]

              view.taxes.map { |t| { id: t.id, amount: t.amount, currency: t.currency } }
            end
          end
        end
      end
    end
  end
end
