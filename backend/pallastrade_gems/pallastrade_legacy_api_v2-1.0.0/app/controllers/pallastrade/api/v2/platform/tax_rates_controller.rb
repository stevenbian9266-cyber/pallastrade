module PallasTrade
  module Api
    module V2
      module Platform
        class TaxRatesController < ResourceController
          private

          def model_class
            PallasTrade::TaxRate
          end

          def scope_includes
            [:zone, :tax_category]
          end

          def pallastrade_permitted_attributes
            super + [calculator_attributes: PallasTrade::Calculator.json_api_permitted_attributes]
          end

          def resource_serializer
            PallasTrade.api.platform_tax_rate_serializer
          end
        end
      end
    end
  end
end
