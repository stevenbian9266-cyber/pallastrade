FactoryBot.define do
  factory :digital_link, class: PallasTrade::DigitalLink do
    digital
    line_item
  end
end
