module PallasTrade
  module Admin
    module PropertiesHelper
      def sorted_product_properties(product)
        product.product_properties.sort_by_property_position
      end
    end
  end
end
