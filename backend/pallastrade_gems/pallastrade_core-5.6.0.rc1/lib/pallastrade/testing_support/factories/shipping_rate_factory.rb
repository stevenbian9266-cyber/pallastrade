FactoryBot.define do
  factory :shipping_rate, class: PallasTrade::ShippingRate do
    cost { BigDecimal(10) }
    shipping_method
    shipment
  end
end
