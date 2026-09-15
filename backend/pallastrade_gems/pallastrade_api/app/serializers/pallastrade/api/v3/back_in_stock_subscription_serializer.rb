module PallasTrade
  module Api
    module V3
      class BackInStockSubscriptionSerializer < BaseSerializer
        typelize product_id: [:string, nullable: true], variant_id: [:string, nullable: true], email: :string, status: :string

        attribute :product_id do |subscription|
          subscription.product&.prefixed_id
        end

        # Batch C-2: present for SKU-level subscriptions, null for legacy ones.
        attribute :variant_id do |subscription|
          subscription.variant&.prefixed_id
        end

        attributes :email, :status, created_at: :iso8601
      end
    end
  end
end
