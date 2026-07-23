# frozen_string_literal: true

module PallasTrade
  # Handles order completion events to update product metrics
  # (+units_sold_count+, +revenue+).
  class ProductMetricsSubscriber < PallasTrade::Subscriber
    subscribes_to 'order.completed'

    on 'order.completed', :refresh_product_metrics

    def refresh_product_metrics(event)
      order_id = event.payload['id']
      return unless order_id

      order = PallasTrade::Order.find_by_param(order_id)
      return unless order

      product_ids = order.line_items.includes(:variant).map { |li| li.variant.product_id }.uniq
      return if product_ids.empty?

      jobs = product_ids.map { |product_id| PallasTrade::Products::RefreshMetricsJob.new(product_id) }
      ActiveJob.perform_all_later(jobs)
    end
  end
end
