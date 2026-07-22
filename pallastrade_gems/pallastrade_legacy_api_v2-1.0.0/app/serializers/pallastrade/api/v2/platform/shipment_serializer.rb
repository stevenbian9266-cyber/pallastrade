module PallasTrade
  module Api
    module V2
      module Platform
        class ShipmentSerializer < BaseSerializer
          include ResourceSerializerConcern

          attribute :tracking_url

          belongs_to :order, serializer: PallasTrade.api.platform_order_serializer
          belongs_to :address, serializer: PallasTrade.api.platform_address_serializer
          belongs_to :stock_location, serializer: PallasTrade.api.platform_stock_location_serializer
          has_many :adjustments, serializer: PallasTrade.api.platform_adjustment_serializer
          has_many :inventory_units, serializer: PallasTrade.api.platform_inventory_unit_serializer
          has_many :shipping_rates, serializer: PallasTrade.api.platform_shipping_rate_serializer
          has_many :state_changes, serializer: PallasTrade.api.platform_state_change_serializer
          has_one :selected_shipping_rate, serializer: PallasTrade.api.platform_shipping_rate_serializer, type: :shipping_rate
        end
      end
    end
  end
end
