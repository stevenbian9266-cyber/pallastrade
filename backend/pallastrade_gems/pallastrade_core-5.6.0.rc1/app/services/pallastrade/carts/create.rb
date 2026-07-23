module PallasTrade
  module Carts
    class Create
      prepend PallasTrade::ServiceModule::Base

      def call(params: {})
        @params = params.to_h.deep_symbolize_keys

        store = @params.delete(:store)
        return failure(:store_is_required) if store.nil?

        cart = store.carts.create!(
          user: @params.delete(:user),
          market: @params.delete(:market) || PallasTrade::Current.market,
          channel: @params.delete(:channel) || PallasTrade::Current.channel,
          currency: @params.delete(:currency) || store.default_currency,
          locale: @params.delete(:locale) || PallasTrade::Current.locale
        )

        # Delegate all attribute/address/item processing to Carts::Update
        if @params.present?
          result = PallasTrade::Carts::Update.call(cart: cart, params: @params)
          return result if result.failure?
        end

        success(cart.reload)
      rescue ActiveRecord::RecordNotFound
        raise
      rescue StandardError => e
        failure(nil, e.message)
      end
    end
  end
end
