module PallasTrade
  module Seeds
    class StockLocations
      prepend PallasTrade::ServiceModule::Base

      def call
        country = PallasTrade::Store.default.default_country
        PallasTrade::StockLocation.find_or_create_by!(
          name: PallasTrade.t(:default_stock_location_name),
          propagate_all_variants: false,
          country: country,
          active: true,
          default: true
        )
      end
    end
  end
end
