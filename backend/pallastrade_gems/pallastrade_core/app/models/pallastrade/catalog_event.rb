# frozen_string_literal: true

# PALLAS-CUSTOM: A3 Step 1（PRD-20260917-catalog-product-events；业务方案 §14 / §16）——
# 商品事件回流：曝光 / 点击 / 加购 / 搜索落到**自有库**，支撑 `Related Product CTR`
# 与后续推荐算法的数据积累。
#
# ⚠️ **旁路表（side channel）**：任何业务路径（库存 / 价格 / 订单 / 结账）**不得读取**
# 本表做判定。整表可随时清空而不影响业务（AC-009 以此立据）。
#
# ⚠️ **零 PII**：不存 IP / User-Agent / 邮箱 / 客户 ID / 原始访客标识；
# `session_hash` 是服务端 HMAC 摘要（跨店不可关联、不可逆）。
class PallasTrade::CatalogEvent < PallasTrade.base_class
  include PallasTrade::SingleStoreResource

  # 与 `PallasTrade.analytics.events` 词表对齐的**严格白名单**（未知名称一律拒收）。
  #
  # `impression` / `click` 是前台新增语义（GA4 的 add_to_cart 等已存在，这里补齐
  # 「推荐位曝光 / 点击」——`Related Product CTR` 的分母与分子）。
  EVENT_NAMES = %w[impression click product_added product_searched].freeze

  # CTR 只由这两个事件构成
  CTR_EVENT_NAMES = %w[impression click].freeze

  # 保留窗口（天）：事件表是高频追加表，必须有界。清理作业见 `CatalogEvents::Prune`。
  RETENTION_DAYS = 90

  # 单请求上限。取值需显著大于「一次页面浏览产生的事件数」，以便前台按页聚合、
  # 减少 flush 次数（见下方 quota 说明）。
  MAX_BATCH_SIZE = 100

  belongs_to :store, class_name: 'PallasTrade::Store'
  belongs_to :product, class_name: 'PallasTrade::Product', optional: true
  belongs_to :variant, class_name: 'PallasTrade::Variant', optional: true

  validates :event_id, :event_name, :session_hash, :occurred_at, presence: true
  validates :event_name, inclusion: { in: EVENT_NAMES }

  scope :occurred_between, ->(from, to = Time.current) { where(occurred_at: from..to) }
  scope :for_list, ->(list_id) { where(list_id: list_id) }

  class << self
    # 访客标识 → 不可逆摘要。
    #
    # 原始值**只在请求内存中存在**，绝不落库；盐按店铺派生，因此同一访客在
    # 不同店铺得到不同摘要（跨店不可关联）。
    #
    # @param visitor_id [String, nil] 请求中携带的访客标识
    # @param store [PallasTrade::Store]
    # @return [String, nil] 32 位十六进制摘要；入参为空时返回 nil
    def digest_visitor(visitor_id, store)
      return nil if visitor_id.blank? || store.blank?

      OpenSSL::HMAC.hexdigest('SHA256', digest_secret(store), visitor_id.to_s)[0, 32]
    end

    # 按推荐位聚合曝光 / 点击 / CTR。
    #
    # ⚠️ 分母为 0 时 `ctr` 返回 **nil**（不返回 0、不返回 1）——沿用 catalog health
    # 「不编造比率」铁律（FR-015）。
    #
    # @param store [PallasTrade::Store]
    # @param from [Time] 窗口起点
    # @param to [Time] 窗口终点
    # @param list_id [String, nil] 可选：只看某个推荐位
    # @return [Array<Hash>] `{ list_id:, impressions:, clicks:, ctr: }`
    def list_metrics(store, from: RETENTION_DAYS.days.ago, to: Time.current, list_id: nil)
      scope = for_store(store).occurred_between(from, to).where(event_name: CTR_EVENT_NAMES)
      scope = scope.for_list(list_id) if list_id.present?

      counts = scope.group(:list_id, :event_name).count

      counts.keys.map(&:first).uniq.sort_by(&:to_s).map do |id|
        impressions = counts[[id, 'impression']].to_i
        clicks = counts[[id, 'click']].to_i

        {
          list_id: id,
          impressions: impressions,
          clicks: clicks,
          ctr: impressions.zero? ? nil : clicks.to_f / impressions
        }
      end
    end

    # 按商品聚合（曝光 / 加购）。
    #
    # @return [Hash{Integer=>Hash}] product_id → `{ impressions:, product_added: }`
    def product_metrics(store, from: RETENTION_DAYS.days.ago, to: Time.current)
      scope = for_store(store).occurred_between(from, to)
                             .where(event_name: %w[impression product_added])
                             .where.not(product_id: nil)

      counts = scope.group(:product_id, :event_name).count

      counts.each_with_object({}) do |((product_id, event_name), count), acc|
        acc[product_id] ||= { impressions: 0, product_added: 0 }

        # 显式映射：`event_name` 是单数（`impression`），键是复数（`impressions`），
        # 直接 `to_sym` 会静默写进一个没人读的键。
        case event_name.to_s
        when 'impression' then acc[product_id][:impressions] = count
        when 'product_added' then acc[product_id][:product_added] = count
        end
      end
    end

    private

    # 盐 = 店铺 + 应用密钥。不额外存储盐（无新密钥管理面）。
    def digest_secret(store)
      base = Rails.application.secret_key_base.presence || 'pallastrade-catalog-events'
      "catalog_events:#{store.id}:#{base}"
    end
  end
end
