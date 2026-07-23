module PallasTradeStripe
  class OrderCompletedSubscriber < PallasTrade::Subscriber
    subscribes_to 'order.completed'

    on 'order.completed', :attach_customer_to_credit_card

    def attach_customer_to_credit_card(event)
      order_id = event.payload['id']
      return if order_id.blank?

      PallasTradeStripe::AttachCustomerToCreditCardJob.perform_later(order_id)
    end
  end
end
