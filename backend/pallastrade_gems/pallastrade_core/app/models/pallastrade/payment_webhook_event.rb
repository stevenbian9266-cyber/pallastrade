# frozen_string_literal: true

module PallasTrade
  # P0-2 (2026-09-02): Webhook Event Store —— 每个已验签 webhook 事件的
  # 数据库事实记录。用途：
  #   - DB 级去重：UNIQUE(provider, provider_event_id) → 重复投递只落一条
  #   - 失败可见 / 可重试 / 可重放（Replay 走原事件记录）
  #   - attempt_count = Payments::HandleWebhook 实际开始执行次数
  #
  # 状态机（PRD FR-020）：received → processing → processed | failed
  #   - received   ：已验签落库，等待 Job
  #   - processing ：Job 开始执行 HandleWebhook
  #   - processed  ：HandleWebhook 成功
  #   - failed     ：HandleWebhook 抛异常（保存错误，交 Job retry / Manual Replay）
  #
  # ⚠️ 这是可靠性外壳，不是业务逻辑 —— 业务幂等仍在 Payments::HandleWebhook /
  # Carts::Complete。未知/transient 异常必须 raise（Job retry），禁止 swallow。
  class PaymentWebhookEvent < PallasTrade.base_class
    # 无 has_prefix_id —— 内部事件表，整数主键即可；对外不暴露资源 API。
    # 原始 provider payload 已落 payload jsonb 列，无需 Metafields/Metadata
    # （后者依赖 public_metadata/private_metadata 列，本表不需要）。

    STATUSES = %w[received processing processed failed quarantined].freeze
    ACTIONS  = %w[captured authorized failed canceled].freeze
    # PRD-20260911-payments-dsp-p7-1 (DSP-P7-1)：provider 发起的资金逆转事件族。
    # 这些事件不绑定 payment_session（parse 层分流），落库后由 HandleWebhookJob 分流到
    # `PallasTrade::Disputes::HandleProviderEvent`。
    DISPUTE_ACTIONS = %w[
      dispute_created dispute_updated dispute_closed
      dispute_funds_withdrawn dispute_funds_reinstated
    ].freeze
    ALL_ACTIONS = (ACTIONS + DISPUTE_ACTIONS).freeze

    belongs_to :payment_method, class_name: 'PallasTrade::PaymentMethod', optional: false
    belongs_to :payment_session, class_name: 'PallasTrade::PaymentSession', optional: true

    validates :provider, :provider_event_id, :status, presence: true
    validates :provider_event_id, uniqueness: { scope: :provider }
    validates :status, inclusion: { in: STATUSES }
    validates :action, inclusion: { in: ALL_ACTIONS }, allow_nil: true

    before_validation :normalize_provider_created_at

    # 数值型 provider_created_at（Stripe 等用 unix epoch）归一化为 Time。
    def normalize_provider_created_at
      value = provider_created_at
      return if value.nil?
      return unless value.is_a?(Numeric) || value.to_s.match?(/\A\d+\z/)

      self.provider_created_at = Time.at(value.to_i)
    end

    scope :received, -> { where(status: 'received') }
    scope :processing, -> { where(status: 'processing') }
    scope :processed, -> { where(status: 'processed') }
    scope :failed, -> { where(status: 'failed') }
    scope :quarantined, -> { where(status: 'quarantined') }

    # PALLAS-CUSTOM: D12（PRD-20260915-payments-d12-webhook-governance 切片1）——
    # 运营面筛选（业务方案 §69「事件流」）：单一入口，控制器只做参数校验，
    # 避免把筛选口径散落在视图/控制器里。`order_number` 经 payment_session → order 反查。
    # @return [ActiveRecord::Relation]
    def self.filter_by(provider: nil, action: nil, status: nil, from: nil, to: nil, order_number: nil)
      scope = all
      scope = scope.where(provider: provider) if provider.present?
      scope = scope.where(action: action) if action.present?
      scope = scope.where(status: status) if status.present?
      scope = scope.where(received_at: from..) if from.present?
      scope = scope.where(received_at: ..to) if to.present?
      if order_number.present?
        scope = scope.joins(payment_session: :order)
                     .where(pallastrade_orders: { number: order_number.to_s.strip })
      end
      scope
    end

    STATUSES.each do |status_name|
      define_method("#{status_name}?") { status == status_name }
    end

    # PRD-20260911-payments-dsp-p7-1：dispute 事件族判定（Job 分流依据）。
    def dispute_action?
      DISPUTE_ACTIONS.include?(action.to_s)
    end

    def self.dispute_action?(action)
      DISPUTE_ACTIONS.include?(action.to_s)
    end

    # ── 生命周期（简单方法 + 显式守卫，不用 state_machine：
    #    本表是可靠性外壳，过度状态机无益；但非法迁移必须被拒绝 ──

    # 幂等插入：重复 (provider, provider_event_id) 返回既有记录并标记 duplicate?
    # 返回 [event, duplicate]；duplicate=true 表示是重复投递（调用方应 ACK 200 且不重复入队）。
    # 校验失败（如缺 provider_event_id）→ raise，由 controller 500 / provider 重投处理。
    def self.create_unique(provider:, provider_event_id:, **attrs)
      event = new(attrs.merge(provider: provider, provider_event_id: provider_event_id,
                              status: 'received', received_at: Time.current))
      event.save!
      [event, false]
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
      # 校验层先于 DB 约束层拦截重复：uniqueness 校验失败（已有相同
      # provider_event_id）或并发下 DB 唯一约束触发，都归为重复投递。
      if e.is_a?(ActiveRecord::RecordInvalid) &&
          !e.record.errors.of_kind?(:provider_event_id, :taken)
        raise
      end

      existing = find_by(provider: provider, provider_event_id: provider_event_id)
      existing.persisted? ? [existing, true] : raise
    end

    # mark_* 是返回布尔结果的变更器（非谓词），仅供内部/Job 状态迁移使用；
    # 返回布尔便于调用方判断「是否真的发生了迁移」。
    # rubocop:disable Naming/PredicateMethod
    def mark_processing!
      return false unless %w[received failed].include?(status)

      update!(status: 'processing', processing_at: Time.current,
              attempt_count: attempt_count + 1)
      true
    end

    def mark_processed!
      return false unless status == 'processing'

      update!(status: 'processed', processed_at: Time.current,
              last_error_class: nil, last_error_message: nil)
      true
    end

    # 记录失败但不改变 status 语义：failed 状态由 Job 的异常路径写入，
    # 以便 Job retry / Manual Replay 能从 failed 重新 mark_processing。
    def mark_failed!(error)
      update!(
        status: 'failed',
        processed_at: Time.current,
        last_error_class: error.class.name,
        last_error_message: error.message.to_s.truncate(2000)
      )
    end
    # rubocop:enable Naming/PredicateMethod

    # Manual Replay：从 failed（或任何非 processing）状态重新进入 processing。
    # D12：隔离事件不可直接重放（需先解除隔离，避免把被判定为“未知/可疑”的事件直接送入业务链）。
    def replayable?
      !processing? && !quarantined?
    end

    # PALLAS-CUSTOM: D12（切片1）—— 隔离（“忽略未知事件”）：保留留痕、不参与处理。
    # @param reason [String] 必填理由（≤ 500 字，落库前截断）
    # @return [Boolean] 状态迁移是否发生
    def mark_quarantined!(reason:)
      return false if processing?

      update!(
        status: 'quarantined',
        quarantined_at: Time.current,
        quarantine_reason: reason.to_s.strip.truncate(500)
      )
      true
    end

    # PALLAS-CUSTOM: D12（切片1）—— 解除隔离：回到 failed（可重放 / 可人工处置）。
    def unquarantine!
      return false unless quarantined?

      update!(status: 'failed', quarantined_at: nil, quarantine_reason: nil)
      true
    end

    # PALLAS-CUSTOM: D12（切片1）—— 人工标记已处理（业务上已线下核实，不再重放）。
    def mark_processed_manually!
      return false if processing?

      update!(
        status: 'processed',
        processed_at: Time.current,
        quarantined_at: nil,
        quarantine_reason: nil,
        last_error_class: nil,
        last_error_message: nil
      )
      true
    end

    # D12：关联订单（经 payment_session；dispute 事件族无 session → nil）。
    def order
      payment_session&.order
    end

    # D12：处理耗时（入站 → 处理完成；未完成返回 nil）。
    def processing_duration_seconds
      return nil if received_at.nil? || processed_at.nil?

      (processed_at - received_at).round(3)
    end
  end
end
