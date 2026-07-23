module PallasTrade
  module Exports
    class Orders < PallasTrade::Export
      def scope_includes
        [
          :store,
          :payments,
          :shipments,
          { bill_address: [:state, :country] },
          { ship_address: [:state, :country] },
          { line_items: { variant: { product: [:taxons] } } },
          { metafields: :metafield_definition }
        ]
      end

      def multi_line_csv?
        true
      end

      def csv_headers
        PallasTrade::CSV::OrderLineItemPresenter::HEADERS + metafields_headers
      end
    end
  end
end
