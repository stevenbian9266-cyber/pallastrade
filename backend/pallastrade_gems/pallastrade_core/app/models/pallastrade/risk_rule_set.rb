# frozen_string_literal: true

# PALLAS-CUSTOM: D15 切片2（PRD-20260917-payments-d15b-risk-rules；业务方案 §72.2）——
# 风控**规则集**：规则的稳定容器，持有「生效版本 + 金丝雀版本 + 灰度百分比」。
#
# 作用域：`store_id` 可空 = 全局（对所有店铺生效）；非空 = 店铺（更具体，**优先**）。
# 与名单（D15 切片1）同口径（NULL = 全局），但优先级相反：名单取「全局 ∪ 本店」的并集，
# 规则集取「同 code 本店覆盖全局」——规则是覆盖语义，不是叠加语义。
#
# 铁律：规则集/版本**只描述规则**，不阻断任何流程（决策由 `Risk::Rules::Evaluate` 产出，
# 处置沿用既有 `Risk::Assess` → 留痕 → 人工复核路径）。
module PallasTrade
  class RiskRuleSet < PallasTrade.base_class
    STATUSES = %w[active inactive].freeze
    CODE_FORMAT = /\A[a-z0-9][a-z0-9_-]*\z/
    MAX_CANARY_PERCENT = 100
    MIN_CANARY_PERCENT = 0

    belongs_to :store, class_name: 'PallasTrade::Store', optional: true
    belongs_to :active_version, class_name: 'PallasTrade::RiskRuleVersion', optional: true
    belongs_to :canary_version, class_name: 'PallasTrade::RiskRuleVersion', optional: true
    has_many :versions, class_name: 'PallasTrade::RiskRuleVersion', dependent: :destroy, inverse_of: :rule_set

    validates :code, :name, presence: true
    validates :code, format: { with: CODE_FORMAT, message: 'must be lowercase letters, digits, dash or underscore' }
    validates :status, inclusion: { in: STATUSES }
    validates :canary_percent, numericality: {
      only_integer: true, greater_than_or_equal_to: MIN_CANARY_PERCENT, less_than_or_equal_to: MAX_CANARY_PERCENT
    }
    validates :code, uniqueness: { scope: :store_id, case_sensitive: false }, if: -> { store_id.present? }
    validate :code_unique_for_global_scope

    scope :recent_first, -> { order(created_at: :desc, id: :desc) }
    scope :active, -> { where(status: 'active') }
    scope :inactive, -> { where(status: 'inactive') }
    scope :global, -> { where(store_id: nil) }
    # 店铺隔离硬边界：全局规则集 + 本店规则集
    scope :for_store, ->(store) { where(store_id: [nil, store&.id].uniq) }
    scope :filter_by, lambda { |store: nil, status: nil|
      result = store.present? ? for_store(store) : all
      result = result.where(status: status) if STATUSES.include?(status.to_s)
      result
    }

    # 引擎是否可用：启用且有生效版本（无生效版本 → 不参与评估，**不猜**）
    def engine_ready?
      status == 'active' && active_version_id.present?
    end

    def canary_active?
      engine_ready? && canary_version_id.present? && canary_percent.to_i.positive?
    end

    # 全局作用域下 code 唯一（store_id IS NULL 时 `uniqueness scope` 不吃 NULL → 手工校验）
    def code_unique_for_global_scope
      return if store_id.present? || code.blank?

      scope = self.class.global.where('LOWER(code) = ?', code.to_s.downcase)
      scope = scope.where.not(id: id) if persisted?
      errors.add(:code, 'has already been taken') if scope.exists?
    end
  end
end
