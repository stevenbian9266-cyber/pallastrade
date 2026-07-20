module PallasTradeStripe
  class AttachCustomerToCreditCardJob < BaseJob
    def perform(order_id)
      return if PallasTrade.user_class.blank?

      order = PallasTrade::Order.find_by(id: order_id)
      return if order.blank? || order.user_id.blank?

      gateway = order.store.stripe_gateway
      return if gateway.blank?

      user = PallasTrade.user_class.find_by(id: order.user_id)
      return if user.blank?

      gateway.attach_customer_to_credit_card(user)
    end
  end
end
