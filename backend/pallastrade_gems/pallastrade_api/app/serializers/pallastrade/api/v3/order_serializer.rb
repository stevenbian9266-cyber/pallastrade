module PallasTrade
  module Api
    module V3
      # Store API Order Serializer
      # Post-purchase order data (completed orders)
      class OrderSerializer < BaseSerializer
        typelize number: :string, email: :string,
                 customer_note: [:string, nullable: true],
                 market_id: [:string, nullable: true], channel_id: [:string, nullable: true],
                 currency: :string, locale: [:string, nullable: true], total_quantity: :number,
                 fulfillment_status: [:string, nullable: true], payment_status: [:string, nullable: true],
                 item_total: [:string, nullable: true], display_item_total: [:string, nullable: true],
                 delivery_total: [:string, nullable: true], display_delivery_total: [:string, nullable: true],
                 adjustment_total: [:string, nullable: true], display_adjustment_total: [:string, nullable: true],
                 discount_total: [:string, nullable: true], display_discount_total: [:string, nullable: true],
                 tax_total: [:string, nullable: true], display_tax_total: [:string, nullable: true],
                 included_tax_total: [:string, nullable: true], display_included_tax_total: [:string, nullable: true],
                 additional_tax_total: [:string, nullable: true], display_additional_tax_total: [:string, nullable: true],
                 store_credit_total: [:string, nullable: true], display_store_credit_total: [:string, nullable: true],
                 gift_card_total: [:string, nullable: true], display_gift_card_total: [:string, nullable: true],
                 covered_by_store_credit: :boolean,
                 total: [:string, nullable: true], display_total: [:string, nullable: true],
                 amount_due: [:string, nullable: true], display_amount_due: [:string, nullable: true],
                 completed_at: [:string, nullable: true],
                 parent_id: [:string, nullable: true],
                 children_ids: [:string, multi: true],
                 is_parent: :boolean, is_child: :boolean, is_single: :boolean,
                 billing_address: { nullable: true }, shipping_address: { nullable: true },
                 gift_card: { nullable: true }, market: { nullable: true }

        attribute :market_id do |order|
          order.market&.prefixed_id
        end

        attribute :channel_id do |order|
          order.channel&.prefixed_id
        end

        attributes :number, :email, :customer_note,
                   :currency, :locale, :total_quantity,
                   :fulfillment_status, :payment_status,
                   :parent_id, :children_ids, :is_parent, :is_child, :is_single,
                   completed_at: :iso8601

        # Nulled for gated (prices_hidden) guests, consistent with cart and
        # catalog price hiding.
        money_attributes :item_total, :display_item_total,
                         :adjustment_total, :display_adjustment_total,
                         :discount_total, :display_discount_total,
                         :tax_total, :display_tax_total, :included_tax_total, :display_included_tax_total,
                         :additional_tax_total, :display_additional_tax_total, :total, :display_total,
                         :gift_card_total, :display_gift_card_total,
                         :amount_due, :display_amount_due,
                         :delivery_total, :display_delivery_total

        attribute :store_credit_total do |order|
          order.total_applied_store_credit.to_s unless params[:hide_prices]
        end

        attribute :display_store_credit_total do |order|
          order.display_total_applied_store_credit.to_s unless params[:hide_prices]
        end

        attribute :covered_by_store_credit do |order|
          order.covered_by_store_credit?
        end

        # Order lifecycle P1 (2026-08-26): parent/child order structure.
        # Non-split orders are single (parent_id nil, no children).
        attribute :parent_id do |order|
          order.parent&.prefixed_id
        end

        attribute :children_ids do |order|
          order.children.map(&:prefixed_id)
        end

        attribute :is_parent do |order|
          order.parent_order?
        end

        attribute :is_child do |order|
          order.child_order?
        end

        attribute :is_single do |order|
          order.single_order?
        end

        many :discounts, resource: proc { PallasTrade.api.discount_serializer }
        many :line_items, key: :items, resource: proc { PallasTrade.api.line_item_serializer }
        many :fulfillments, resource: proc { PallasTrade.api.fulfillment_serializer }
        many :payments, resource: proc { PallasTrade.api.payment_serializer }
        one :billing_address, resource: proc { PallasTrade.api.address_serializer }
        one :shipping_address, resource: proc { PallasTrade.api.address_serializer }
        one :gift_card, resource: proc { PallasTrade.api.gift_card_serializer }
        one :market, resource: proc { PallasTrade.api.market_serializer }
      end
    end
  end
end
