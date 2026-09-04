# frozen_string_literal: true

# PALLAS-CUSTOM: CHK-P1-1B (PRD-20260903-checkout-chk-p1-1 §12)
# Order Checkout Mutation Facade —— 只 WRAP 既有 Domain Services，禁止复制逻辑。
module PallasTrade
  module OrderCheckout
    # 订单域改选物流：WRAP Shipments::Update（其负责 rate 选中、cost 镜像、
    # order shipment_total/payment_state/shipment_state 重算与持久化）。
    # 说明：运费重算完全沿用 Shipments::Update 既有语义；运费敏感税一致性 /
    # price-version 由 CHK-P1-2（Invalidation/Version）负责，本包不新增。
    class SelectShipping
      prepend PallasTrade::ServiceModule::Base

      UNSELECTABLE_SHIPMENT_STATES = %w[shipped canceled].freeze

      # @param order [PallasTrade::Order]
      # @param delivery_rate_id [String] prefixed `dr_`（或裸 id）
      def call(order:, delivery_rate_id:)
        return failure(order, 'Order already completed') if order.completed?

        shipment = order.shipments.find { |s| !UNSELECTABLE_SHIPMENT_STATES.include?(s.state.to_s) }
        return failure(order, 'No selectable shipment on this order') if shipment.nil?

        rate = resolve_rate(delivery_rate_id)
        return failure(order, 'Delivery rate not found') if rate.nil?
        return failure(order, 'Delivery rate is not available for this shipment') unless shipment.shipping_rates.where(id: rate.id).exists?

        result = PallasTrade::Shipments::Update.call(
          shipment: shipment,
          shipment_attributes: { selected_shipping_rate_id: rate.id }
        )
        return result unless result.success?

        # CHK-P1-2：Shipments::Update 已重算 totals；Recalculate 幂等补齐 tax/price_version
        recalculated = PallasTrade::OrderCheckout::Recalculate.call(order: order.reload)
        return recalculated unless recalculated.success?

        success(PallasTrade::OrderCheckout::View.call(order: recalculated.value))
      end

      private

      def resolve_rate(delivery_rate_id)
        id = delivery_rate_id.to_s
        if id.start_with?('dr_')
          PallasTrade::ShippingRate.find_by_prefix_id(id)
        else
          PallasTrade::ShippingRate.find_by(id: id)
        end
      end
    end
  end
end
