module PallasTrade
  class RefundReason < PallasTrade.base_class
    has_prefix_id :rr

    include PallasTrade::NamedType

    RETURN_PROCESSING_REASON = 'Return processing'
    ORDER_CANCELED_REASON = 'Order Canceled'
    SHIPMENT_CANCELED_REASON = 'Shipment Canceled'
    # REV-P6-8m：孤儿（provider-only）退款补记的系统原因（8d/8h 边界落地）
    ORPHAN_BACKFILL_REASON = 'Provider Refund Backfill'

    has_many :refunds, dependent: :restrict_with_error

    def self.return_processing_reason
      find_or_create_by(name: RETURN_PROCESSING_REASON, mutable: false)
    end

    def self.order_canceled_reason
      find_or_create_by(name: ORDER_CANCELED_REASON, mutable: false)
    end

    def self.shipment_canceled_reason
      find_or_create_by(name: SHIPMENT_CANCELED_REASON, mutable: false)
    end

    def self.orphan_backfill_reason
      find_or_create_by(name: ORPHAN_BACKFILL_REASON, mutable: false)
    end
  end
end
