# frozen_string_literal: true

# PALLAS-CUSTOM: D13 切片4（PRD-20260916-payments-d13d-fx-snapshot；业务方案 §70.4）——
# 汇率行：**多源 + 优先级 + 生效窗口**。只用于结算差核算，不参与定价、不改资金。
#
# 来源默认优先级（可显式覆写 `priority`）：provider 30 > third_party 20 > manual 10。
# 解析排序（唯一口径，`by_priority`）：`priority DESC` → 本店优先于全局 → `effective_from DESC` → `id DESC`。
# 幂等：`identity_key = SHA256("rate:<store|global>:<base>:<quote>:<source>:<effective_from_iso>")`。
module PallasTrade
  class CurrencyRate < PallasTrade.base_class
    SOURCES = %w[manual provider third_party].freeze
    STATUSES = %w[active revoked].freeze
    DEFAULT_PRIORITIES = { 'manual' => 10, 'third_party' => 20, 'provider' => 30 }.freeze
    RATE_SCALE = 10
    MAX_NOTE_LENGTH = 500

    belongs_to :store, class_name: 'PallasTrade::Store', optional: true

    validates :base_currency, :quote_currency, :rate, :identity_key, presence: true
    validates :source, inclusion: { in: SOURCES }
    validates :status, inclusion: { in: STATUSES }
    validates :rate, numericality: { greater_than: 0 }
    validates :priority, numericality: { greater_than_or_equal_to: 0, only_integer: true }
    validates :note, length: { maximum: MAX_NOTE_LENGTH }
    validates :identity_key, uniqueness: true
    validate :currencies_must_differ
    validate :currencies_must_be_known

    before_validation :normalize_attributes

    scope :recent_first, -> { order(created_at: :desc, id: :desc) }
    scope :active, -> { where(status: 'active') }
    scope :revoked, -> { where(status: 'revoked') }
    # 「生效」唯一口径：未撤销 + 在生效窗口内
    scope :effective_at, lambda { |at = Time.current|
      where('pallastrade_currency_rates.effective_from IS NULL OR pallastrade_currency_rates.effective_from <= ?', at)
        .where('pallastrade_currency_rates.effective_until IS NULL OR pallastrade_currency_rates.effective_until >= ?', at)
    }
    # 店铺隔离硬边界：全局 + 本店
    scope :for_store, ->(store) { where(store_id: [nil, store&.id].uniq) }
    scope :for_pair, lambda { |base, quote|
      where(base_currency: base.to_s.upcase, quote_currency: quote.to_s.upcase)
    }
    # 解析顺序（唯一口径：Resolver 与后台展示共用）
    scope :by_priority, lambda {
      order(Arel.sql(<<~SQL.squish))
        priority DESC,
        (CASE WHEN store_id IS NULL THEN 0 ELSE 1 END) DESC,
        effective_from DESC NULLS LAST,
        id DESC
      SQL
    }

    # 后台筛选（唯一口径：列表与计数共用）
    scope :filter_by, lambda { |store: nil, base_currency: nil, quote_currency: nil, source: nil, status_filter: nil|
      result = store.present? ? for_store(store) : all
      result = result.where(base_currency: base_currency.to_s.upcase) if base_currency.present?
      result = result.where(quote_currency: quote_currency.to_s.upcase) if quote_currency.present?
      result = result.where(source: source) if source.present?

      case status_filter.to_s
      when 'active' then result.active
      when 'revoked' then result.revoked
      else result
      end
    }

    class << self
      # @return [Integer]
      def default_priority_for(source)
        DEFAULT_PRIORITIES[source.to_s] || 10
      end

      # 幂等身份键（唯一口径：维护 / 解析 / 导入共用）
      # @return [String] 64 位十六进制
      def identity_key_for(base_currency:, quote_currency:, source:, effective_from: nil, store: nil)
        scope = store.present? ? "store:#{store.is_a?(Integer) ? store : store.id}" : 'global'
        stamp = effective_from.present? ? Time.zone.parse(effective_from.to_s).utc.iso8601 : 'always'
        ::Digest::SHA256.hexdigest(
          "rate:#{scope}:#{base_currency.to_s.upcase}:#{quote_currency.to_s.upcase}:#{source}:#{stamp}"
        )
      end
    end

    def revoked?
      status == 'revoked'
    end

    # 软撤销：保留历史行（历史快照可复算）
    def revoke!(actor: nil, at: Time.current)
      update!(status: 'revoked', revoked_at: at, metadata: metadata.merge('revoked_by' => actor_label(actor)))
    end

    # 加点后的实际汇率（四舍五入到 10 位小数）
    # @param up_charge_percent [Numeric]
    # @return [BigDecimal]
    def effective_rate_for(up_charge_percent = 0)
      markup = up_charge_percent.to_d
      (rate.to_d * (1 + markup / 100)).round(RATE_SCALE)
    end

    private

    def normalize_attributes
      self.base_currency = base_currency.to_s.strip.upcase.presence
      self.quote_currency = quote_currency.to_s.strip.upcase.presence
      self.source = source.to_s.strip.downcase.presence || 'manual'
      self.status = status.to_s.strip.downcase.presence || 'active'
      self.note = note.to_s.strip.presence
      self.effective_from = normalize_time(effective_from)
      self.effective_until = normalize_time(effective_until)
      self.priority = self.class.default_priority_for(source) if priority.nil?
    end

    def normalize_time(value)
      return nil if value.blank?

      value.is_a?(String) ? (Time.zone.parse(value) rescue nil) : value
    end

    def currencies_must_differ
      return if base_currency.blank? || quote_currency.blank?
      return unless base_currency == quote_currency

      errors.add(:quote_currency, :invalid)
    end

    def currencies_must_be_known
      [base_currency, quote_currency].each do |code|
        next if code.blank?
        next if defined?(::Money::Currency) && ::Money::Currency.find(code).present?

        errors.add(:base_currency, :invalid)
        break
      end
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
