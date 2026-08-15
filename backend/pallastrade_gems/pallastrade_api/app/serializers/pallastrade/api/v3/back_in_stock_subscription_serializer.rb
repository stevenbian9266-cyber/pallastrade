module PallasTrade
  module Api
    module V3
      class BackInStockSubscriptionSerializer < BaseSerializer
        typelize product_id: [:string, nullable: true], email: :string, status: :string

        attribute :product_id do |subscription|
          subscription.product&.prefixed_id
        end

        attributes :email, :status, created_at: :iso8601
      end
    end
  end
end
