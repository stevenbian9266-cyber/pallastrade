module PallasTrade
  module Products
    module PrepareNestedAttributesDecorator
      def call
        # Mark product properties for removal when value is left blank
        if params[:product_properties_attributes].present?
          params[:product_properties_attributes].each do |key, product_property_params|
            next unless product_property_params[:id].present?
            next if product_property_params[:value].present?

            # https://api.rubyonrails.org/v7.1.3.4/classes/ActiveRecord/NestedAttributes/ClassMethods.html
            params[:product_properties_attributes][key]['_destroy'] = '1'
          end
        end

        super
      end
    end
  end
end

PallasTrade::Products::PrepareNestedAttributes.prepend(PallasTrade::Products::PrepareNestedAttributesDecorator)
