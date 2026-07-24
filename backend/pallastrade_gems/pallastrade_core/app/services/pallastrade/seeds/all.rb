module PallasTrade
  module Seeds
    class All
      prepend PallasTrade::ServiceModule::Base

      def call
        PallasTrade::Events.disable do
          ActiveRecord::Base.no_touching do
            # GEO
            Countries.call
            States.call
            Zones.call

            # user roles
            Roles.call

            # additional data
            ReturnsEnvironment.call
            ShippingCategories.call
            StoreCreditCategories.call
            TaxCategories.call
            DigitalDelivery.call

            # store & stock location
            Stores.call
            StockLocations.call
            AdminUser.call

            # add store resources
            PaymentMethods.call
            ApiKeys.call
            AllowedOrigins.call
          end
        end
      end
    end
  end
end
