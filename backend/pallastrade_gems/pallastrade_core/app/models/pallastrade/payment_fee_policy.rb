# frozen_string_literal: true

# PALLAS-CUSTOM: D13 切片3（PRD-20260916-payments-d13c-fee-cost-report；业务方案 §70.3 费率模型 / §74.1 表名规划）——
# 支付费率策略（rate card）行：**只读核算的输入**，不参与资金流、不阻断支付、不调 provider。
#
# 解析优先级（唯一口径，供 `Payments::Fees::Resolver` 使用）：
#   `method`(4) > `provider`(3) > `store`(2) > `global`(1)，同优先级取 `effective_from` 更晚者，再取 id 更大者。
#
# 生效（`active` scope 是「生效」的唯一口径）：未撤销 + （`effective_from` 为空或已到）+（`effective_until` 为空或未过）。
# 店铺隔离硬边界：全局策略（`store_id IS NULL`）+ 本店策略。
module PallasTrade
  class PaymentFeePolicy < PallasTrade.base_class
    SCOPE_TYPES = %w[global store provider method].freeze
    STATUSES = %w[active revoked].freeze
    # 解析优先级（数字越大越优先）
    SCOPE_PRIORITIES = { 'method' => 4, 'provider' => 3, 'store' => 2, 'global' => 1 }.freeze
    PERCENT_COLUMNS = %w[percent_fee cross_border_percent currency_conversion_percent platform_percent].freeze
    AMOUNT_COLUMNS = %w[fixed_fee cross_border_fixed min_fee max_fee].freeze
    MAX_PERCENT = 100
    MAX_NAME_LENGTH = 200
    # 卡片类型（与既有 cc_type 口径一致的常见取值；空 = 全部）
    CARD_TYPES = %w[visa master discover american_express jcb diners_club unionpay].freeze

    belongs_to :store, class_name: 'PallasTrade::Store', optional: true
    belongs_to :created_by, polymorphic: true, optional: true

    validates :name, presence: true, length: { maximum: MAX_NAME_LENGTH }
    validates :scope_type, inclusion: { in: SCOPE_TYPES }
    validates :status, inclusion: { in: STATUSES }
    validate :scope_id_consistent_with_scope_type
    validate :percentages_within_bounds
    validate :amounts_non_negative
    validate :min_not_greater_than_max

    before_validation :normalize_attributes

    scope :recent_first, -> { order(created_at: :desc, id: :desc) }
    scope :revoked, -> { where(status: 'revoked') }
    # 「生效」唯一口径：未撤销 + 在生效窗口内
    scope :active, -> { where(status: 'active') }
    scope :effective_at, lambda { |at = Time.current|
      where('pallastrade_payment_fee_policies.effective_from IS NULL OR pallastrade_payment_fee_policies.effective_from <= ?', at)
        .where('pallastrade_payment_fee_policies.effective_until IS NULL OR pallastrade_payment_fee_policies.effective_until >= ?', at)
    }
    # 店铺隔离硬边界：全局 + 本店
    scope :for_store, ->(store) { where(store_id: [nil, store&.id].uniq) }
    # 解析顺序（唯一口径：Resolver 与页面展示共用同一 SQL 排序）
    scope :by_priority, lambda {
      order(Arel.sql(<<~SQL.squish))
        CASE scope_type
          WHEN 'method' THEN 4
          WHEN 'provider' THEN 3
          WHEN 'store' THEN 2
          ELSE 1
        END DESC,
        effective_from DESC NULLS LAST,
        id DESC
      SQL
    }

    # 后台列表筛选（唯一口径：列表与计数共用）
    scope :filter_by, lambda { |store: nil, scope_type: nil, status_filter: nil, currency: nil|
      result = store.present? ? for_store(store) : all
      result = result.where(scope_type: scope_type) if scope_type.present?
      result = result.where(currency: currency.to_s.upcase) if currency.present?

      case status_filter.to_s
      when 'active' then result.active
      when 'revoked' then result.revoked
      else result
      end
    }

    class << self
      # @return [Integer]
      def priority_for(scope_type)
        SCOPE_PRIORITIES[scope_type.to_s] || 0
      end
    end

    def global?
      scope_type == 'global'
    end

    def revoked?
      status == 'revoked'
    end

    # 撤销（软撤销：保留历史行，供审计与历史报表复算）
    def revoke!(actor: nil, at: Time.current)
      update!(status: 'revoked', revoked_at: at, metadata: metadata.merge('revoked_by' => actor_label(actor)))
    end

    def priority
      self.class.priority_for(scope_type)
    end

    def percent_total
      PERCENT_COLUMNS.sum { |column| public_send(column).to_d }
    end

    # 条件匹配（币种 / 卡类型 / 地区）。**不猜**：策略声明了条件但上下文无法判定时视为不匹配并留痕。
    # @param context [Hash] currency / card_type / region / payment_method_id / method_key
    # @return [Array(Boolean, Array<String>)] [是否匹配, 信号]
    def matches_context?(context)
      context = (context || {}).symbolize_keys
      signals = []

      unless scope_matches?(context)
        signals << 'scope_mismatch'
        return [false, signals]
      end

      if currency.present? && currency != context[:currency].to_s.upcase
        signals << 'currency_mismatch'
        return [false, signals]
      end

      if card_type.present?
        if context[:card_type].blank?
          signals << 'card_type_undetermined'
          return [false, signals]
        end

        if card_type != context[:card_type].to_s.downcase
          signals << 'card_type_mismatch'
          return [false, signals]
        end
      end

      if region.present?
        if context[:region].blank?
          signals << 'region_undetermined'
          return [false, signals]
        end

        if region != context[:region].to_s.upcase
          signals << 'region_mismatch'
          return [false, signals]
        end
      end

      [true, signals]
    end

    # 人类可读的费率描述（**不依赖翻译**：核心模型不引 admin 命名空间；页面按需本地化数字格式）
    def description
      parts = []
      parts << "#{percent_fee.to_f}%" if percent_fee.to_d.positive?
      parts << "+#{fixed_fee.to_f}" if fixed_fee.to_d.positive?
      parts << "platform #{platform_percent.to_f}%" if platform_percent.to_d.positive?
      parts << "cross-border #{cross_border_percent.to_f}%" if cross_border_percent.to_d.positive?
      parts << "cross-border +#{cross_border_fixed.to_f}" if cross_border_fixed.to_d.positive?
      parts << "fx #{currency_conversion_percent.to_f}%" if currency_conversion_percent.to_d.positive?
      parts.join(' + ')
    end

    private

    def scope_matches?(context)
      case scope_type
      when 'global' then true
      when 'store' then store_id.present? && store_id == context[:store_id]
      when 'provider' then scope_id.present? && scope_id == context[:payment_method_id].to_s
      when 'method' then scope_id.present? && scope_id == context[:method_key].to_s
      else false
      end
    end

    def normalize_attributes
      self.name = name.to_s.strip.presence
      self.scope_type = scope_type.to_s.strip.downcase.presence || 'global'
      self.scope_id = scope_id.to_s.strip.presence
      self.scope_id = nil if %w[global store].include?(scope_type)
      self.currency = currency.to_s.strip.presence&.upcase
      self.card_type = card_type.to_s.strip.presence&.downcase
      self.region = region.to_s.strip.presence&.upcase
      self.home_country = home_country.to_s.strip.presence&.upcase
      self.settlement_currency = settlement_currency.to_s.strip.presence&.upcase
      self.status = status.to_s.strip.downcase.presence || 'active'
      self.percent_fee = percent_fee.to_d if percent_fee.present?
      self.platform_percent = platform_percent.to_d if platform_percent.present?
      self.cross_border_percent = cross_border_percent.to_d if cross_border_percent.present?
      self.currency_conversion_percent = currency_conversion_percent.to_d if currency_conversion_percent.present?
      self.fixed_fee = fixed_fee.to_d if fixed_fee.present?
      self.cross_border_fixed = cross_border_fixed.to_d if cross_border_fixed.present?
    end

    # scope_id 与 scope_type 的一致性：provider/method 必填；global/store 一律归一为 NULL（见 normalize_attributes）
    def scope_id_consistent_with_scope_type
      return unless %w[provider method].include?(scope_type)

      errors.add(:scope_id, :blank) if scope_id.blank?
    end

    def percentages_within_bounds
      PERCENT_COLUMNS.each do |column|
        value = public_send(column)
        next if value.nil?

        decimal = value.to_d
        errors.add(column, :greater_than_or_equal_to, count: 0) if decimal.negative?
        errors.add(column, :less_than_or_equal_to, count: MAX_PERCENT) if decimal > MAX_PERCENT
      end
    end

    def amounts_non_negative
      AMOUNT_COLUMNS.each do |column|
        value = public_send(column)
        next if value.nil?

        errors.add(column, :greater_than_or_equal_to, count: 0) if value.to_d.negative?
      end
    end

    def min_not_greater_than_max
      return if min_fee.blank? || max_fee.blank?
      return unless min_fee.to_d > max_fee.to_d

      errors.add(:min_fee, :greater_than, count: max_fee.to_d.to_f)
    end

    def actor_label(actor)
      case actor
      when Hash then actor[:label].presence || actor[:id].to_s
      when nil then nil
      else actor.respond_to?(:id) ? actor.id.to_s : actor.to_s
      end
    end
  end
end
