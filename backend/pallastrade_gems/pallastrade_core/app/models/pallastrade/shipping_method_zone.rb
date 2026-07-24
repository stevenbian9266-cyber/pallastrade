module PallasTrade
  class ShippingMethodZone < PallasTrade.base_class
    belongs_to :shipping_method, -> { with_deleted }, inverse_of: :shipping_method_zones, class_name: 'PallasTrade::ShippingMethod'
    belongs_to :zone, inverse_of: :shipping_method_zones, class_name: 'PallasTrade::Zone'

    validates :shipping_method, uniqueness: { scope: :zone }
  end
end
