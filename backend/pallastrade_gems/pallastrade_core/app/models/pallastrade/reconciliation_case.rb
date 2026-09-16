# frozen_string_literal: true

# PALLAS-CUSTOM: D13 切片1（PRD-20260916-payments-d13-reconciliation-cases；业务方案 §70.1）——
# 对账差异案例（Reconciliation Case）：把 P4 只读对账结论变成**可运营的工作队列**。
#
# 边界（硬约束，与 P4 §44/§46 + runbook 一致）：
#   * 本模型是**工作队列**，不是资金对象 —— 绝不修改 Payment/Refund/Transaction/Journal/订单/库存，
#     也绝不触发 provider 调用；案例动作只写案例表 + AuditLog。
#   * 唯一写入口 = `Reconciliations::SyncCases`（自动）+ 后台控制器动作（人工）。
module PallasTrade
  class ReconciliationCase < PallasTrade.base_class
    KINDS = %w[transaction payment refund payout].freeze
    # 人工可置的终态（自动逻辑永不覆盖）
    HUMAN_RESOLVED_STATUSES = %w[explained fixed dismissed].freeze
    STATUSES = %w[open investigating explained fixed dismissed].freeze
    DIFFERENCE_TYPES = %w[
      amount_mismatch allocation_mismatch refund_mismatch one_sided duplicate
      settlement_pending journal_missing provider_issue needs_attention unsupported
      payout_unmatched payout_amount_mismatch
    ].freeze
    SEVERITIES = %w[critical attention info].freeze
    RESOLUTION_SOURCES = %w[human auto].freeze

    # 原因码 → 差异类型（确定性映射；唯一权威，禁止散落判断）
    REASON_DIFFERENCE_TYPES = {
      'AMOUNT_MISMATCH' => 'amount_mismatch',
      'CURRENCY_MISMATCH' => 'amount_mismatch',
      'ALLOCATION_MISMATCH' => 'allocation_mismatch',
      'COMMERCIAL_AMOUNT_MISMATCH' => 'amount_mismatch',
      'REFUND_MISMATCH' => 'refund_mismatch',
      'LOCAL_PAYMENT_MISSING' => 'one_sided',
      'PROVIDER_PAYMENT_MISSING' => 'one_sided',
      'LOCAL_REFUND_MISSING' => 'one_sided',
      'PROVIDER_REFUND_MISSING' => 'one_sided',
      'SETTLEMENT_PENDING' => 'settlement_pending',
      'JOURNAL_POSTING_MISSING' => 'journal_missing',
      'PROVIDER_UNAVAILABLE' => 'provider_issue',
      'PROVIDER_CONTRACT_UNSUPPORTED' => 'provider_issue',
      'UNLINKED_LEGACY_PAYMENT' => 'duplicate',
      'AMBIGUOUS_CAPTURE' => 'duplicate',
      'PAYOUT_LINE_UNMATCHED' => 'payout_unmatched',
      'PAYOUT_AMOUNT_MISMATCH' => 'payout_amount_mismatch'
    }.freeze
    # 对账状态 → 严重级
    STATUS_SEVERITIES = { 'MISMATCH' => 'critical', 'NEEDS_ATTENTION' => 'attention' }.freeze
    # 案例类型前缀（dedupe_key 首段）：交易级对账 / 结算台账
    KEY_PREFIXES = { transaction: 'txn', payout: 'payout' }.freeze

    belongs_to :store, class_name: 'PallasTrade::Store'
    # ⚠️ 不能命名为 `transaction`：与 ActiveRecord 内建 `transaction` 方法冲突，
    # 故关联名 = `commerce_transaction`（列名仍为 `transaction_id`）。
    belongs_to :commerce_transaction, class_name: 'PallasTrade::CommerceTransaction',
                                       foreign_key: :transaction_id, optional: true
    belongs_to :payment, class_name: 'PallasTrade::Payment', optional: true
    belongs_to :refund, class_name: 'PallasTrade::Refund', optional: true
    belongs_to :assignee, class_name: PallasTrade.admin_user_class.to_s, optional: true

    has_many :notes, -> { order(:created_at) }, class_name: 'PallasTrade::ReconciliationCaseNote',
                                                foreign_key: :reconciliation_case_id, dependent: :destroy,
                                                inverse_of: :reconciliation_case

    validates :kind, presence: true, inclusion: { in: KINDS }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :severity, presence: true, inclusion: { in: SEVERITIES }
    validates :difference_type, presence: true, inclusion: { in: DIFFERENCE_TYPES }
    validates :dedupe_key, presence: true, uniqueness: true

    scope :open_queue, -> { where(status: %w[open investigating]) }
    scope :resolved, -> { where(status: HUMAN_RESOLVED_STATUSES) }
    scope :recent_first, -> { order(last_seen_at: :desc, id: :desc) }

    # 后台队列筛选（唯一口径：页面/计数/CSV 导出都走它，避免三处各写一套）。
    # @param scope_filter [String, nil] 'queue'（未解决）/ 'resolved'（已判定）/ 具体 status
    scope :filter_by, lambda { |store_id:, scope_filter: nil, kind: nil, difference_type: nil,
                                severity: nil, provider: nil, assignee_id: nil, search: nil|
      result = where(store_id: store_id)
      result = case scope_filter.to_s
               when 'queue' then result.open_queue
               when 'resolved' then result.resolved
               when *STATUSES then result.where(status: scope_filter.to_s)
               else result
               end
      result = result.where(kind: kind) if kind.present?
      result = result.where(difference_type: difference_type) if difference_type.present?
      result = result.where(severity: severity) if severity.present?
      result = result.where(provider: provider) if provider.present?
      result = result.where(assignee_id: assignee_id) if assignee_id.present?
      result = result.merge(search_by(search)) if search.present?
      result
    }

    # 关键词搜索：交易 prefixed id / 订单号 / 去重键片段 / 原因码文本。
    # 找不到对应实体时**不猜**（返回 `none` 而非全表），避免「搜到不相关内容」。
    scope :search_by, lambda { |query|
      term = query.to_s.strip
      next none if term.blank?

      transaction_ids = []
      if term.start_with?('txn_')
        found = PallasTrade::CommerceTransaction.find_by(prefixed_id: term)
        transaction_ids << found.id if found
      end

      order = PallasTrade::Order.find_by(number: term)
      if order
        transaction_ids.concat(
          PallasTrade::TransactionOrder.where(order_id: order.id).limit(50).pluck(:commerce_transaction_id)
        )
      end

      if transaction_ids.any?
        where(transaction_id: transaction_ids.uniq)
      else
        where('dedupe_key ILIKE :term OR reason_codes::text ILIKE :term', term: "%#{term}%")
      end
    }

    # @param status [String] 对账状态（TransactionResult/SourceResult 的 status）
    # @param reasons [Array<String>]
    # @return [String] 差异类型
    def self.difference_type_for(status:, reasons:)
      return 'unsupported' if status.to_s == 'UNSUPPORTED'

      Array(reasons).map(&:to_s).filter_map { |code| REASON_DIFFERENCE_TYPES[code] }.first || 'needs_attention'
    end

    # @param status [String]
    # @return [String] 严重级
    def self.severity_for(status:)
      STATUS_SEVERITIES[status.to_s] || 'info'
    end

    # 差异签名：排序去重的原因码（空 → 状态名），用于 dedupe_key 与「签名被取代」判定。
    def self.signature_for(status:, reasons:)
      codes = Array(reasons).map(&:to_s).reject(&:blank?).uniq.sort
      codes.any? ? codes.join('+') : status.to_s
    end

    # @return [String] `txn:<transaction_id>:<signature>`
    def self.dedupe_key_for(transaction_id:, signature:)
      "txn:#{transaction_id}:#{signature}"
    end

    # 通用去重键（D13 切片2 引入）：`<prefix>:<subject_id>:<signature>`。
    # @param prefix [String, Symbol] `txn` / `payout` …
    def self.key_for(prefix:, subject_id:, signature:)
      "#{prefix}:#{subject_id}:#{signature}"
    end

    # 人工是否已判定（自动逻辑不得覆盖）
    def human_resolved?
      HUMAN_RESOLVED_STATUSES.include?(status)
    end

    def open?
      status == 'open'
    end

    def investigating?
      status == 'investigating'
    end

    # 是否仍在队列中（未解决）
    def in_queue?
      %w[open investigating].include?(status)
    end

    def auto_resolved?
      resolution_source == 'auto'
    end

    # 关闭案例（人工 or 自动）。
    # @param status [String] explained / fixed / dismissed
    # @param source [String] human / auto
    def close!(status:, source:, note: nil)
      raise ArgumentError, "Unsupported close status: #{status}" unless HUMAN_RESOLVED_STATUSES.include?(status.to_s)

      update!(
        status: status.to_s,
        resolution_source: source.to_s,
        resolution_note: note.to_s.strip.first(500).presence,
        resolved_at: Time.current
      )
    end

    # 重新打开（人工）。
    def reopen!
      update!(status: 'open', resolution_source: nil, resolution_note: nil, resolved_at: nil)
    end

    def assign_to!(user)
      update!(assignee: user)
    end

    # 摘要金额（来自 P4 TransactionFinancialSummary 快照；缺失 → nil，不猜）
    def summary_amount(key)
      summary.to_h[key.to_s].presence
    end
  end
end
