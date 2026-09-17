module PallasTrade
  module Api
    module V3
      # Store API Price Serializer
      # Represents a resolved/calculated price for storefront display
      # Can represent either a calculated price (with price list resolution) or a base price
      class PriceSerializer < BaseSerializer
        typelize amount: [:string, nullable: true],
                 amount_in_cents: [:number, nullable: true],
                 display_amount: [:string, nullable: true],
                 compare_at_amount: [:string, nullable: true],
                 compare_at_amount_in_cents: [:number, nullable: true],
                 display_compare_at_amount: [:string, nullable: true],
                 currency: [:string, nullable: true],
                 price_list_id: [:string, nullable: true],
                 price_list_ends_at: [:string, nullable: true]

        attributes :amount, :amount_in_cents, :compare_at_amount,
                   :compare_at_amount_in_cents, :currency

        attribute :display_amount do |price|
          price.display_amount&.to_s
        end

        attribute :display_compare_at_amount do |price|
          price.display_compare_at_amount&.to_s
        end

        attribute :price_list_id do |price|
          price.price_list&.prefixed_id
        end

        # 价目表时间窗的结束时刻（PRD-20260917-catalog-json-ld-phase2 FR-002），
        # 供商品页结构化数据的 `priceValidUntil` 使用。
        #
        # **只读派生，不参与任何价格计算** —— 价格仍由 PriceList 的解析逻辑决定，
        # 这个字段只是把「这张价目表什么时候失效」如实报出来。
        # 未命中价目表（回落默认价格）时为 nil，前台据此省略 `priceValidUntil`。
        attribute :price_list_ends_at do |price|
          price.price_list&.ends_at&.iso8601
        end
      end
    end
  end
end
