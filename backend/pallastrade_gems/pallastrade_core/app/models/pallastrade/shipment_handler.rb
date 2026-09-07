module PallasTrade
  class ShipmentHandler
    class << self
      def factory(shipment)
        # Do we have a specialized shipping-method-specific handler? e.g:
        # Given shipment.shipping_method = PallasTrade::ShippingMethod::DigitalDownload
        # do we have PallasTrade::ShipmentHandler::DigitalDownload?
        if sm_handler = "PallasTrade::ShipmentHandler::#{shipment.shipping_method&.name&.split('::')&.last}".safe_constantize
          sm_handler.new(shipment)
        else
          new(shipment)
        end
      end
    end

    def initialize(shipment)
      @shipment = shipment
    end

    def perform
      @shipment.inventory_units.each &:ship!
      @shipment.process_order_payments if PallasTrade::Config[:auto_capture_on_dispatch]
      @shipment.touch :shipped_at
      update_order_shipment_state
      # 标准流程（正向链路）：shipment 已发货 → 推进 Order 标准状态机
      # （paid→processing 部分发货 / →shipped 全部发货）。ship 是唯一同步汇聚点，
      # 覆盖 admin Rails / admin API / Fulfillments::Create 三条发货路径。
      @shipment.order.advance_standard_fulfillment!
    end

    protected

    def update_order_shipment_state
      order = @shipment.order

      new_state = OrderUpdater.new(order).update_shipment_state
      order.update_columns(shipment_state: new_state, updated_at: Time.current)
    end
  end
end
