# frozen_string_literal: true

module PallasTrade
  # 订单流程标准电商改造 P1（2026-08-30）：购物车与订单分表。
  #
  # Cart 是**临时会话**（pallastrade_carts 表），与 Order（pallastrade_orders 表）物理分离：
  # - 购物车承载加购/勾选/删除/收件信息/物流选择/金额预览，不承载支付/履约/逆向
  # - 提交订单（Carts::Submit）从 Cart 快照创建 Order（state=pending）后 Cart → converted
  # - 状态机极简：active → converted / abandoned
  #
  # 注意：Spree 遗留的购物车服务已重命名为 `PallasTrade::CartLegacy::*`（AddItem/Recalculate
  # 等，操作 Order 而非本模型），待 P4 清理。新流程请使用 `PallasTrade::Carts::*`（复数）
  # 服务命名空间。
  class Cart < PallasTrade.base_class
    has_prefix_id :cart  # cart_xxx（与 Order 的 or_xxx 前缀区分，API 解析无歧义）

    include PallasTrade::SingleStoreResource
    include PallasTrade::Metadata
    include PallasTrade::MemoizedData

    self.event_prefix = 'cart'

    publishes_lifecycle_events

    STATUSES = %w[active converted abandoned].freeze
    MEMOIZED_METHODS = %w[].freeze

    belongs_to :store, class_name: 'PallasTrade::Store'
    belongs_to :user, class_name: "::#{PallasTrade.user_class}", optional: true
    belongs_to :shipping_address, class_name: 'PallasTrade::Address', optional: true
    belongs_to :billing_address, class_name: 'PallasTrade::Address', optional: true
    belongs_to :shipping_method, class_name: 'PallasTrade::ShippingMethod', optional: true

    has_many :cart_items, class_name: 'PallasTrade::CartItem', inverse_of: :cart, dependent: :destroy
    has_many :variants, through: :cart_items
    has_many :orders, class_name: 'PallasTrade::Order', inverse_of: :cart

    has_secure_token :token, length: 35

    validates :store, :currency, presence: true
    validates :status, inclusion: { in: STATUSES }

    extend PallasTrade::DisplayMoney
    money_methods :item_total

    state_machine :status, initial: :active do
      state :active
      state :converted
      state :abandoned

      event :convert do
        transition active: :converted
      end

      event :abandon do
        transition active: :abandoned
      end

      after_transition to: :converted, do: :record_conversion
      after_transition to: :abandoned, do: :publish_abandoned_event
    end

    scope :active,     -> { where(status: 'active') }
    scope :converted,  -> { where(status: 'converted') }
    scope :abandoned,  -> { where(status: 'abandoned') }

    delegate :name, to: :store, prefix: true, allow_nil: true

    # 转订单后购物车不可再改；记录转换时间戳。
    def record_conversion
      update_column(:converted_at, Time.current)
      publish_converted_event
    end

    # 本次结算范围：勾选商品行。
    def selected_items
      cart_items.selected
    end

    def item_count
      cart_items.sum(:quantity)
    end

    # 商品小计（variant 当前价格 × 数量，仅勾选项）。
    # 运费/税费不在 Cart 上计算——提交订单时由 Carts::Submit 在 Order 上
    # 通过完整履约/税务管线计算权威金额（见 PRD §6.2.3）。
    def item_total
      selected_items.to_a.sum(&:amount)
    end

    # 标记最近活跃（弃购检测用），与 Order#touch_last_activity! 语义一致。
    def touch_last_activity!
      return if new_record? || !has_attribute?(:last_activity_at)

      update_column(:last_activity_at, Time.current)
    end

    private

    # 事件 payload 用最小回退（id/timestamps）——约定解析会命中 legacy CartSerializer
    # （Order 同表专属，调用 cart.market 等会 NoMethodError）。有真实消费者后再引入
    # 专用序列化器（避免 core→api 反向依赖）。
    def event_serializer_class
      nil
    end

    def publish_converted_event
      publish_event('cart.converted')
    end

    def publish_abandoned_event
      publish_event('cart.abandoned')
    end
  end
end
