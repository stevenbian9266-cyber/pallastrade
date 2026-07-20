module PallasTrade
  module Cart
    class Create
      prepend PallasTrade::ServiceModule::Base

      def call(user:, store:, currency:, public_metadata: {}, private_metadata: {}, order_params: {})
        order_params ||= {}

        # we cannot create an order without store
        return failure(:store_is_required) if store.nil?

        default_params = {
          user: user,
          market: PallasTrade::Current.market,
          currency: currency || store.default_currency,
          token: PallasTrade::GenerateToken.new.call(PallasTrade::Order),
          public_metadata: public_metadata.to_h,
          private_metadata: private_metadata.to_h
        }

        order = store.orders.create!(default_params.merge(order_params))
        success(order)
      end
    end
  end
end
