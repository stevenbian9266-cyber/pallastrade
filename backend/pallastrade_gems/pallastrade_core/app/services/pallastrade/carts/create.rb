module PallasTrade
  module Carts
    # 订单流程标准电商改造 P1（2026-08-30）：创建购物车（pallastrade_carts 实体）。
    # 与 legacy `CartLegacy::Create`（操作 Order 同表）语义分离——本服务操作 `PallasTrade::Cart`。
    class Create
      prepend PallasTrade::ServiceModule::Base

      def call(params: {})
        @params = params.to_h.deep_symbolize_keys

        store = @params.delete(:store)
        return failure(:store_is_required) if store.nil?

        cart = store.shopping_carts.create!(
          user: @params.delete(:user),
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
