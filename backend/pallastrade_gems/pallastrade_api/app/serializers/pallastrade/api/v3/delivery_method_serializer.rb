module PallasTrade
  module Api
    module V3
      class DeliveryMethodSerializer < BaseSerializer
        typelize id: :string, name: :string, code: [:string, nullable: true],
                 display_estimated_price: [:string, nullable: true]

        attribute :id do |method|
          method.prefixed_id
        end

        attributes :name, :code, :display_estimated_price
      end
    end
  end
end
