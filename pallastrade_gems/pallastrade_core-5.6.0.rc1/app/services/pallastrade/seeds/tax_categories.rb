module PallasTrade
  module Seeds
    class TaxCategories
      prepend PallasTrade::ServiceModule::Base

      def call
        PallasTrade::TaxCategory.find_or_create_by(name: 'Default', is_default: true)
        PallasTrade::TaxCategory.find_or_create_by(name: 'Non-taxable')
      end
    end
  end
end
