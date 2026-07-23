module PallasTrade
  module V2
    module Storefront
      class TaxonomySerializer < BaseSerializer
        include PallasTrade::Api::V2::PublicMetafieldsConcern

        set_type   :taxonomy

        attributes :name, :position, :public_metadata
      end
    end
  end
end
