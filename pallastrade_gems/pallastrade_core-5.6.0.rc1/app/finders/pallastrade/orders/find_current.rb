module PallasTrade
  module Orders
    class FindCurrent
      include PallasTrade::Orders::FinderHelper

      def execute(user:, store:, **params)
        params = params.merge(store_id: store.id)

        order = incomplete_orders.find_by(params)

        return order unless order.nil?
        return if user.nil?

        incomplete_orders.order(created_at: :desc).find_by(store: store, user: user, currency: params[:currency])
      end

      private

      def incomplete_orders
        PallasTrade::Order.incomplete.not_canceled.includes(order_includes)
      end
    end
  end
end
