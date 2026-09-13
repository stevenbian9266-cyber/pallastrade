# frozen_string_literal: true

module PallasTrade
  # PALLAS-CUSTOM: DSP-P7-10 B2 / FR-005
  # (PRD-20260913-payments-争议本地运营增强与-stripe-深化-规格-68-边界-c-…)
  #
  # DisputeEvidenceApproval —— 争议证据草稿的**双人复核**签核记录。
  #
  # 铁律：
  #   - **append-only**：`before_update` + `update_columns` 双拦（与 `FinancialLedgerEntry` /
  #     `DisputeEvidenceSubmission` 同范式）；
  #   - **键 = 载荷摘要**：签核绑定的不是"某次提交"而是**一份具体草稿**（payload_digest 与
  #     `SubmitEvidence` 的幂等基准同算法）——草稿改一个字，原签核自动失效（无需撤销机制）；
  #   - **零资金语义**：无金额列、不参与账本/对账/库存/订单；复核只决定"能否提交"。
  class DisputeEvidenceApproval < PallasTrade.base_class
    has_prefix_id :dap

    DECISIONS = %w[approved rejected].freeze
    APPROVED = 'approved'

    class ImmutableError < StandardError; end

    belongs_to :dispute, class_name: 'PallasTrade::Dispute'

    validates :decision, presence: true, inclusion: { in: DECISIONS }
    validates :payload_digest, presence: true
    validates :payload_digest, uniqueness: { scope: %i[dispute_id decision actor_id] }

    before_update :guard_immutability
    before_destroy :guard_immutability

    scope :for_dispute, ->(dispute) { where(dispute_id: dispute) }
    scope :approved, -> { where(decision: APPROVED) }
    scope :recent_first, -> { order(created_at: :desc, id: :desc) }

    # 草稿是否已被签核通过（提交前置校验的唯一查询口）
    def self.approved_for(dispute:, payload_digest:)
      return nil if dispute.nil? || payload_digest.blank?

      for_dispute(dispute).approved.find_by(payload_digest: payload_digest.to_s)
    end

    def approved?
      decision == APPROVED
    end

    def rejected?
      !approved?
    end

    # 拦截直接列写（update_columns 绕过 before_update）
    def update_columns(*)
      raise ImmutableError, 'DisputeEvidenceApproval is immutable (append-only); create a new record instead'
    end

    private

    def guard_immutability
      raise ImmutableError, 'DisputeEvidenceApproval is immutable (append-only)'
    end
  end
end
