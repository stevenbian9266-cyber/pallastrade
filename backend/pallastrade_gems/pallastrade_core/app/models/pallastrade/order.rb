require_dependency 'pallastrade/order/checkout'
require_dependency 'pallastrade/order/currency_updater'
require_dependency 'pallastrade/order/digital'
require_dependency 'pallastrade/order/payments'
require_dependency 'pallastrade/order/store_credit'
require_dependency 'pallastrade/order/gift_card'

module PallasTrade
  class Order < PallasTrade.base_class
    has_prefix_id :or  # Stripe: or_

    # Legacy free-text `channel` column was replaced by the `channel_id` FK
    # (see 6.0-order-routing.md). The string column stays in the DB so the
    # 5.4-to-5.5 backfill rake can read it; AR ignores it everywhere else.
    self.ignored_columns += ['channel']

    PAYMENT_STATES = %w(balance_due credit_owed failed paid void)
    SHIPMENT_STATES = %w(backorder canceled partial pending ready shipped)
    LINE_ITEM_REMOVABLE_STATES = %w(cart address delivery payment confirm resumed)

    extend PallasTrade::DisplayMoney

    include PallasTrade::Order::Checkout
    include PallasTrade::Order::CurrencyUpdater
    include PallasTrade::Order::Digital
    include PallasTrade::Order::Payments
    include PallasTrade::Order::StoreCredit
    include PallasTrade::Order::AddressBook
    include PallasTrade::Order::Webhooks
    include PallasTrade::Core::NumberGenerator.new(prefix: 'R')
    include PallasTrade::Order::GiftCard

    include PallasTrade::NumberIdentifier
    include PallasTrade::SingleStoreResource

    publishes_lifecycle_events
    include PallasTrade::MemoizedData
    include PallasTrade::Metafields
    include PallasTrade::Metadata
    include PallasTrade::Searchable
    if defined?(PallasTrade::Security::Orders)
      include PallasTrade::Security::Orders
    end
    if defined?(PallasTrade::VendorConcern)
      include PallasTrade::VendorConcern
    end

    has_secure_token :token, length: 35
    has_rich_text :internal_note

    MEMOIZED_METHODS = %w(tax_zone)

    money_methods :outstanding_balance, :item_total,           :adjustment_total,
                  :included_tax_total,  :additional_tax_total, :tax_total,
                  :shipment_total,      :promo_total,          :total,
                  :cart_promo_total,    :pre_tax_item_amount,  :pre_tax_total,
                  :payment_total,       :amount_due,
                  :combined_total, :combined_payment_total,
                  :combined_outstanding_balance, :combined_amount_due

    alias display_ship_total display_shipment_total
    alias_attribute :ship_total, :shipment_total
    def amount_due
      [outstanding_balance - total_applied_store_credit, 0].max
    end

    # Transient warnings populated by remove_out_of_stock_items! and ensure_available_shipping_rates
    attribute :warnings, default: -> { [] }

    # Removes out-of-stock/discontinued items and populates warnings.
    # Returns self (reloaded if items were removed) with warnings set.
    # Captured before the call because removing items reloads the order, which
    # would drop warnings already recorded for the order.
    def remove_out_of_stock_items!
      existing_warnings = warnings
      result = PallasTrade::CartLegacy::RemoveOutOfStockItems.call(order: self)
      return self unless result.success?

      order, _messages, new_warnings = result.value
      order.warnings = existing_warnings | (new_warnings || [])
      order
    end

    # 5.5 API naming bridges (DB columns rename in 6.0)
    alias_attribute :discount_total, :promo_total
    alias display_discount_total display_promo_total
    alias_attribute :customer_note, :special_instructions
    alias_attribute :total_quantity, :item_count

    MONEY_THRESHOLD  = 100_000_000
    MONEY_VALIDATION = {
      presence: true,
      numericality: {
        greater_than: -MONEY_THRESHOLD,
        less_than: MONEY_THRESHOLD,
        allow_blank: true
      },
      format: { with: /\A-?\d+(?:\.\d{1,2})?\z/, allow_blank: true }
    }.freeze

    POSITIVE_MONEY_VALIDATION = MONEY_VALIDATION.deep_dup.tap do |validation|
      validation.fetch(:numericality)[:greater_than_or_equal_to] = 0
    end.freeze

    NEGATIVE_MONEY_VALIDATION = MONEY_VALIDATION.deep_dup.tap do |validation|
      validation.fetch(:numericality)[:less_than_or_equal_to] = 0
    end.freeze

    checkout_flow do
      go_to_state :address
      go_to_state :delivery, if: ->(order) { order.delivery_required? }
      go_to_state :payment, if: ->(order) { order.payment? || order.payment_required? }
      go_to_state :confirm, if: ->(order) { order.confirmation_required? }
      go_to_state :complete
    end

    self.whitelisted_ransackable_associations = %w[shipments user created_by approver canceler promotions bill_address ship_address line_items store channel tags]
    self.whitelisted_ransackable_attributes = %w[
      completed_at email number state status payment_state shipment_state
      total item_total item_count considered_risky channel_id currency
    ]
    self.whitelisted_ransackable_scopes = %w[complete incomplete refunded partially_refunded search multi_search]

    attr_reader :coupon_code
    attr_accessor :temporary_address

    # Set to false on admin-initiated flows to suppress customer-facing emails.
    attr_accessor :notify_customer

    attribute :state_machine_resumed, :boolean

    STATUSES = %w[draft placed canceled].freeze

    attribute :status, :string, default: 'draft'
    validates :status, inclusion: { in: STATUSES }

    scope :drafts,         -> { where(status: 'draft') }
    scope :placed_orders,  -> { where(status: 'placed') }
    scope :canceled_orders, -> { where(status: 'canceled') }

    acts_as_taggable_on :tags
    acts_as_taggable_tenant :store_id

    def tags=(tags)
      self.tag_list = tags
    end

    ASSOCIATED_USER_ATTRIBUTES = [:user_id, :email, :bill_address_id, :ship_address_id]

    # 6.0 forward-compat: User→Customer rename. Column stays user_id in 5.x.
    alias_attribute :customer_id, :user_id

    belongs_to :user, class_name: "::#{PallasTrade.user_class}", optional: true, autosave: true
    belongs_to :created_by, class_name: "::#{PallasTrade.admin_user_class}", optional: true
    belongs_to :approver, class_name: "::#{PallasTrade.admin_user_class}", optional: true
    belongs_to :canceler, class_name: "::#{PallasTrade.admin_user_class}", optional: true

    belongs_to :bill_address, foreign_key: :bill_address_id, class_name: 'PallasTrade::Address',
                              optional: true, dependent: :destroy
    alias_method :billing_address, :bill_address
    alias_method :billing_address=, :bill_address=
    alias_attribute :billing_address_id, :bill_address_id

    belongs_to :ship_address, foreign_key: :ship_address_id, class_name: 'PallasTrade::Address',
                              optional: true, dependent: :destroy
    alias_method :shipping_address, :ship_address
    alias_method :shipping_address=, :ship_address=
    alias_attribute :shipping_address_id, :ship_address_id

    belongs_to :store, class_name: 'PallasTrade::Store'
    belongs_to :market, class_name: 'PallasTrade::Market', optional: true
    belongs_to :channel, class_name: 'PallasTrade::Channel', optional: true
    belongs_to :preferred_stock_location, class_name: 'PallasTrade::StockLocation', optional: true
    # 订单流程标准电商改造 P1（2026-08-30）：来源购物车（分表后 Cart 实体）。
    # 可空——存量订单 / Admin 代下单 / 直接下单无来源购物车。
    belongs_to :cart, class_name: 'PallasTrade::Cart', optional: true, inverse_of: :orders

    # Order lifecycle P1 (2026-08-26): parent/child order structure.
    # - split: children.parent_id points at the parent (container) order;
    #   a non-split order has parent_id = nil and no children (single_order?)
    # - split_from preserves the source order lineage for display only
    belongs_to :parent, class_name: 'PallasTrade::Order', optional: true, inverse_of: :children
    has_many :children, class_name: 'PallasTrade::Order', foreign_key: :parent_id,
                        dependent: :nullify, inverse_of: :parent
    belongs_to :split_from, class_name: 'PallasTrade::Order', optional: true, inverse_of: :split_orders
    has_many :split_orders, class_name: 'PallasTrade::Order', foreign_key: :split_from_id,
                            dependent: :nullify, inverse_of: :split_from
    has_many :payment_splits, class_name: 'PallasTrade::PaymentSplit', inverse_of: :order

    with_options dependent: :destroy do
      has_many :state_changes, as: :stateful, class_name: 'PallasTrade::StateChange'
      has_many :line_items, -> { order(:created_at) }, inverse_of: :order, class_name: 'PallasTrade::LineItem'
      has_many :payments, class_name: 'PallasTrade::Payment'
      has_many :payment_sessions, inverse_of: :order, class_name: 'PallasTrade::PaymentSession'
      has_many :return_authorizations, inverse_of: :order, class_name: 'PallasTrade::ReturnAuthorization'
      has_many :adjustments, -> { order(:created_at) }, as: :adjustable, class_name: 'PallasTrade::Adjustment'
      has_many :cancellations, -> { order(:created_at) }, inverse_of: :order, class_name: 'PallasTrade::OrderCancellation'
      has_many :approvals, -> { order(:created_at) }, inverse_of: :order, class_name: 'PallasTrade::OrderApproval'
    end
    has_many :reimbursements, inverse_of: :order, class_name: 'PallasTrade::Reimbursement'
    has_many :customer_returns, class_name: 'PallasTrade::CustomerReturn', through: :return_authorizations
    has_many :line_item_adjustments, through: :line_items, source: :adjustments
    has_many :inventory_units, inverse_of: :order, class_name: 'PallasTrade::InventoryUnit'
    has_many :stock_reservations, class_name: 'PallasTrade::StockReservation', inverse_of: :order, dependent: :destroy
    has_many :return_items, through: :inventory_units, class_name: 'PallasTrade::ReturnItem'
    has_many :variants, through: :line_items
    has_many :products, through: :variants
    has_many :refunds, through: :payments
    has_many :all_adjustments,
             class_name: 'PallasTrade::Adjustment',
             foreign_key: :order_id,
             dependent: :destroy,
             inverse_of: :order

    has_many :order_promotions, class_name: 'PallasTrade::OrderPromotion'
    has_many :promotions, through: :order_promotions, class_name: 'PallasTrade::Promotion'

    has_many :shipments, class_name: 'PallasTrade::Shipment', dependent: :destroy, inverse_of: :order do
      def states
        pluck(:state).uniq
      end
    end
    has_many :shipment_adjustments, through: :shipments, source: :adjustments

    alias items line_items
    alias discounts order_promotions
    alias fulfillments shipments
    alias_attribute :delivery_total, :shipment_total
    alias display_delivery_total display_shipment_total
    alias_attribute :fulfillment_status, :shipment_state
    alias_attribute :payment_status, :payment_state

    delegate :has_markets?, to: :store, prefix: true

    accepts_nested_attributes_for :line_items
    accepts_nested_attributes_for :bill_address
    accepts_nested_attributes_for :ship_address
    alias shipping_address_attributes= ship_address_attributes=
    alias billing_address_attributes= bill_address_attributes=
    accepts_nested_attributes_for :payments, reject_if: :credit_card_nil_payment?
    accepts_nested_attributes_for :shipments

    # Needs to happen before save_permalink is called
    before_validation :ensure_market_presence
    before_validation :ensure_channel_presence
    before_validation :ensure_currency_presence
    before_validation :ensure_locale_presence
    before_validation :resolve_market_from_currency, if: -> { persisted? && currency_changed? && !skip_market_resolution }

    before_validation :clone_billing_address, if: :use_billing?
    before_validation :clone_shipping_address, if: :use_shipping?
    attr_accessor :use_billing, :use_shipping, :skip_market_resolution

    before_create :link_by_email
    before_update :ensure_updated_shipments, :homogenize_line_item_currencies, if: :currency_changed?

    with_options presence: true do
      # we want to have this case_sentive: true as changing it to false causes all SQL to use LOWER(slug)
      # which is very costly and slow on large set of records
      validates :email, length: { maximum: 254, allow_blank: true }, email: { allow_blank: true }, if: :require_email
      validates :item_count, numericality: { greater_than_or_equal_to: 0, less_than: 2**31, only_integer: true, allow_blank: true }
      validates :store
      validates :currency
      validates :locale
    end
    validates :payment_state,        inclusion:    { in: PAYMENT_STATES, allow_blank: true }
    validates :shipment_state,       inclusion:    { in: SHIPMENT_STATES, allow_blank: true }
    validates :item_total,           POSITIVE_MONEY_VALIDATION
    validates :adjustment_total,     MONEY_VALIDATION
    validates :included_tax_total,   POSITIVE_MONEY_VALIDATION
    validates :additional_tax_total, POSITIVE_MONEY_VALIDATION
    validates :payment_total,        MONEY_VALIDATION
    validates :shipment_total,       MONEY_VALIDATION
    validates :promo_total,          NEGATIVE_MONEY_VALIDATION
    validates :total,                MONEY_VALIDATION
    validates :market, presence: true, if: :store_has_markets?
    validate :currency_must_be_supported_by_store
    validate :locale_must_be_supported_by_store

    delegate :update_totals, :persist_totals, to: :updater
    delegate :merge!, to: :merger
    delegate :firstname, :lastname, to: :bill_address, prefix: true, allow_nil: true

    class_attribute :update_hooks
    self.update_hooks = Set.new

    scope :created_between, ->(start_date, end_date) { where(created_at: start_date..end_date) }
    scope :completed_between, ->(start_date, end_date) { where(completed_at: start_date..end_date) }
    scope :complete, -> { where.not(completed_at: nil) }
    scope :incomplete, -> { where(completed_at: nil) }
    # P0-3 (2026-08-18): carts whose last activity is older than +since+ and that
    # have a contactable email — the abandoned-cart recovery scan target.
    scope :abandoned, ->(since) { incomplete.where.not(email: nil).where('last_activity_at < ?', since) }
    scope :canceled, -> { where(state: %w[canceled partially_canceled]) }
    scope :not_canceled, -> { where.not(state: %w[canceled partially_canceled]) }
    scope :ready_to_ship, -> { where(shipment_state: %w[ready pending]) }
    scope :partially_shipped, -> { where(shipment_state: %w[partial]) }
    scope :not_shipped, -> { where(shipment_state: %w[ready pending partial]) }
    scope :shipped, -> { where(shipment_state: %w[shipped]) }
    scope :refunded, lambda {
      joins(:refunds).group(:id).having("sum(#{PallasTrade::Refund.table_name}.amount) = #{PallasTrade::Order.table_name}.total")
    }
    scope :partially_refunded, lambda {
      joins(:refunds).group(:id).having("sum(#{PallasTrade::Refund.table_name}.amount) < #{PallasTrade::Order.table_name}.total")
    }
    scope :with_deleted_bill_address, -> { joins(:bill_address).where.not(Address.table_name => { deleted_at: nil }) }
    scope :with_deleted_ship_address, -> { joins(:ship_address).where.not(Address.table_name => { deleted_at: nil }) }

    # shows completed orders first, by their completed_at date, then uncompleted orders by their created_at
    scope :reverse_chronological, -> { order(Arel.sql('pallastrade_orders.completed_at IS NULL'), completed_at: :desc, created_at: :desc) }

    def self.search(query)
      sanitized_query = sanitize_query_for_search(query)
      return none if query.blank?

      query_pattern = "%#{sanitized_query}%"

      conditions = []
      conditions << arel_table[:number].lower.matches(query_pattern)

      conditions << search_condition(PallasTrade::Address, :firstname, sanitized_query)
      conditions << search_condition(PallasTrade::Address, :lastname, sanitized_query)

      full_name = NameOfPerson::PersonName.full(sanitized_query)

      if full_name.first.present? && full_name.last.present?
        conditions << search_condition(PallasTrade::Address, :firstname, full_name.first)
        conditions << search_condition(PallasTrade::Address, :lastname, full_name.last)
      end

      left_joins(:bill_address).where(arel_table[:email].lower.eq(query.downcase)).or(where(conditions.reduce(:or)))
    end

    # Backward compatibility alias — remove in PallasTrade 6.0
    def self.multi_search(query) = search(query)

    # Find an order by prefixed ID first, falling back to number, then integer id for backwards compatibility
    # @param param [String] the prefixed ID, number, or integer id to search for
    # @return [PallasTrade::Order, nil] the found order or nil
    def self.find_by_param(param)
      return nil if param.blank?

      # Try prefixed ID first (new format)
      if param.to_s.include?('_')
        decoded = decode_prefixed_id(param)
        order = find_by(id: decoded) if decoded
        return order if order
      end

      # Try number (legacy format)
      order = find_by(number: param)
      return order if order

      # Fall back to id (numeric legacy format) - only if param looks like an integer
      find_by(id: param) if param.to_s.match?(/\A\d+\z/)
    end

    # Find an order by prefixed ID first, falling back to number, then integer id for backwards compatibility
    # Raises ActiveRecord::RecordNotFound if not found
    # @param param [String] the prefixed ID, number, or integer id to search for
    # @return [PallasTrade::Order] the found order
    # @raise [ActiveRecord::RecordNotFound] if order not found
    def self.find_by_param!(param)
      find_by_param(param) || raise(ActiveRecord::RecordNotFound.new("Couldn't find Order with param=#{param}"))
    end

    # Use this method in other gems that wish to register their own custom logic
    # that should be called after Order#update
    def self.register_update_hook(hook)
      update_hooks.add(hook)
    end

    # For compatibility with Calculator::PriceSack
    def amount
      line_items.inject(0.0) { |sum, li| sum + li.amount }
    end

    # Sum of all line item amounts pre-tax
    def pre_tax_item_amount
      line_items.sum(:pre_tax_amount)
    end

    # Sum of all line item and shipment pre-tax
    def pre_tax_total
      pre_tax_item_amount + shipments.sum(:pre_tax_amount)
    end

    # Returns the subtotal used for analytics integrations
    # It's a sum of the item total and the promo total
    # @return [Float]
    def analytics_subtotal
      (item_total + line_items.sum(:promo_total)).to_f
    end

    def shipping_discount
      shipment_adjustments.non_tax.eligible.sum(:amount) * - 1
    end

    def completed?
      completed_at.present?
    end

    # 订单流程标准电商改造 P1（2026-08-30）：标准状态集合（新流程）。
    # 与 legacy checkout 状态（cart/address/.../complete）并行共存——存量数据不迁移，
    # 新流程（Carts::Submit 创建）只走标准状态。standard_flow? 用于隔离两套语义。
    STANDARD_STATES = %w[pending paid processing shipped completed].freeze

    # True when the order was created through the standard flow (Carts::Submit).
    def standard_flow?
      STANDARD_STATES.include?(state)
    end

    # True when the order is mid-checkout: past the `cart` state but not yet
    # completed or canceled. Used by stock reservation hooks and any flow
    # that should only run during the active checkout phase.
    # Standard-flow orders are never "in checkout" — they are created submitted
    # (pending) and only transition through the standard lifecycle.
    def in_checkout?
      return false if standard_flow?

      !cart? && !complete? && !canceled?
    end

    def draft?
      status == 'draft'
    end

    def placed?
      status == 'placed'
    end

    # Checks if the order is fully refunded
    # @return [Boolean]
    def order_refunded?
      return false if item_count.zero?
      return false if refunds_total.zero?

      payment_state.in?(%w[void failed]) || refunds_total == total_minus_store_credits - additional_tax_total.abs
    end

    def refunds_total
      refunds.loaded? ? refunds.sum(&:amount) : refunds.sum(:amount)
    end

    # Checks if the order is partially refunded
    # @return [Boolean]
    def partially_refunded?
      return false if item_count.zero?
      return false if payment_state.in?(%w[void failed]) || refunds.empty?

      refunds_total < total_minus_store_credits - additional_tax_total.abs
    end

    # Indicates whether or not the user is allowed to proceed to checkout.
    # Currently this is implemented as a check for whether or not there is at
    # least one LineItem in the Order.  Feel free to override this logic in your
    # own application if you require additional steps before allowing a checkout.
    def checkout_allowed?
      line_items.exists?
    end

    # Does this order require a delivery (physical or digital).
    def delivery_required?
      true # true for PallasTrade, can be decorated
    end

    # Is this a free order in which case the payment step should be skipped
    def payment_required?
      total.to_f > 0.0
    end

    # If true, causes the confirmation step to happen during the checkout process
    def confirmation_required?
      PallasTrade::Config[:always_include_confirm_step] ||
        payments.valid.map(&:payment_method).compact.any?(&:confirmation_required?) ||
        # Little hacky fix for #4117
        # If this wasn't here, order would transition to address state on confirm failure
        # because there would be no valid payments any more.
        confirm?
    end

    def email_required?
      require_email
    end

    def backordered?
      shipments.any?(&:backordered?)
    end

    # Check if the shipping address is a quick checkout address
    # quick checkout addresses are incomplete as wallet providers like Apple Pay and Google Pay
    # do not provide all the address fields until the checkout is completed (confirmed) on their side
    # @return [Boolean]
    def quick_checkout?
      shipping_address.present? && shipping_address.quick_checkout?
    end

    # Check if quick checkout is available for this order
    # Either fully digital or not digital at all
    # @return [Boolean]
    def quick_checkout_available?
      payment_required? && shipments.count <= 1 && (digital? || !some_digital? || !delivery_required?)
    end

    # Check if quick checkout requires an address collection
    # If the order is digital or not delivery required, then we don't need to collect an address
    # @return [Boolean]
    def quick_checkout_require_address?
      !digital? && delivery_required?
    end

    # Returns the relevant zone (if any) to be used for taxation purposes.
    # Uses default tax zone unless there is a specific match
    def tax_zone
      @tax_zone ||= Zone.match(tax_address) || Zone.default_tax
    end

    # Returns the address for taxation based on configuration
    def tax_address
      PallasTrade::Config[:tax_using_ship_address] ? ship_address : bill_address
    end

    def updater
      @updater ||= PallasTrade.order_updater.new(self)
    end

    def update_with_updater!
      touch_last_activity!
      updater.update
    end

    # P0-3 (2026-08-18): mark the cart as active right now — drives abandoned-cart
    # detection. `update_column` avoids re-entrant callbacks/validations and the
    # timestamp churn that `touch` would cause.
    def touch_last_activity!
      return if new_record? || !has_attribute?(:last_activity_at)

      update_column(:last_activity_at, Time.current)
    end

    def merger
      @merger ||= PallasTrade::OrderMerger.new(self)
    end

    def ensure_store_presence
      PallasTrade::Deprecation.warn('PallasTrade::Order#ensure_store_presence is deprecated and will be removed in PallasTrade 6.0. ensure_store instead.')
      ensure_store
    end

    def ensure_market_presence
      self.market ||= PallasTrade::Current.market || store&.default_market
    end

    def ensure_channel_presence
      return if channel_id.present?

      self.channel = store&.default_channel
    end

    # @return [Boolean] true when this order has no registered user and its
    #   channel forbids guest checkout (see PallasTrade::Channel::Gating). Enforced by
    #   the checkout completion service and the v3 Store API so every completion
    #   path (controller, payment webhook) is covered.
    #
    #   A +prices_hidden+ channel also disallows guest completion regardless of
    #   the +guest_checkout+ flag — prices are withheld from guests, and a buyer
    #   who cannot see prices cannot meaningfully place an order. This dissolves
    #   the otherwise contradictory "prices hidden but guests may buy" config.
    def guest_checkout_disallowed?
      return false if user_id.present?
      return false if channel.blank?
      return true if channel.storefront_prices_hidden?

      !channel.resolved_guest_checkout
    end

    def allow_cancel?
      # 标准流程（P1）：pending/paid 未开始履约的订单允许取消；
      # processing 之后走退款/退货路径（与 legacy 一致）。
      if standard_flow?
        return false if canceled? || %w[processing shipped completed].include?(state)

        return true
      end

      return false if !completed? || canceled?

      shipment_state.nil? || %w{ready backorder pending canceled}.include?(shipment_state)
    end

    def all_inventory_units_returned?
      inventory_units.all?(&:returned?)
    end

    # Order lifecycle P1 (2026-08-26): parent/child semantics.
    # A non-split order is both its own parent and its own child (single_order?);
    # after a split the parent keeps the un-split line items (possibly none) and
    # each child points back via parent_id.
    def parent_order?
      children.exists?
    end

    def child_order?
      parent_id.present?
    end

    def single_order?
      !parent_order? && !child_order?
    end

    # Sibling orders under the same parent (excluding self).
    def sibling_orders
      parent ? parent.children.where.not(id: id) : PallasTrade::Order.none
    end

    # Root of the parent chain (cycle-safe).
    def root_order
      return self if parent_id.blank?

      seen = { id => true }
      cursor = parent
      while cursor&.parent_id.present? && !seen[cursor.parent_id]
        seen[cursor.parent_id] = true
        cursor = cursor.parent
      end
      cursor || self
    end

    # ---- Order lifecycle P3 (2026-08-27): 父订单聚合派生 ----
    # 父订单（有 children）的金额/支付/发货状态聚合。
    # ⚠️ 不覆写核心 total/payment_total/outstanding_balance/shipment_state——
    # 这些被 OrderUpdater/状态机/校验依赖；聚合方法仅供序列化器/查询在父订单时使用，
    # 无 children 时回退原值（零行为变化）。

    # 聚合总额：own（item+shipment+adjustment）+ Σ children.combined_total（递归）
    def combined_total
      return total unless parent_order?

      own_total = item_total + shipment_total + adjustment_total
      own_total + children.to_a.sum { |child| child.combined_total }
    end

    # 聚合已付总额：own completed payments + Σ children
    def combined_payment_total
      return payment_total unless parent_order?

      payment_total + children.to_a.sum { |child| child.combined_payment_total }
    end

    # 聚合未结余额（与 outstanding_balance 规则一致，基于聚合值）
    def combined_outstanding_balance
      return outstanding_balance unless parent_order?

      if canceled?
        -1 * combined_payment_total
      else
        combined_total - (combined_payment_total + reimbursement_paid_total)
      end
    end

    # 聚合应付金额（与 amount_due 规则一致）
    def combined_amount_due
      return amount_due unless parent_order?

      [combined_outstanding_balance - total_applied_store_credit, 0].max
    end

    # 聚合发货状态：own shipments + children 状态，套用 OrderUpdater#update_shipment_state 规则
    def combined_shipment_state
      return shipment_state unless parent_order?

      states = shipments.states.dup
      children.each { |child| states << child.combined_shipment_state if child.combined_shipment_state.present? }

      if states.include?('backorder')
        'backorder'
      elsif states.size > 1
        if states.include?('shipped')
          'partial'
        elsif states.include?('pending')
          'pending'
        else
          'ready'
        end
      else
        states.first
      end
    end

    # 聚合支付状态：基于 combined_outstanding_balance，套用 OrderUpdater#update_payment_state 规则
    def combined_payment_state
      return payment_state unless parent_order?

      if canceled? && combined_payment_total == 0
        'void'
      elsif combined_outstanding_balance > 0
        'balance_due'
      elsif combined_outstanding_balance < 0
        'credit_owed'
      else
        'paid'
      end
    end

    # 有效已付金额：有 PaymentSplit（拆单记账分摊）时用 split 推导，否则 payment_total
    def effective_payment_total
      split = payment_splits.order(:id).last
      return split.captured_amount - split.refunded_amount if split

      payment_total
    end

    # Associates the specified user with the order.
    # Delegates to {PallasTrade::CartLegacy::Associate} service.
    #
    # @param user [PallasTrade.user_class] the user to associate with the order
    # @param override_email [Boolean] whether to override the order email with the user's email
    # @return [PallasTrade::ServiceModule::Result]
    def associate_user!(user, override_email = true)
      PallasTrade.cart_associate_service.call(guest_order: self, user: user, override_email: override_email)
    end

    def disassociate_user!
      nullified_attributes = ASSOCIATED_USER_ATTRIBUTES.index_with(nil)

      update!(nullified_attributes)
    end

    def quantity_of(variant, options = {})
      line_item = find_line_item_by_variant(variant, options)
      line_item ? line_item.quantity : 0
    end

    def find_line_item_by_variant(variant, options = {})
      line_items.detect do |line_item|
        line_item.variant_id == variant.id &&
          PallasTrade.cart_compare_line_items_service.new.call(order: self, line_item: line_item, options: options).value
      end
    end

    # Creates new tax charges if there are any applicable rates. If prices already
    # include taxes then price adjustments are created instead.
    def create_tax_charge!
      PallasTrade::TaxRate.adjust(self, line_items)
      PallasTrade::TaxRate.adjust(self, shipments) if shipments.any?
    end

    def create_shipment_tax_charge!
      PallasTrade::TaxRate.adjust(self, shipments) if shipments.any?
    end

    def update_line_item_prices!
      transaction do
        line_items.reload.each(&:update_price)
        save!
      end
    end

    def outstanding_balance
      if canceled?
        -1 * payment_total
      else
        total - (payment_total + reimbursement_paid_total)
      end
    end

    def reimbursement_paid_total
      reimbursements.sum(&:paid_amount)
    end

    def outstanding_balance?
      outstanding_balance != 0
    end

    def name
      if (address = bill_address || ship_address)
        address.full_name
      end
    end

    def full_name
      @full_name ||= if user.present? && user.name.present?
                       user.full_name
                     else
                       billing_address&.full_name || email
                     end
    end

    # Returns the payment method for the order
    #
    # @return [PallasTrade::PaymentMethod] the payment method for the order
    def payment_method
      payments.valid.not_store_credits.first&.payment_method
    end

    # Returns the payment source for the order
    #
    # @return [PallasTrade::PaymentSource] the payment source for the order
    def payment_source
      payments.valid.not_store_credits.first&.source
    end

    # Returns the backordered variants for the order
    #
    # @return [Array<PallasTrade::Variant>] the backordered variants for the order
    def backordered_variants
      variants.
        where(track_inventory: true).
        joins(:stock_items, :product).
        where(PallasTrade::StockItem.table_name => { count_on_hand: ..0, backorderable: true })
    end

    def can_ship?
      complete? || resumed? || awaiting_return? || returned?
    end

    def uneditable?
      complete? || canceled? || returned?
    end

    # Finalizes an in progress order after checkout is complete.
    # Called after transition to complete state when payments will have been processed
    def finalize!
      # lock all adjustments (coupon promotions, etc.)
      all_adjustments.each(&:close)

      # update payment and shipment(s) states, and save
      updater.update_payment_state
      shipments.each do |shipment|
        shipment.update!(self)
        shipment.finalize!
      end

      updater.update_shipment_state
      self.status = 'placed'
      save!
      updater.run_hooks

      touch :completed_at

      send_order_placed_webhook

      consider_risk

      publish_order_completed_event
    end

    def fulfill!
      shipments.each { |shipment| shipment.update!(self) if shipment.persisted? }
      updater.update_shipment_state
      save!
    end

    # Helper methods for checkout steps
    def paid?
      payments.valid.completed.size == payments.valid.size && payments.valid.sum(:amount) >= total
    end

    def payment_methods
      @payment_methods ||= store.payment_methods.active.available_on_front_end.select { |pm| pm.available_for_order?(self) }
    end

    def available_payment_methods(store = nil)
      PallasTrade::Deprecation.warn('`Order#available_payment_methods` is deprecated and will be removed in PallasTrade 5.5. Use `collect_frontend_payment_methods` instead.')

      @available_payment_methods ||= collect_payment_methods(store)
    end

    def insufficient_stock_lines
      line_items.select(&:insufficient_stock?)
    end

    ##
    # Check to see if any line item variants are discontinued.
    # If so add error and restart checkout.
    def ensure_line_item_variants_are_not_discontinued
      if line_items.any? { |li| !li.variant || li.variant.discontinued? }
        restart_checkout_flow
        errors.add(:base, PallasTrade.t(:discontinued_variants_present))
        false
      else
        true
      end
    end

    def ensure_line_items_are_in_stock
      if insufficient_stock_lines.present?
        restart_checkout_flow
        errors.add(:base, PallasTrade.t(:insufficient_stock_lines_present))
        false
      else
        true
      end
    end

    def empty!
      raise PallasTrade.t(:cannot_empty_completed_order) if completed?

      result = PallasTrade.cart_empty_service.call(order: self)
      result.value
    end

    def use_all_coupon_codes
      PallasTrade::CouponCodes::CouponCodesHandler.new(order: self).use_all_codes
    end

    def has_step?(step)
      checkout_steps.include?(step)
    end

    def state_changed(name)
      state = "#{name}_state"
      if persisted?
        old_state = send("#{state}_was")
        new_state = send(state)
        unless old_state == new_state
          log_state_changes(state_name: name, old_state: old_state, new_state: new_state)
        end
      end
    end

    def log_state_changes(state_name:, old_state:, new_state:)
      state_changes.create(
        previous_state: old_state,
        next_state: new_state,
        name: state_name,
        user_id: user_id
      )
    end

    def coupon_code=(code)
      @coupon_code = begin
        code.strip.downcase
      rescue StandardError
        nil
      end
    end

    def can_add_coupon?
      PallasTrade::Promotion.order_activatable?(self)
    end

    def shipped?
      %w(partial shipped).include?(shipment_state)
    end

    def fully_shipped?
      shipments.shipped.size == shipments.size
    end

    def create_proposed_shipments
      all_adjustments.shipping.delete_all

      shipment_ids = shipments.map(&:id)
      StateChange.where(stateful_type: 'PallasTrade::Shipment', stateful_id: shipment_ids).delete_all
      ShippingRate.where(shipment_id: shipment_ids).delete_all

      shipments.delete_all

      # Inventory Units which are not associated to any shipment (unshippable)
      # and are not returned or shipped should be deleted
      inventory_units.on_hand_or_backordered.delete_all

      self.shipments = order_routing_strategy.for_allocation.map do |package|
        package.to_shipment.tap { |s| s.address_id = ship_address_id }
      end
    end

    # Resolves the routing strategy from the channel override first, then the
    # store default. Only a registered PallasTrade::OrderRouting::Strategy::Base
    # subclass is used; any other value (an unregistered/typo'd class, or a
    # strategy that was unregistered after being persisted) is logged and
    # skipped rather than raised, falling back to the default Rules strategy so
    # a misconfiguration can't take down cart display or checkout.
    #
    # @return [PallasTrade::OrderRouting::Strategy::Base]
    def order_routing_strategy
      klass = valid_order_routing_strategy_class(channel&.preferred_order_routing_strategy) ||
              valid_order_routing_strategy_class(store.preferred_order_routing_strategy) ||
              PallasTrade::OrderRouting::Strategy::Rules

      klass.new(order: self)
    end

    # Cascade for the `preferred_location` rule kind. Channel and B2B sources
    # are layered in by their respective plans.
    #
    # @return [Integer, nil]
    def inferred_preferred_stock_location_id
      preferred_stock_location_id.presence ||
        created_by&.try(:preferred_stock_location_id)
    end

    # Returns the total weight of the inventory units in the order
    # This is used to calculate the shipping rates for the order
    #
    # @return [BigDecimal] the total weight of the inventory units in the order
    def total_weight
      @total_weight ||= line_items.joins(:variant).includes(:variant).map(&:item_weight).sum
    end

    # Returns line items that have no shipping rates
    #
    # @return [Array<PallasTrade::LineItem>]
    def line_items_without_shipping_rates
      @line_items_without_shipping_rates ||= shipments.map do |shipment|
        shipment.manifest.map(&:line_item) if shipment.shipping_rates.blank?
      end.flatten.compact
    end

    # Checks if all line items cannot be shipped
    #
    # @returns Boolean
    def all_line_items_invalid?
      line_items_without_shipping_rates.size == line_items.count
    end

    def apply_free_shipping_promotions
      PallasTrade::PromotionHandler::FreeShipping.new(self).activate
      shipments.each { |shipment| PallasTrade::Adjustable::AdjustmentsUpdater.update(shipment) }
      create_shipment_tax_charge!
      update_with_updater!
    end

    # Applies user promotions when login after filling the cart
    def apply_unassigned_promotions
      ::PallasTrade::PromotionHandler::Cart.new(self).activate
    end

    # Clean shipments and make order back to address state
    #
    # At some point the might need to force the order to transition from address
    # to delivery again so that proper updated shipments are created.
    # e.g. customer goes back from payment step and changes order items
    def ensure_updated_shipments
      if shipments.any? && !completed?
        shipments.destroy_all
        update_column(:shipment_total, 0)

        # Manually publish update event since update_column bypasses callbacks
        publish_event('order.updated')

        restart_checkout_flow
      end
    end

    def restart_checkout_flow
      update_columns(
        state: 'cart',
        updated_at: Time.current
      )

      # Manually publish update event since update_columns bypasses callbacks
      publish_event('order.updated')

      next! unless line_items.empty?
    end

    def refresh_shipment_rates(shipping_method_filter = ShippingMethod::DISPLAY_ON_FRONT_END)
      shipments.map { |s| s.refresh_rates(shipping_method_filter) }
    end

    def shipping_eq_billing_address?
      bill_address == ship_address
    end

    def set_shipments_cost
      shipments.each(&:update_amounts)
      updater.update_shipment_total
      updater.update_adjustment_total
      persist_totals
    end

    def shipping_method
      # This query will select the first available shipping method from the shipments.
      # It will use subquery to first select the shipping method id from the shipments' selected_shipping_rate.
      PallasTrade::ShippingMethod.
        where(id: shipments.with_selected_shipping_method.limit(1).pluck(:shipping_method_id)).
        limit(1).
        first
    end

    def is_risky?
      !payments.risky.empty?
    end

    # Cancels the order and records the canceler.
    # Delegates to {PallasTrade::Orders::Cancel} service.
    #
    # @param user [PallasTrade.user_class, nil] the user who canceled the order
    # @param canceled_at [Time, nil] the time of cancellation (defaults to current time)
    # @return [PallasTrade::ServiceModule::Result]
    def canceled_by(user, canceled_at = nil)
      PallasTrade.order_cancel_service.call(order: self, canceler: user, canceled_at: canceled_at)
    end

    # Approves the order and records the approver.
    # Delegates to {PallasTrade::Orders::Approve} service.
    #
    # @param user [PallasTrade.user_class, nil] the user who approved the order
    # @return [PallasTrade::ServiceModule::Result]
    def approved_by(user = nil)
      PallasTrade.order_approve_service.call(order: self, approver: user)
    end

    def approved?
      !!approved_at
    end

    def can_approve?
      !approved?
    end

    def can_be_destroyed?
      PallasTrade::Deprecation.warn('PallasTrade::Order#can_be_destroyed? is deprecated and will be removed in the next major version. Use PallasTrade::Order#can_be_deleted? instead.')
      can_be_deleted?
    end

    def can_be_deleted?
      !completed? && payments.completed.empty?
    end

    def consider_risk
      considered_risky! if is_risky? && !approved?
    end

    def considered_risky!
      update_column(:considered_risky, true)

      # Manually publish update event since update_column bypasses callbacks
      publish_event('order.updated')
    end

    # Approves the order without recording an approver.
    # Delegates to {PallasTrade::Orders::Approve} service.
    #
    # @return [PallasTrade::ServiceModule::Result]
    def approve!
      PallasTrade.order_approve_service.call(order: self)
    end

    def tax_total
      included_tax_total + additional_tax_total
    end

    def quantity
      line_items.sum(:quantity)
    end

    def has_non_reimbursement_related_refunds?
      refunds.non_reimbursement.exists? ||
        payments.offset_payment.exists? # how old versions of pallastrade stored refunds
    end

    def collect_backend_payment_methods
      store.payment_methods.active.available_on_back_end.select { |pm| pm.available_for_order?(self) }
    end

    def collect_frontend_payment_methods
      store.payment_methods.active.available_on_front_end.select { |pm| pm.available_for_order?(self) }
    end

    # determines whether the inventory is fully discounted
    #
    # Returns
    # - true if inventory amount is the exact negative of inventory related adjustments
    # - false otherwise
    def fully_discounted?
      adjustment_total + line_items.map(&:final_amount).sum == 0.0
    end
    alias fully_discounted fully_discounted?

    def promo_code
      PallasTrade::CouponCode.find_by(order: self, promotion: promotions).try(:code) || promotions.pluck(:code).compact.first
    end

    # Returns the valid promotions for the order
    # @return [Array<PallasTrade::OrderPromotion>]
    def valid_promotions
      order_promotions.includes(:promotion).where(promotion_id: valid_promotion_ids).uniq(&:promotion_id)
    end

    # Returns the IDs of the valid promotions for the order
    # @return [Array<Integer>]
    def valid_promotion_ids
      all_adjustments.eligible.nonzero.promotion.promotion.eligible.nonzero.promotion.
        joins("INNER JOIN #{PallasTrade::PromotionAction.table_name} ON #{PallasTrade::PromotionAction.table_name}.id = #{PallasTrade::Adjustment.table_name}.source_id").
        pluck("#{PallasTrade::PromotionAction.table_name}.promotion_id").compact.uniq
    end

    # Returns the valid coupon promotions for the order
    # @return [Array<PallasTrade::Promotion>]
    def valid_coupon_promotions
      promotions.
        where(id: valid_promotion_ids).
        coupons
    end

    # Returns item and whole order discount amount for Order
    # without Shipment discounts (eg. Free Shipping)
    # @return [BigDecimal]
    def cart_promo_total
      all_adjustments.eligible.nonzero.promotion.
        where.not(adjustable_type: 'PallasTrade::Shipment').
        sum(:amount)
    end

    def has_free_shipping?
      shipment_adjustments.
        joins(:promotion_action).
        where(pallastrade_adjustments: { eligible: true, source_type: 'PallasTrade::PromotionAction' },
              pallastrade_promotion_actions: { type: 'PallasTrade::Promotion::Actions::FreeShipping' }).exists?
    end

    def to_csv(_store = nil)
      metafields_for_csv ||= PallasTrade::MetafieldDefinition.for_resource_type('PallasTrade::Order').order(:namespace, :key).map do |mf_def|
        metafields.find { |mf| mf.metafield_definition_id == mf_def.id }&.csv_value
      end

      csv_lines = []
      all_line_items.each_with_index do |line_item, index|
        csv_lines << PallasTrade::CSV::OrderLineItemPresenter.new(self, line_item, index, metafields_for_csv).call
      end
      csv_lines
    end

    def all_line_items
      line_items
    end

    def requires_ship_address?
      !digital?
    end

    private

    def valid_order_routing_strategy_class(klass_name)
      return if klass_name.blank?

      klass = PallasTrade.order_routing.strategies.find { |strategy| strategy.to_s == klass_name.to_s }
      return klass if klass

      Rails.logger.warn(
        "[PallasTrade] Ignoring unregistered order routing strategy #{klass_name.inspect} " \
        "for order #{number.inspect}; falling back to the default strategy."
      )
      nil
    end

    def link_by_email
      self.email = user.email if user
    end

    # Determine if email is required (we don't want validation errors before we hit the checkout)
    # we need to add delivery to the list for quick checkouts
    def require_email
      true unless new_record? || ['cart', 'address', 'delivery'].include?(state)
    end

    def ensure_line_items_present
      unless line_items.present?
        errors.add(:base, PallasTrade.t(:there_are_no_items_for_this_order)) && (return false)
      end
    end

    def ensure_available_shipping_rates
      if shipments.empty? || line_items_without_shipping_rates.present?
        # After this point, order redirects back to 'address' state and asks user to pick a proper address
        # Therefore, shipments are not necessary at this point.
        shipments.destroy_all

        if line_items_without_shipping_rates.present?
          errors.add(:base, PallasTrade.t(:products_cannot_be_shipped, product_names: line_items_without_shipping_rates.map(&:name).to_sentence))
          self.warnings |= line_items_without_shipping_rates.map do |line_item|
            {
              code: 'delivery_unavailable',
              message: PallasTrade.t('cart_line_item.delivery_unavailable', li_name: line_item.name),
              line_item_id: line_item.prefixed_id,
              variant_id: line_item.variant&.prefixed_id
            }
          end
        else
          errors.add(:base, PallasTrade.t(:items_cannot_be_shipped))
          self.warnings |= [{ code: 'delivery_unavailable', message: PallasTrade.t(:items_cannot_be_shipped) }]
        end

        false
      end
    end

    def after_cancel
      update_column(:status, 'canceled')

      shipments.each(&:cancel!)

      # payments fully covered by gift card won't be refunded
      # we want to only void the payment
      if gift_card.present? && covered_by_store_credit?
        payments.completed.store_credits.each(&:void!)
      else
        payments.completed.each(&:cancel!)
        payments.incomplete.not_store_credits.each(&:void_transaction!)
        payments.store_credits.pending.each(&:void!)
      end

      update_with_updater!
      send_order_canceled_webhook
    end

    def after_resume
      update_column(:status, 'placed')

      shipments.each(&:resume!)
      consider_risk
      send_order_resumed_webhook
      publish_order_resumed_event
    end

    def use_billing?
      use_billing.in?([true, 'true', '1'])
    end

    def use_shipping?
      use_shipping.in?([true, 'true', '1'])
    end

    def ensure_currency_presence
      self.currency ||= store&.default_currency
    end

    # Sets the locale from PallasTrade::Current.locale when not already set.
    # Called as a before_validation callback, mirroring ensure_currency_presence.
    def ensure_locale_presence
      self.locale ||= PallasTrade::Current.locale
    end

    def currency_must_be_supported_by_store
      return if currency.blank? || store.blank?

      supported_codes = store.supported_currencies_list.map(&:iso_code)
      unless supported_codes.include?(currency)
        errors.add(:currency, PallasTrade.t(:currency_not_supported_by_store))
      end
    end

    # Validates that the order's locale is within the store's supported locales.
    # Mirrors currency_must_be_supported_by_store.
    def locale_must_be_supported_by_store
      return if locale.blank? || store.blank?

      unless store.supported_locales_list.include?(locale)
        errors.add(:locale, PallasTrade.t(:locale_not_supported_by_store))
      end
    end

    # When currency changes, auto-resolve the matching market.
    # Only applies when the store has markets configured.
    def resolve_market_from_currency
      return unless store_has_markets?
      return if market&.currency == currency

      resolved = store.markets.find_by(currency: currency)
      self.market = resolved if resolved
    end

    def collect_payment_methods
      PallasTrade::Deprecation.warn('`Order#collect_payment_methods` is deprecated and will be removed in PallasTrade 5.5. Use `collect_frontend_payment_methods` instead.')

      store.payment_methods.available_on_front_end.select { |pm| pm.available_for_order?(self) }
    end

    def credit_card_nil_payment?(attributes)
      payments.store_credits.present? && attributes[:amount].to_f.zero?
    end

    def recalculate_store_credit_payment
      updater.update_adjustment_total if using_store_credit?

      if gift_card.present?
        recalculate_gift_card
      elsif using_store_credit?
        PallasTrade.checkout_add_store_credit_service.call(order: self)
      end
    end

    def publish_order_completed_event
      publish_event('order.completed', event_payload.merge(notify_customer: notify_customer))
    end

    def publish_order_resumed_event
      publish_event('order.resumed')
    end
  end
end
