# frozen_string_literal: true

# PALLAS-CUSTOM: D14 切片3（PRD-20260916-payments-d14c-dispute-rate-board；业务方案 §71.3 + §72.5）——
# **拒付率预警台账行**（append-only 记录，档位只会单向升级）。
#
# 一行 = 一个「店铺 × 卡组织 × 评估日」的预警观测：
#   * `tier`        —— `approaching`（达到阈值 × 预警比例，默认 80%）/ `breached`（达到或超过阈值）
#   * `*_ratio_bps` —— 当时观测到的笔数比 / 金额比（bps = 万分之一；nil = 窗口内无分母，**不猜**）
#   * `*_threshold_bps` —— 当时生效的阈值（留档：阈值后来改了也能回溯当时的判定依据）
#   * `triggered_metrics` —— 触发的是哪一项（`count` / `amount`）
#
# 幂等：唯一键 `dedupe_key = "rate:<store_id>:<network>:<evaluated_on>"` —— 同一评估日重复评估
# **只更新同一行**（刷新观测值），档位升级时更新 `tier` 并记 `escalated_at`（首次进入更高档的时间）。
#
# 铁律：台账只记录「曾经逼近/超过阈值」，不触发任何资金、争议状态或 provider 动作。
module PallasTrade
  class DisputeRateAlert < PallasTrade.base_class
    APPROACHING = 'approaching'
    BREACHED = 'breached'
    TIERS = [APPROACHING, BREACHED].freeze
    # 严重度排序（升级判定用：只允许向「更严重」走）
    TIER_SEVERITY = { APPROACHING => 1, BREACHED => 2 }.freeze
    METRICS = %w[count amount].freeze
    UNKNOWN_NETWORK = 'unknown'

    belongs_to :store, class_name: 'PallasTrade::Store'

    validates :network, :tier, :evaluated_on, :dedupe_key, :detected_at, presence: true
    validates :tier, inclusion: { in: TIERS }
    validates :dedupe_key, uniqueness: true
    validates :window_days, numericality: { greater_than: 0, only_integer: true }

    scope :recent_first, -> { order(evaluated_on: :desc, id: :desc) }
    scope :for_tier, ->(tier) { where(tier: tier) }
    scope :for_network, ->(network) { where(network: network) }
    scope :for_store, ->(store) { where(store_id: store&.id) }

    # 后台筛选（唯一口径：页面计数与列表共用同一 scope）
    scope :filter_by, lambda { |store_id: nil, network: nil, tier: nil, from: nil, to: nil|
      result = all
      result = result.where(store_id: store_id) if store_id.present?
      result = result.for_network(network) if network.present?
      result = result.for_tier(tier) if tier.present?
      result = result.where(evaluated_on: from.to_date..) if from.present?
      result = result.where(evaluated_on: ..to.to_date) if to.present?
      result
    }

    # 幂等键（唯一口径：服务写入与测试断言共用）
    # @return [String]
    def self.key_for(store_id:, network:, evaluated_on:)
      "rate:#{store_id}:#{network}:#{evaluated_on.respond_to?(:to_date) ? evaluated_on.to_date : evaluated_on}"
    end

    def breached?
      tier == BREACHED
    end

    def approaching?
      tier == APPROACHING
    end

    def escalated?
      escalated_at.present?
    end

    # 触发指标（`['count']` / `['amount']` / 两者）；非法结构一律视为空（只读安全）
    def triggered
      Array(triggered_metrics).map(&:to_s).select { |metric| METRICS.include?(metric) }
    end

    def triggered?(metric)
      triggered.include?(metric.to_s)
    end

    # 观测值 → 百分比（bps / 100），nil 透传（不用 0 伪装）
    def count_ratio_percent
      bps_to_percent(count_ratio_bps)
    end

    def amount_ratio_percent
      bps_to_percent(amount_ratio_bps)
    end

    def count_threshold_percent
      bps_to_percent(count_threshold_bps)
    end

    def amount_threshold_percent
      bps_to_percent(amount_threshold_bps)
    end

    # 观测值占阈值的比例（%）：看板进度条用；阈值缺失或 bps 缺失 → nil
    def usage_percent(metric)
      observed = metric.to_s == 'amount' ? amount_ratio_bps : count_ratio_bps
      threshold = metric.to_s == 'amount' ? amount_threshold_bps : count_threshold_bps
      return nil if observed.nil? || threshold.nil? || threshold.to_i <= 0

      (observed.to_d / threshold.to_d * 100).round(1)
    end

    private

    def bps_to_percent(bps)
      return nil if bps.nil?

      (bps.to_d / 100).round(2)
    end
  end
end
