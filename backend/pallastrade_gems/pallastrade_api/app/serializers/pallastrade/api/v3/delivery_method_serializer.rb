module PallasTrade
  module Api
    module V3
      class DeliveryMethodSerializer < BaseSerializer
        typelize id: :string, name: :string, code: [:string, nullable: true],
                 display_estimated_price: [:string, nullable: true],
                 estimated_transit_business_days_min: [:number, nullable: true],
                 estimated_transit_business_days_max: [:number, nullable: true]

        attribute :id do |method|
          method.prefixed_id
        end

        attributes :name, :code, :display_estimated_price,
                   :estimated_transit_business_days_min, :estimated_transit_business_days_max
      end
    end
  end
end
