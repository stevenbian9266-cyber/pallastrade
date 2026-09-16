# frozen_string_literal: true

# PALLAS-CUSTOM: D14 切片1（PRD-20260916-payments-d14-refund-approval；业务方案 §71.1）——
# 退款审批记录（双人复核）：超阈值退款的 durable 待批行。
#
# 状态语义（唯一权威）：
#   * `pending`   —— 等待**第二人**批准（发起人 ≠ 批准人，服务层强制）
#   * `approved`  —— 已批准（批准后由 `Refunds::Approvals::Approve` 入队 ExecuteJob）
#   * `rejected`  —— 已拒绝（拒绝时 `refund.cancel_request!` 释放可退额度）
#
# 铁律：审批记录本身**不动钱** —— 它只决定「是否入队执行」；provider I/O 仍只发生在
# `Refunds::ExecuteJob`（REV-INV-03，沿用既有语义）。
module PallasTrade
  class RefundApproval < PallasTrade.base_class
    STATUSES = %w[pending approved rejected].freeze
    TERMINAL_STATUSES = %w[approved rejected].freeze

    belongs_to :store, class_name: 'PallasTrade::Store'
    belongs_to :refund, class_name: 'PallasTrade::Refund', inverse_of: :approval
    belongs_to :requester, class_name: PallasTrade.admin_user_class.to_s, optional: true
    belongs_to :approver, class_name: PallasTrade.admin_user_class.to_s, optional: true

    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :refund_id, uniqueness: true

    scope :pending, -> { where(status: 'pending') }
    scope :terminal, -> { where(status: TERMINAL_STATUSES) }
    scope :recent_first, -> { order(created_at: :desc, id: :desc) }

    # 工作台筛选（唯一口径：页面/计数共用）。
    # @param scope_filter [String, nil] 'pending' / 'terminal' / 具体 status
    scope :filter_by, lambda { |store_id:, scope_filter: nil, from: nil, to: nil|
      result = where(store_id: store_id)
      result = case scope_filter.to_s
               when 'pending' then result.pending
               when 'terminal', 'decided' then result.terminal
               when *STATUSES then result.where(status: scope_filter.to_s)
               else result
               end
      result = result.where(created_at: from..) if from.present?
      result = result.where(created_at: ..to) if to.present?
      result
    }

    def pending?
      status == 'pending'
    end

    def approved?
      status == 'approved'
    end

    def rejected?
      status == 'rejected'
    end

    def decided?
      TERMINAL_STATUSES.include?(status)
    end

    # 职责分离（SoD）：发起人不得作为批准/拒绝人（服务层强制，页面隐藏只是 UX）。
    def requester?(actor_id)
      requester_id.present? && actor_id.present? && requester_id.to_i == actor_id.to_i
    end

    # 策略快照中的阈值（审批时展示「当时按什么规则挂起」；缺失不猜 → nil）
    def policy_limit
      policy_snapshot.to_h['auto_approve_limit']
    end

    def policy_currency
      policy_snapshot.to_h['currency']
    end
  end
end
