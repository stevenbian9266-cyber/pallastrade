module PallasTrade
  module Seeds
    class StoreCreditCategories
      prepend PallasTrade::ServiceModule::Base

      def call
        # FIXME: we should use translations here
        PallasTrade::StoreCreditCategory.find_or_create_by!(name: 'Default')
        PallasTrade::StoreCreditCategory.find_or_create_by!(name: 'Non-expiring')
        PallasTrade::StoreCreditCategory.find_or_create_by!(name: 'Expiring')
      end
    end
  end
end
