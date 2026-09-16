# frozen_string_literal: true

# PALLAS-CUSTOM: D15 切片1（PRD-20260916-payments-d15-risk-lists；业务方案 §72.2 决策留痕底座）——
# 风控**决策留痕**：一行 = 一次评估（订单 × 时刻）。
#
# 幂等：唯一键 `(order_id, evaluated_at)`（秒级）→ 订阅者重复投递不产生第二行。
# 用途：①订单页「风控」卡展示最近一次决策；②后续切片（规则引擎 / 3DS 下发 / 复核队列）的唯一数据源；
#   ③运营可按 `decision` 统计（review 待办量的基础）。
#
# 铁律：留痕**只描述过去**，不触发任何动作（标记/阻断由调用方决定）。
module PallasTrade
  class PaymentRiskAssessment < PallasTrade.base_class
    DECISIONS = %w[allow review block].freeze
    FLAGGED_DECISIONS = %w[review block].freeze

    belongs_to :order, class_name: 'PallasTrade::Order', optional: true
    belongs_to :store, class_name: 'PallasTrade::Store', optional: true

    validates :decision, presence: true, inclusion: { in: DECISIONS }
    validates :evaluated_at, presence: true

    scope :recent_first, -> { order(evaluated_at: :desc, id: :desc) }
    scope :for_order, ->(order) { where(order_id: order&.id) }
    scope :flagged, -> { where(decision: FLAGGED_DECISIONS) }
    scope :filter_by, lambda { |store: nil, decision: nil|
      result = all
      result = result.where(store_id: store.id) if store.present?
      result = result.where(decision: decision) if decision.present?
      result
    }

    def allow?
      decision == 'allow'
    end

    def review?
      decision == 'review'
    end

    def block?
      decision == 'block'
    end

    def flagged?
      FLAGGED_DECISIONS.include?(decision)
    end

    def matched_entry_ids
      Array(super)
    end

    def matched_count
      matched_entry_ids.size
    end

    def insufficient_subject?
      signals.to_h['insufficient_subject'] == true
    end
  end
end
