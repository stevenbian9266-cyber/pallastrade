# frozen_string_literal: true

module PallasTrade
  # Sends back-in-stock notifications.
  #
  # Batch C-2 (PRD-20260915-catalog-batch-c2-sku-back-in-stock) splits the two
  # audiences so nobody is emailed about the wrong SKU:
  #
  # - `variant.back_in_stock` (published by `StockMovement::CustomEvents` with the
  #   variant that became buyable) → only the subscriptions for that variant.
  # - `product.back_in_stock` (the product as a whole is back) → the legacy
  #   product-level subscriptions (`variant_id` IS NULL) only, because SKU
  #   subscribers are served by their own event.
  #
  # Each subscription is marked notified after send, so it never fires twice.
  class BackInStockSubscriber < PallasTrade::Subscriber
    subscribes_to 'product.back_in_stock', 'variant.back_in_stock'

    on 'product.back_in_stock', :notify_product_subscribers
    on 'variant.back_in_stock', :notify_variant_subscribers

    private

    def notify_product_subscribers(event)
      product = PallasTrade::Product.find_by_param(event.payload['id'])
      return unless product

      notify_each(
        PallasTrade::BackInStockSubscription
          .where(product_id: product.id)
          .product_level
          .active
          .includes(:product, :variant)
      )
    end

    def notify_variant_subscribers(event)
      variant = PallasTrade::Variant.find_by_prefix_id(event.payload['id'])
      return unless variant

      notify_each(
        PallasTrade::BackInStockSubscription
          .for_variant(variant.id)
          .active
          .includes(:product, :variant)
      )
    end

    def notify_each(subscriptions)
      subscriptions.find_each { |subscription| notify_subscription(subscription) }
    end

    def notify_subscription(subscription)
      PallasTrade::BackInStockMailer.back_in_stock(subscription).deliver_later
      subscription.mark_notified!
    rescue StandardError => e
      Rails.logger.error("[BackInStock] failed to notify subscription #{subscription.id}: #{e.message}")
    end
  end
end
