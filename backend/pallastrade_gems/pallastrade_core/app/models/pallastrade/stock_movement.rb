module PallasTrade
  class StockMovement < PallasTrade.base_class
    has_prefix_id :sm

    QUANTITY_LIMITS = {
      max: 2**31 - 1,
      min: -2**31
    }.freeze

    include PallasTrade::StockMovement::Webhooks
    include PallasTrade::StockMovement::CustomEvents

    publishes_lifecycle_events

    belongs_to :stock_item, class_name: 'PallasTrade::StockItem', inverse_of: :stock_movements
    belongs_to :originator, polymorphic: true
    # REV-P6-5：退货 restock 的稳定幂等键（可空；partial unique 见 migration）——
    # 同一 return_item 至多一条正向 movement（源 §42）。originator=ReturnAuthorization 为一对多，
    # 不可作唯一键，故以 return_item_id 承担 exactly-once。
    belongs_to :return_item, class_name: 'PallasTrade::ReturnItem', optional: true, inverse_of: :stock_movements

    after_create :update_stock_item_quantity

    with_options presence: true do
      validates :stock_item
      validates :quantity, numericality: {
        greater_than_or_equal_to: :min_quantity,
        less_than_or_equal_to: QUANTITY_LIMITS[:max],
        only_integer: true
      }
    end

    scope :recent, -> { order(created_at: :desc) }

    delegate :variant, :variant_id, to: :stock_item, allow_nil: true
    delegate :product, to: :variant

    self.whitelisted_ransackable_attributes = %w[quantity action created_at stock_item_id originator_type]
    self.whitelisted_ransackable_associations = %w[stock_item]

    def readonly?
      persisted?
    end

    private

    def update_stock_item_quantity
      return unless stock_item.should_track_inventory?

      stock_item.adjust_count_on_hand quantity
    end

    def min_quantity
      return QUANTITY_LIMITS[:min] if stock_item.nil? || stock_item.backorderable?

      -stock_item.count_on_hand
    end
  end
end
