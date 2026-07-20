module PallasTrade
  module Imports
    class ProductTranslations < PallasTrade::Import
      def row_processor_class
        PallasTrade::Imports::RowProcessors::ProductTranslation
      end

      def group_column
        'slug'
      end

      def model_class
        PallasTrade::Product
      end

      def self.model_class
        PallasTrade::Product
      end

      # Translation imports write products, so they share the products scope
      # (mirrors PallasTrade::Exports::ProductTranslations.required_scope).
      def self.required_scope
        :products
      end
    end
  end
end
