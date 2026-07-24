module PallasTrade
  module Products
    module FindDecorator
      def initialize(scope:, params:)
        @properties = params.dig(:filter, :properties)
        super
      end

      def execute
        products = super
        # Apply property filtering after all other filters
        by_properties(products)
      end

      private

      attr_reader :properties

      def properties?
        properties.present? && properties.values.reject(&:empty?).present?
      end

      def by_properties(products)
        return products unless properties?

        product_ids = []
        index = 0

        properties.to_unsafe_hash.each do |property_filter_param, product_properties_values|
          next if property_filter_param.blank? || product_properties_values.empty?

          values = product_properties_values.split(',').reject(&:empty?).uniq.map(&:parameterize)

          next if values.empty?

          ids = scope.unscope(:order, :includes).with_property_values(property_filter_param, values).ids
          product_ids = index == 0 ? ids : product_ids & ids
          index += 1
        end

        products.where(id: product_ids)
      end
    end
  end
end

PallasTrade::Products::Find.prepend(PallasTrade::Products::FindDecorator)
