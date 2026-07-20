module PallasTrade
  module Seeds
    class Roles
      prepend PallasTrade::ServiceModule::Base

      def call
        PallasTrade::Role.where(name: 'admin').first_or_create!
      end
    end
  end
end
