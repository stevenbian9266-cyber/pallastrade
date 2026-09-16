# frozen_string_literal: true

# PALLAS-CUSTOM: D13 切片2（PRD-20260916-payments-d13b-payout-ledger；业务方案 §70.2）——
# 结算（Payout）台账主表：provider 结算批次 + 汇总 + 状态。
#
# 状态语义（唯一权威，页面/服务都读它）：
#   * `difference`  —— 任一行 `unmatched` / `amount_mismatch`（差异优先）
#   * `settled`     —— 无差异且 `settled_at` 存在（provider 已到账）
#   * `in_transit`  —— 其余（已导入、未结算）
#
# 铁律：台账是**对账事实** —— 不生成资金日志、不触发资金动作（业务方案 §70.1 边界）。
module PallasTrade
  class Payout < PallasTrade.base_class
    STATUSES = %w[in_transit settled difference].freeze
    DIFFERENCE_MATCH_STATUSES = %w[unmatched amount_mismatch].freeze

    belongs_to :store, class_name: 'PallasTrade::Store'
    has_many :lines, class_name: 'PallasTrade::PayoutLine', dependent: :destroy, inverse_of: :payout

    validates :provider, presence: true
    validates :reference, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :reference, uniqueness: { scope: %i[store_id provider] }

    scope :recent_first, -> { order(imported_at: :desc, id: :desc) }
    scope :with_differences, -> { where(status: 'difference') }

    # 后台筛选（唯一口径：页面/汇总共用）。
    scope :filter_by, lambda { |store_id:, provider: nil, status: nil, from: nil, to: nil|
      result = where(store_id: store_id)
      result = result.where(provider: provider) if provider.present?
      result = result.where(status: status) if status.present?
      result = result.where(settled_at: from..) if from.present?
      result = result.where(settled_at: ..to) if to.present?
      result
    }

    def difference?
      status == 'difference'
    end

    def settled?
      status == 'settled'
    end

    # 由行汇总总额（导入/重匹配后调用；口径 = provider 报表值原样求和）。
    def recalculate_totals!
      sums = lines.pick(
        Arel.sql('COALESCE(SUM(gross_amount), 0)'),
        Arel.sql('COALESCE(SUM(fee_amount), 0)'),
        Arel.sql('COALESCE(SUM(net_amount), 0)')
      ) || [0, 0, 0]

      update!(gross_total: sums[0], fee_total: sums[1], net_total: sums[2])
    end

    # 状态合成（差异优先 → 已结算 → 在途）。
    # @return [String] 生效状态
    def refresh_status!
      derived = if lines.where(match_status: DIFFERENCE_MATCH_STATUSES).exists?
                  'difference'
                elsif settled_at.present?
                  'settled'
                else
                  'in_transit'
                end

      update!(status: derived) if status != derived
      derived
    end

    def difference_lines
      lines.where(match_status: DIFFERENCE_MATCH_STATUSES)
    end
  end
end
