# frozen_string_literal: true

module PallasTrade
  # PALLAS-CUSTOM: DSP-P7-10 B1
  # (PRD-20260913-payments-争议本地运营增强与-stripe-深化-规格-68-边界-c-…)
  #
  # DisputeEvidenceAsset —— 争议**证据素材库**。
  #
  # 定位（源计划 §68 边界 C）：运营可预先准备**可复用素材**（说明文本、条款截图、物流凭证等），
  # 在人工准备证据草稿时**引用**（`EvidenceAssets#insert` 返回纯值），**永不自动提交**。
  #
  # 铁律：
  #   - **不是资金实体**：无金额列、无账本/对账关联、不触网、不建 `DisputeEvidenceSubmission`；
  #   - **只读引用**：素材本身不持有 provider 句柄，引用产物是普通 Hash（交给人工确认后走 SubmitEvidence）；
  #   - **store 作用域**：`store_id` 可空（全局素材），查询恒经 `for_store`/显式 scope，不做跨店泄漏。
  class DisputeEvidenceAsset < PallasTrade.base_class
    has_prefix_id :dea

    KINDS = %w[text file].freeze
    MAX_NAME_LENGTH = 120
    MAX_REASON_CODE_LENGTH = 80
    MAX_EVIDENCE_KEY_LENGTH = 80

    belongs_to :store, optional: true

    # 文件类素材的审计留存（与回执附件同范式：挂素材自身，不回挂 Dispute）
    has_one_attached :file

    validates :name, presence: true, length: { maximum: MAX_NAME_LENGTH }
    validates :kind, presence: true, inclusion: { in: KINDS }
    validates :reason_code, length: { maximum: MAX_REASON_CODE_LENGTH }, allow_nil: true
    validates :evidence_key, length: { maximum: MAX_EVIDENCE_KEY_LENGTH }, allow_nil: true
    validates :name, uniqueness: { scope: :store_id }, allow_nil: true
    validate :body_present_for_text_kind

    scope :for_store, ->(store) { where(store_id: store&.id) }
    scope :active_only, -> { where(active: true) }
    scope :by_kind, ->(kind) { kind.present? ? where(kind: kind.to_s) : all }
    scope :for_reason_code, ->(code) { code.present? ? where(reason_code: code.to_s) : all }
    scope :for_evidence_key, ->(key) { key.present? ? where(evidence_key: key.to_s) : all }
    scope :recent_first, -> { order(created_at: :desc, id: :desc) }

    def text?
      kind.to_s == 'text'
    end

    def file?
      kind.to_s == 'file'
    end

    # 引用值：文本素材 → 正文；文件素材 → 附件（未附加时为 nil，引用方须自行判空）
    def value
      text? ? body.to_s : file
    end

    private

    def body_present_for_text_kind
      errors.add(:body, :blank) if text? && body.blank?
    end
  end
end
