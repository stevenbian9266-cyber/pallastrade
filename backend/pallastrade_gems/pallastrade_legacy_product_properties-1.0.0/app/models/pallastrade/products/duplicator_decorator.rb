module PallasTrade
  module Products
    module DuplicatorDecorator
      def call(product:, include_images: true)
        result = super
        return result unless result.success?

        new_product = result.value
        new_product.product_properties = duplicate_properties(product.product_properties) if new_product.persisted?

        result
      end

      protected

      def duplicate_properties(product_properties)
        product_properties.map do |prop|
          new_prop = prop.dup
          new_prop.product = nil
          new_prop.created_at = nil
          new_prop.updated_at = nil
          new_prop
        end
      end
    end
  end
end

PallasTrade::Products::Duplicator.prepend(PallasTrade::Products::DuplicatorDecorator)
