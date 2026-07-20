module PallasTrade
  module Exports
    class Customers < PallasTrade::Export
      def scope_includes
        [
          { bill_address: :state },
          { ship_address: :state },
          { metafields: :metafield_definition }
        ]
      end

      def csv_headers
        PallasTrade::CSV::CustomerPresenter::HEADERS + metafields_headers
      end
    end
  end
end
