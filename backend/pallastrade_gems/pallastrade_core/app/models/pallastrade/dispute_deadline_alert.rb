# frozen_string_literal: true

# PALLAS-CUSTOM: D14 切片2（PRD-20260916-payments-d14b-dispute-deadlines；业务方案 §71.2）——
# 争议证据期限的**分档提醒台账行**（append-only：写入即历史，不做状态流转）。
#
# 档位（tier）：
#   * `t{n}`     —— 距今 `n` 天档位（默认 `t3` / `t1`，由店铺策略 `tiers_days` 决定）；
#   * `overdue`  —— 已过期（`evidence_due_at < now`）。
#
# 幂等：唯一键 `(dispute_id, tier)` —— 同一争议同一档位只落一行（「不遗漏」靠达到即写，
# 「不重复」靠唯一键）。`metadata['backfilled']` 标记「跳档补齐」（首次扫描时已跨过多档）。
#
# 铁律：台账只记录「提醒过」，不触发任何资金/状态动作（处置在 `Disputes::AlertDeadlines`）。
module PallasTrade
  class DisputeDeadlineAlert < PallasTrade.base_class
    OVERDUE_TIER = 'overdue'
    TIER_PATTERN = /\A(?:t\d+|#{OVERDUE_TIER})\z/

    belongs_to :dispute, class_name: 'PallasTrade::Dispute', inverse_of: :deadline_alerts
    belongs_to :store, class_name: 'PallasTrade::Store', optional: true

    validates :tier, presence: true, format: { with: TIER_PATTERN }
    validates :alerted_at, presence: true
    validates :tier, uniqueness: { scope: :dispute_id }

    scope :recent_first, -> { order(alerted_at: :desc, id: :desc) }
    scope :for_tier, ->(tier) { where(tier: tier) }

    # 后台筛选（唯一口径：页面/计数共用）
    scope :filter_by, lambda { |store_id: nil, tier: nil, from: nil, to: nil|
      result = all
      result = result.where(store_id: store_id) if store_id.present?
      result = result.for_tier(tier) if tier.present?
      result = result.where(alerted_at: from..) if from.present?
      result = result.where(alerted_at: ..to) if to.present?
      result
    }

    def overdue?
      tier == OVERDUE_TIER
    end

    # 跳档补齐（首次扫描时已经跨过的档位）：只落台账，不补发过期提醒
    def backfilled?
      metadata.to_h['backfilled'] == true
    end

    def days_before_due
      return nil unless tier =~ /\At(\d+)\z/

      ::Regexp.last_match(1).to_i
    end

    def human_tier
      overdue? ? 'overdue' : "t#{days_before_due}"
    end
  end
end
