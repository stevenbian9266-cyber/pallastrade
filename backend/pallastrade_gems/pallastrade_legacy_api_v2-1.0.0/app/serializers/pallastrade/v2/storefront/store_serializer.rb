module PallasTrade
  module V2
    module Storefront
      class StoreSerializer < BaseSerializer
        include PallasTrade::Api::V2::StoreMediaSerializerImagesConcern
        include PallasTrade::Api::V2::PublicMetafieldsConcern

        set_type :store

        attributes :name, :url, :meta_description, :meta_keywords, :seo_title, :default_currency,
                   :default, :supported_currencies, :facebook, :twitter, :instagram, :default_locale,
                   :customer_support_email, :description, :address, :contact_phone, :supported_locales

        has_one :default_country, serializer: PallasTrade.api.storefront_country_serializer, record_type: :country, id_method_name: :default_country_id
      end
    end
  end
end
