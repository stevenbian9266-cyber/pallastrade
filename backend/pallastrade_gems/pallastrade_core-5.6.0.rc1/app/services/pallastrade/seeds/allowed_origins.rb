module PallasTrade
  module Seeds
    class AllowedOrigins
      prepend PallasTrade::ServiceModule::Base

      def call
        store = PallasTrade::Store.default
        return unless store&.persisted?

        store.allowed_origins.find_or_create_by!(origin: 'http://localhost')
      end
    end
  end
end
