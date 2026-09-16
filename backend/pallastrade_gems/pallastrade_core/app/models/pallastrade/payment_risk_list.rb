# frozen_string_literal: true

# PALLAS-CUSTOM: D15 切片1（PRD-20260916-payments-d15-risk-lists；业务方案 §72.3 名单 / §74.1 表名规划）——
# 风控名单行：`list_type`（denylist / allowlist）× `subject_type`（主体类型）× **归一化值**。
#
# 幂等：唯一键 `(list_type, subject_type, value_hash)`；`value_hash = SHA256("type:subject:归一化值")`。
# 失效两条路：`status = 'revoked'`（人工撤销，**保留历史**）或 `expires_at <= now`（到期）。
#   `active` scope 是「生效」的唯一口径（页面计数 / 评估共用）。
#
# 铁律：名单**只描述事实**，本身不阻断任何流程（决策由 `Risk::Assess` 产出，处置属后续切片）。
module PallasTrade
  class PaymentRiskList < PallasTrade.base_class
    LIST_TYPES = %w[denylist allowlist].freeze
    SUBJECT_TYPES = %w[card_fingerprint bin email ip device customer address country].freeze
    STATUSES = %w[active revoked].freeze
    # 评估时可从订单**本地解析**的主体（其余主体类型本切片只支持人工维护，接线留后续切片）
    RESOLVABLE_SUBJECT_TYPES = %w[email ip customer country].freeze
    MAX_VALUE_LENGTH = 500

    belongs_to :store, class_name: 'PallasTrade::Store', optional: true
    belongs_to :added_by, polymorphic: true, optional: true

    validates :list_type, :subject_type, :value, :value_hash, presence: true
    validates :list_type, inclusion: { in: LIST_TYPES }
    validates :subject_type, inclusion: { in: SUBJECT_TYPES }
    validates :status, inclusion: { in: STATUSES }
    validates :value, length: { maximum: MAX_VALUE_LENGTH }
    validates :value_hash, uniqueness: { scope: %i[list_type subject_type] }

    before_validation :assign_identity

    scope :recent_first, -> { order(created_at: :desc, id: :desc) }
    scope :denylist, -> { where(list_type: 'denylist') }
    scope :allowlist, -> { where(list_type: 'allowlist') }
    # 「生效」唯一口径：未撤销 且（无到期 或 未到期）
    scope :active, lambda {
      where(status: 'active').where(
        'pallastrade_payment_risk_lists.expires_at IS NULL OR pallastrade_payment_risk_lists.expires_at > ?',
        Time.current
      )
    }
    scope :expired, lambda {
      where(status: 'active').where(
        'pallastrade_payment_risk_lists.expires_at IS NOT NULL AND pallastrade_payment_risk_lists.expires_at <= ?',
        Time.current
      )
    }
    scope :revoked, -> { where(status: 'revoked') }
    # 店铺隔离硬边界：全局名单（store_id IS NULL）+ 本店名单
    scope :for_store, ->(store) { where(store_id: [nil, store&.id].uniq) }

    # 后台工作台筛选（唯一口径：列表与计数共用）
    # @param scope_filter [String, nil] all / active / expired / revoked（默认 all）
    scope :filter_by, lambda { |store: nil, list_type: nil, subject_type: nil, scope_filter: nil|
      result = store.present? ? for_store(store) : all
      result = result.where(list_type: list_type) if list_type.present?
      result = result.where(subject_type: subject_type) if subject_type.present?

      case scope_filter.to_s
      when 'active' then result.active
      when 'expired' then result.expired
      when 'revoked' then result.revoked
      else result
      end
    }

    class << self
      # 归一化（唯一口径：维护 / 导入 / 评估共用；不同写法不产生第二行）
      # @param subject_type [String]
      # @param value [Object]
      # @return [String]
      def normalize_value(subject_type, value)
        raw = value.to_s.strip
        return '' if raw.blank?

        case subject_type.to_s
        when 'email', 'device' then raw.downcase
        when 'country' then raw.upcase
        when 'bin' then raw.gsub(/[^0-9]/, '')
        when 'card_fingerprint' then raw.gsub(/\s/, '').downcase
        when 'address' then raw.downcase.gsub(/\s+/, ' ')
        when 'ip' then raw.gsub(/\s/, '').downcase
        else raw
        end
      end

      # @return [String] 64 位十六进制
      def value_hash_for(list_type:, subject_type:, value:)
        normalized = normalize_value(subject_type, value)
        ::Digest::SHA256.hexdigest("#{list_type}:#{subject_type}:#{normalized}")
      end
    end

    # 到期（`expires_at` 已过）—— 与 `status` 正交
    def expired?
      expires_at.present? && expires_at <= Time.current
    end

    # 生效 = 未撤销 + 未到期（与 `active` scope 同义，供单行判断）
    def effective?
      status == 'active' && !expired?
    end

    def denylist?
      list_type == 'denylist'
    end

    def allowlist?
      list_type == 'allowlist'
    end

    # 展示脱敏（页面 / 审计一律用它；CSV 导出保留原值）
    def masked_value
      case subject_type
      when 'email' then mask_email
      when 'ip' then mask_ip
      when 'bin' then mask_head(value, 4)
      when 'card_fingerprint' then mask_edge(value, 4)
      when 'customer', 'device' then mask_head(value, 2)
      else value
      end
    end

    private

    def assign_identity
      self.list_type = list_type.to_s
      self.subject_type = subject_type.to_s
      return if value.blank?

      self.value = self.class.normalize_value(subject_type, value)
      self.value_hash = self.class.value_hash_for(list_type: list_type, subject_type: subject_type, value: value)
    end

    def mask_email
      local, _at, domain = value.to_s.partition('@')
      return mask_head(value, 1) if domain.blank? || local.blank?

      "#{local[0, 1]}***@#{domain}"
    end

    def mask_ip
      parts = value.to_s.split('.')
      return mask_head(value, 2) if parts.size < 4

      "#{parts[0]}.#{parts[1]}.*.*"
    end

    # 只露头部（BIN / 客户 / 设备：尾部不重要，多露反而泄露）
    def mask_head(raw, keep)
      text = raw.to_s
      return '***' if text.length <= keep

      "#{text[0, keep]}***"
    end

    # 首尾各露 keep 位（卡指纹：需要首尾比对才能人眼核对）
    def mask_edge(raw, keep)
      text = raw.to_s
      return '***' if text.length <= (keep + 1)

      "#{text[0, keep]}***#{text[-keep, keep]}"
    end
  end
end
