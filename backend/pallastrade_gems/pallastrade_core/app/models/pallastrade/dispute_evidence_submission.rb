# frozen_string_literal: true

module PallasTrade
  # PALLAS-CUSTOM: DSP-P7-8 (PRD-20260913-payments-dsp-p7-8)
  #
  # DisputeEvidenceSubmission —— 争议**危险操作**（Submit Evidence / Accept Dispute）的不可变回执。
  #
  # 铁律（源计划 §67/§68）：
  #   - **不含任何金额列**：资金结果由 provider webhook 驱动 P7-3 入账 / P7-6 收敛，本表只记录「对外动作」；
  #   - **append-only**：创建后禁止 update / destroy（`before_update` / `update_columns` 双重拦截，
  #     与 `FinancialLedgerEntry` 同范式）；
  #   - **幂等**：`(dispute_id, kind, payload_digest)` 唯一 —— 重复提交不产生第二次 provider 调用；
  #   - **不含状态机**：本模型**不**改 `Dispute#state`（状态仍由 webhook / 收敛推进）。
  class DisputeEvidenceSubmission < PallasTrade.base_class
    has_prefix_id :des

    # evidence_submitted：向 provider 提交证据（Stripe Dispute#update）
    # accepted：接受争议（Stripe Dispute#close，不可逆）
    KINDS = %w[evidence_submitted accepted].freeze

    class ImmutableError < StandardError; end

    belongs_to :dispute, class_name: 'PallasTrade::Dispute'

    # 文件类证据的**审计留存**（附件挂回执，不回挂 Dispute）；provider 侧引用在 response_metadata
    has_many_attached :evidence_files

    validates :kind, presence: true, inclusion: { in: KINDS }
    validates :payload_digest, presence: true
    validates :payload_digest, uniqueness: { scope: %i[dispute_id kind] }

    before_update :guard_immutability
    before_destroy :guard_immutability

    scope :for_dispute, ->(dispute) { where(dispute_id: dispute) }
    scope :by_kind, ->(kind) { where(kind: kind) }
    scope :recent_first, -> { order(created_at: :desc, id: :desc) }

    # 最近一次同类型回执（幂等查询 / 控制台展示用）
    def self.latest_for(dispute:, kind:)
      for_dispute(dispute).by_kind(kind).recent_first.first
    end

    def accepted?
      kind == 'accepted'
    end

    # 拦截直接列写（update_columns 绕过 before_update）
    def update_columns(*)
      raise ImmutableError, 'DisputeEvidenceSubmission is immutable (append-only); create a new record instead'
    end

    # 规范化 payload 摘要：仅业务载荷（键排序、值字符串化），**不含** actor/时间 —— 幂等基准
    def self.digest_for(payload)
      normalized = payload.to_h.each_with_object({}) do |(key, value), acc|
        acc[key.to_s] = value.is_a?(Hash) ? digest_for(value) : value.to_s
      end.sort.to_h
      Digest::SHA256.hexdigest(JSON.generate(normalized))
    end

    private

    def guard_immutability
      raise ImmutableError, 'DisputeEvidenceSubmission is immutable (append-only)'
    end
  end
end
