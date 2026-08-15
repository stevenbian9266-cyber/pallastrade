# frozen_string_literal: true

module PallasTrade
  # Sends back-in-stock notifications when a product comes back in stock.
  #
  # The `product.back_in_stock` event is published by `StockMovement::CustomEvents`
  # when a product transitions from out-of-stock → in-stock. We scan active
  # subscriptions for all of the product's variants, send an email and mark each
  # subscription as notified (idempotent — a subscription never fires twice).
  class BackInStockSubscriber < PallasTrade::Subscriber
    subscribes_to 'product.back_in_stock'

    on 'product.back_in_stock', :notify_subscribers

    private

    def notify_subscribers(event)
      product = PallasTrade::Product.find_by_param(event.payload['id'])
      return unless product

      PallasTrade::BackInStockSubscription
        .where(product_id: product.id)
        .active
        .includes(:product)
        .find_each do |subscription|
          notify_subscription(subscription)
        end
    end

    def notify_subscription(subscription)
      PallasTrade::BackInStockMailer.back_in_stock(subscription).deliver_later
      subscription.mark_notified!
    rescue StandardError => e
      Rails.logger.error("[BackInStock] failed to notify subscription #{subscription.id}: #{e.message}")
    end
  end
end
