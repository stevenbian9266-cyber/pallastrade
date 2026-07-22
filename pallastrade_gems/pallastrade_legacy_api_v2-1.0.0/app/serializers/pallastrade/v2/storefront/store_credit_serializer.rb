module PallasTrade
  module V2
    module Storefront
      class StoreCreditSerializer < BaseSerializer
        include PallasTrade::Api::V2::PublicMetafieldsConcern

        set_type :store_credit

        belongs_to :category, serializer: PallasTrade.api.storefront_store_credit_category_serializer
        has_many :store_credit_events, serializer: PallasTrade.api.storefront_store_credit_event_serializer
        belongs_to :credit_type,
                   id_method_name: :type_id,
                   serializer: PallasTrade.api.storefront_store_credit_type_serializer

        attributes :amount, :amount_used, :created_at, :public_metadata
      end
    end
  end
end
