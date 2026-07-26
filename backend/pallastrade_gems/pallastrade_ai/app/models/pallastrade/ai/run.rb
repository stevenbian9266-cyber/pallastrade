# frozen_string_literal: true

module PallasTrade
  module AI
    # Records every AI invocation 鈥?sync, async, failed, or skipped.
    # Contains token counts, cost estimates, timing data, and error information.
    # Sensitive data (prompts, full input/output) is NOT stored on this record.
    class Run < BaseModel
      self.table_name = 'pallastrade_ai_runs'
      include PallasTrade::SingleStoreResource

      belongs_to :store, class_name: 'PallasTrade::Store'
      belongs_to :user, class_name: 'PallasTrade::AdminUser', optional: true
      belongs_to :provider, class_name: 'PallasTrade::Integration', optional: true
      belongs_to :model, class_name: 'PallasTrade::AI::Model', optional: true

      has_many :artifacts, class_name: 'PallasTrade::AI::Artifact', dependent: :destroy

      validates :status, presence: true
      validates :mode, presence: true, inclusion: { in: %w[sync async] }
      validates :idempotency_key, uniqueness: { scope: :store_id }, allow_nil: true

      # Lifecycle statuses.
      STATUSES = %w[queued running succeeded failed cancelled skipped].freeze

      # Statuses that indicate no HTTP request was made.
      NO_HTTP_STATUSES = %w[cancelled skipped].freeze

      # Statuses that are terminal (no further transitions).
      TERMINAL_STATUSES = %w[succeeded failed cancelled skipped].freeze

      validates :status, inclusion: { in: STATUSES }

      scope :for_store, ->(store) { where(store: store) }
      scope :recent, -> { order(created_at: :desc) }
      scope :succeeded, -> { where(status: 'succeeded') }
      scope :failed, -> { where(status: 'failed') }
      scope :skipped, -> { where(status: 'skipped') }

      # Mark run as skipped (blocked by switch/policy, no HTTP).
      def skip!(reason:, error_code: nil)
        update!(
          status: 'skipped',
          unavailable_reason: reason,
          error_code: error_code,
          completed_at: Time.current
        )
      end

      # Transition to running state.
      def start!
        update!(
          status: 'running',
          started_at: Time.current,
          attempts: attempts + 1
        )
      end

      # Mark as succeeded with usage data.
      def succeed!(usage: {}, provider_request_id: nil, latency_ms: nil)
        update!(
          status: 'succeeded',
          provider_request_id: provider_request_id,
          input_tokens: usage[:input_tokens] || 0,
          cached_input_tokens: usage[:cached_input_tokens] || 0,
          output_tokens: usage[:output_tokens] || 0,
          reasoning_tokens: usage[:reasoning_tokens] || 0,
          latency_ms: latency_ms,
          completed_at: Time.current
        )
      end

      # Mark as failed with error info.
      def fail!(error_code:, error_message:, provider_request_id: nil)
        update!(
          status: 'failed',
          error_code: error_code,
          error_message: error_message&.truncate(500),
          provider_request_id: provider_request_id,
          completed_at: Time.current
        )
      end

      # Check if this run can be retried.
      def retryable?
        failed? && attempts < 3 && !%w[ai_credentials_invalid ai_configuration_invalid].include?(error_code)
      end
    end
  end
end
