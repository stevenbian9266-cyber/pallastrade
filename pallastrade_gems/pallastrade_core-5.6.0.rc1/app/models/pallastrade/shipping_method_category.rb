module PallasTrade
  class ShippingMethodCategory < PallasTrade.base_class
    has_prefix_id :smcat

    belongs_to :shipping_method, class_name: 'PallasTrade::ShippingMethod'
    belongs_to :shipping_category, class_name: 'PallasTrade::ShippingCategory', inverse_of: :shipping_method_categories
  end
end
