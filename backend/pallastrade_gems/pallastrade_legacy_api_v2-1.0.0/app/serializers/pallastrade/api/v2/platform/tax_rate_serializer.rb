module PallasTrade
  module Api
    module V2
      module Platform
        class TaxRateSerializer < BaseSerializer
          include ResourceSerializerConcern

          belongs_to :zone, serializer: PallasTrade.api.platform_zone_serializer
          belongs_to :tax_category, serializer: PallasTrade.api.platform_tax_category_serializer
        end
      end
    end
  end
end
