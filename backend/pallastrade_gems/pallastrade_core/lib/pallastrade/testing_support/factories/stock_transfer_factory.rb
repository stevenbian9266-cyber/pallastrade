FactoryBot.define do
  factory :stock_transfer, class: PallasTrade::StockTransfer do
    association :source_location, factory: :stock_location
    association :destination_location, factory: :stock_location

    stock_movements { [build(:stock_movement)] }

    number {}
    reference {}
    type {}
  end
end
