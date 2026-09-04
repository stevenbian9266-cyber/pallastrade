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

    STATUSES = %w[received processing processed failed].freeze
    ACTIONS  = %w[captured authorized failed canceled].freeze

    belongs_to :payment_method, class_name: 'PallasTrade::PaymentMethod', optional: false
    belongs_to :payment_session, class_name: 'PallasTrade::PaymentSession', optional: true

    validates :provider, :provider_event_id, :status, presence: true
    validates :provider_event_id, uniqueness: { scope: :provider }
    validates :status, inclusion: { in: STATUSES }
    validates :action, inclusion: { in: ACTIONS }, allow_nil: true

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

    STATUSES.each do |status_name|
      define_method("#{status_name}?") { status == status_name }
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
    def replayable?
      status != 'processing'
    end
  end
end
