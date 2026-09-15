module PallasTrade
  module Api
    module V3
      module Store
        module Carts
          class FulfillmentsController < Store::BaseController
            include PallasTrade::Api::V3::CartResolvable
            include PallasTrade::Api::V3::OrderLock
            include PallasTrade::Api::V3::LegacyFlowObservable

            before_action :find_cart!
            # P0-7 / PRD-20260914-checkout-cart-store-credits-canonical FR-007：legacy 流量观测
            # （订单域履约：canonical 等价能力在 /orders/... 与 `PATCH /carts/:id`）。
            before_action :log_legacy_usage_once_fulfillments

            # GET /api/v3/store/carts/:cart_id/fulfillments
            def index
              fulfillments = @cart.shipments.includes(shipping_rates: :shipping_method)
              render json: {
                data: fulfillments.map { |s| PallasTrade.api.fulfillment_serializer.new(s, params: serializer_params).to_h },
                meta: { count: fulfillments.size }
              }
            end

            # PATCH /api/v3/store/carts/:cart_id/fulfillments/:id
            # Select a delivery rate for a specific fulfillment
            def update
              with_order_lock do
                fulfillment = @cart.shipments.find_by_prefix_id!(params[:id])

                if permitted_params[:selected_delivery_rate_id].present?
                  fulfillment.selected_delivery_rate_id = permitted_params[:selected_delivery_rate_id]
                end

                # Auto-advance (e.g. delivery → payment) after rate selection.
                # Temporary — PallasTrade 6 removes the checkout state machine.
                try_advance

                render_cart
              end
            end

            private

            def log_legacy_usage_once_fulfillments
              log_legacy_usage_once(flow_type: 'legacy_cart_fulfillments', action: action_name)
            end

            # §45 matrix：本行 canonical = OrderCheckout Shipping（订单域 checkout 门面）。
            def legacy_canonical_successor
              '/api/v3/store/orders/:order_id/checkout'
            end

            def permitted_params
              params.permit(:selected_delivery_rate_id)
            end

            # Temporary — PallasTrade 6 removes the checkout state machine.
            def try_advance
              return if @cart.confirm? || @cart.complete? || @cart.canceled?

              loop do
                break if @cart.payment?
                break unless @cart.next
              end
            rescue StandardError => e
              Rails.error.report(e, context: { order_id: @cart.id, state: @cart.state }, source: 'PallasTrade.checkout')
            ensure
              @cart.reload
            end
          end
        end
      end
    end
  end
end
