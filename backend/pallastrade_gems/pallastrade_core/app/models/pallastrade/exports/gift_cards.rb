module PallasTrade
  module Exports
    class GiftCards < PallasTrade::Export
      def scope_includes
        [:user, { metafields: :metafield_definition }]
      end

      def csv_headers
        PallasTrade::CSV::GiftCardPresenter::HEADERS + metafields_headers
      end
    end
  end
end
