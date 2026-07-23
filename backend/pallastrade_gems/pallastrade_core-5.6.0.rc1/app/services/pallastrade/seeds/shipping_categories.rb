module PallasTrade
  module Seeds
    class ShippingCategories
      prepend PallasTrade::ServiceModule::Base

      def call
        PallasTrade::ShippingCategory.find_or_create_by!(name: I18n.t('PallasTrade.seed.shipping.categories.default'))
        PallasTrade::ShippingCategory.find_or_create_by!(name: I18n.t('PallasTrade.seed.shipping.categories.digital'))
      end
    end
  end
end
