# frozen_string_literal: true

# INV-P3-1 (PRD-20260905-shipping-库存事务集成与预留生命周期-p3-...):
# Reservation 生命周期状态化。
#
#   RESERVED  → COMMITTED：canonical physical consumption（Order#finalize!/StockMovement）
#                          成功后的**事实确认**；不改 count_on_hand（INV-I04/I05）。
#   RESERVED  → RELEASED：未消费的主动释放（UNPAID + cancel/timeout），记 release_reason。
#   RESERVED  → EXPIRED ：TTL（expires_at）到期失效。
#   COMMITTED/RELEASED/EXPIRED 为终态，不回 RESERVED。
#
# active（占用 ATS）语义 = state == RESERVED 且 expires_at > now。
# 历史/终态行保留（不再硬删除），同一 stock_item+line_item 的 RESERVED 唯一性由
# partial unique index（idx_stock_reservations_active_reserved_unique）兜底。
module PallasTrade
  class StockReservation < PallasTrade.base_class
    has_prefix_id :res

    publishes_lifecycle_events

    before_create :set_reserved_at
    after_commit :publish_reserved_event, on: :create

    # 核心生命周期状态（P3 源 §5/§9）
    STATES = %w[reserved committed released expired].freeze
    TERMINAL_STATES = %w[committed released expired].freeze

    belongs_to :stock_item, class_name: 'PallasTrade::StockItem', inverse_of: :stock_reservations
    belongs_to :line_item, class_name: 'PallasTrade::LineItem', inverse_of: :stock_reservations
    belongs_to :order, class_name: 'PallasTrade::Order', inverse_of: :stock_reservations
    # Transaction ownership / trace（FR-007/008）；可空——历史/legacy 行不回溯（FR-051）。
    belongs_to :commerce_transaction, class_name: 'PallasTrade::CommerceTransaction',
                                      inverse_of: :stock_reservations, optional: true

    validates :stock_item, :line_item, :order, :quantity, :expires_at, presence: true
    validates :quantity, numericality: { greater_than: 0, only_integer: true }, presence: true
    validates :state, inclusion: { in: STATES }
    # 同一 stock_item+line_item 的 RESERVED 唯一性由 DB partial unique 保证（见 migration），
    # 不在模型层做全表唯一校验（否则会阻止"终态历史行存在时重新预留"）。

    # —— scopes ——
    scope :reserved, -> { where(state: 'reserved') }
    scope :committed, -> { where(state: 'committed') }
    scope :released, -> { where(state: 'released') }
    scope :expired_state, -> { where(state: 'expired') }

    # active = RESERVED 且未过期（占用 available-to-sell 的行）
    scope :active, -> { reserved.where(arel_table[:expires_at].gt(Time.current)) }
    # expired = RESERVED 但已过 TTL（ExpireJob 的候选，将流转为 EXPIRED 状态）
    scope :expired, -> { reserved.where(arel_table[:expires_at].lteq(Time.current)) }

    scope :for_order, ->(order) { where(order_id: order.id) }
    scope :for_transaction, ->(transaction) { where(commerce_transaction_id: transaction.id) }
    scope :for_store, lambda { |store|
      joins(:order).where(pallastrade_orders: { store_id: store.id })
    }

    # —— 生命周期（state_machines；bang 方法由事件生成，服务层以 state guard 保证幂等） ——
    state_machine :state, initial: :reserved do
      state :reserved
      state :committed
      state :released
      state :expired

      event :commit do
        transition reserved: :committed
      end

      event :release do
        transition reserved: :released
      end

      event :expire do
        transition reserved: :expired
      end

      after_transition to: :committed, do: [:touch_committed_at, :publish_committed_event]
      after_transition to: :released, do: [:touch_released_at, :publish_released_event]
      after_transition to: :expired, do: [:touch_expired_at, :publish_expired_event]
    end

    self.whitelisted_ransackable_attributes = %w[
      stock_item_id line_item_id order_id commerce_transaction_id quantity state
      expires_at reserved_at committed_at released_at expired_at release_reason
    ]
    self.whitelisted_ransackable_associations = %w[stock_item line_item order commerce_transaction]

    # 是否仍在占用 available-to-sell
    def active?
      state == 'reserved' && expires_at > Time.current
    end

    # 终态判断（COMMITTED/RELEASED/EXPIRED 不可再回到 RESERVED）
    def terminal?
      TERMINAL_STATES.include?(state)
    end

    # Resolves the reservation TTL: per-Store preference if set, otherwise
    # the global PallasTrade::Config[:default_stock_reservation_ttl_minutes]. Falls
    # back to 10 minutes if both are unset (e.g. early-boot / fixture state).
    def self.ttl_for(order)
      minutes = order&.store&.preferred_stock_reservation_ttl_minutes
      minutes = PallasTrade::Config[:default_stock_reservation_ttl_minutes] if minutes.blank?
      minutes.to_i.then { |m| m.positive? ? m : 10 }.minutes
    end

    private

    def set_reserved_at
      self.reserved_at ||= Time.current
    end

    # INV-P3-7 (FR-053/054): inventory.* 审计事件（复用 Events/audit_logs 通道，不新建 Audit Engine）
    def publish_reserved_event
      publish_event('inventory.reserved', inventory_event_payload)
    end

    def publish_committed_event
      publish_event('inventory.committed', inventory_event_payload)
    end

    def publish_released_event
      publish_event('inventory.released', inventory_event_payload)
    end

    def publish_expired_event
      publish_event('inventory.expired', inventory_event_payload)
    end

    def inventory_event_payload
      {
        id: prefixed_id,
        state: state,
        order_id: order&.prefixed_id,
        commerce_transaction_id: commerce_transaction&.prefixed_id,
        stock_item_id: stock_item&.prefixed_id,
        line_item_id: line_item&.prefixed_id,
        quantity: quantity,
        release_reason: release_reason
      }
    end

    def touch_committed_at
      update_column(:committed_at, Time.current) if committed_at.nil?
    end

    def touch_released_at
      update_column(:released_at, Time.current) if released_at.nil?
    end

    def touch_expired_at
      update_column(:expired_at, Time.current) if expired_at.nil?
    end
  end
end
