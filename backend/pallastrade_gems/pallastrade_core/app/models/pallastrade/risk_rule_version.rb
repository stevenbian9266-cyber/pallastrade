# frozen_string_literal: true

# PALLAS-CUSTOM: D15 切片2（PRD-20260917-payments-d15b-risk-rules；业务方案 §72.2）——
# 风控**规则版本**：规则内容的不可变快照。
#
# 语义（唯一权威）：
#   * `version` 每集从 1 单调递增（唯一键 `(rule_set_id, version)` 兜底并发）；
#   * `state`：`draft`（可编辑）→ `published`（生效/可被置为 active 或 canary）→ `archived`（被更新版取代）；
#   * **发布后 `rules` 不可改写**（要改 = 新建版本）——这是「回滚」可信的前提；
#   * 回滚 = 以历史版本内容生成**新版本**（`rolled_back: true` + `source_version` + `reason`），
#     历史版本内容原样保留，可逐版本对账「当时到底跑的是什么」。
#
# 铁律：版本本身不执行任何动作（求值在 `Risk::Rules::Evaluate`，流转在 `Risk::Rules::Versioning`）。
module PallasTrade
  class RiskRuleVersion < PallasTrade.base_class
    STATES = %w[draft published archived].freeze
    # D15 切片3（PRD-20260917-checkout-d15-切片3）：新增 `force_3ds`（强制 3DS/SCA 认证）——
    # 严重度位于 `review` 与 `block` 之间（见 `Risk::Assess::DECISION_SEVERITY`）。
    ACTIONS = %w[allow review force_3ds block].freeze
    MAX_RULES = 50

    belongs_to :rule_set, class_name: 'PallasTrade::RiskRuleSet', inverse_of: :versions
    belongs_to :created_by, polymorphic: true, optional: true

    validates :version, presence: true, numericality: { only_integer: true, greater_than: 0 }
    validates :version, uniqueness: { scope: :rule_set_id }
    validates :state, inclusion: { in: STATES }
    validate :rules_immutable_after_publish

    before_validation :normalize_rules

    scope :recent_first, -> { order(version: :desc) }
    scope :published, -> { where(state: 'published') }
    scope :drafts, -> { where(state: 'draft') }
    scope :archived, -> { where(state: 'archived') }

    def draft?
      state == 'draft'
    end

    def published?
      state == 'published'
    end

    def archived?
      state == 'archived'
    end

    # 规则条数（页面展示与校验共用同一口径）
    def rules_count
      Array(rules).size
    end

    private

    def normalize_rules
      self.rules = [] if rules.nil?
      self.rules = Array(rules).map { |rule| rule.respond_to?(:to_h) ? rule.to_h.stringify_keys : rule }
    end

    # 发布/归档后不可改写规则内容（`state` 流转本身允许，规则内容变更不允许）
    def rules_immutable_after_publish
      return if new_record? || !rules_changed?
      return if state_was == 'draft' && state == 'draft'

      errors.add(:rules, 'cannot be changed once the version leaves draft')
    end
  end
end
