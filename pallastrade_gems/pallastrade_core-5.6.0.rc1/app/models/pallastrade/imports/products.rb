module PallasTrade
  module Imports
    class Products < PallasTrade::Import
      def row_processor_class
        PallasTrade::Imports::RowProcessors::ProductVariant
      end

      # Group by slug: product row + its variant rows must be processed together
      def group_column
        'slug'
      end
    end
  end
end
