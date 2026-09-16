# frozen_string_literal: true

# PALLAS-CUSTOM: D13 切片2（PRD-20260916-payments-d13b-payout-ledger；业务方案 §70.2）——
# 结算台账明细行：provider 报表的一行（charge / refund / fee / adjustment）+ 匹配结果。
#
# 匹配状态：
#   * `pending`          —— 尚未匹配（导入后未跑 Match）
#   * `matched`          —— 找到本地记录且金额一致（fee/adjustment 行按 provider 侧项目直接 matched）
#   * `unmatched`        —— 本地无对应记录
#   * `amount_mismatch`  —— 找到记录但金额不一致（差值记 `match_details['difference']`）
module PallasTrade
  class PayoutLine < PallasTrade.base_class
    KINDS = %w[charge refund fee adjustment].freeze
    MATCH_STATUSES = %w[pending matched unmatched amount_mismatch].freeze
    # 金额比较容差（分；provider 报表与本地小数舍入差异）
    AMOUNT_TOLERANCE = BigDecimal('0.01')

    belongs_to :payout, class_name: 'PallasTrade::Payout', inverse_of: :lines
    belongs_to :payment, class_name: 'PallasTrade::Payment', optional: true
    belongs_to :refund, class_name: 'PallasTrade::Refund', optional: true

    validates :kind, presence: true, inclusion: { in: KINDS }
    validates :provider_reference, presence: true
    validates :match_status, presence: true, inclusion: { in: MATCH_STATUSES }
    validates :provider_reference, uniqueness: { scope: %i[payout_id kind] }

    scope :differences, -> { where(match_status: %w[unmatched amount_mismatch]) }
    scope :pending_match, -> { where(match_status: 'pending') }

    def difference?
      %w[unmatched amount_mismatch].include?(match_status)
    end

    # 标记匹配结果（写 match_details 快照；不触碰任何资金对象）。
    # @param status [String] matched / unmatched / amount_mismatch
    # @param details [Hash]
    def mark_match!(status:, details: {})
      raise ArgumentError, "Unsupported match status: #{status}" unless MATCH_STATUSES.include?(status.to_s)

      update!(
        match_status: status.to_s,
        match_details: details.to_h.stringify_keys,
        matched_at: status.to_s == 'pending' ? nil : Time.current
      )
    end

    # 本地金额（用于金额对照展示；无本地记录 → nil）
    def local_amount
      payment&.amount || refund&.amount
    end

    def difference_amount
      match_details.to_h['difference']
    end
  end
end
