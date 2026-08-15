# frozen_string_literal: true

module PallasTrade
  # Read-only record of an outgoing transactional email. Written by an
  # ActionMailer observer (see PallasTrade::EmailLogRecorder) so admins can
  # audit who received what, when, and whether delivery succeeded.
  class EmailLog < PallasTrade.base_class
    has_prefix_id :emlg

    include PallasTrade::SingleStoreResource

    belongs_to :store, class_name: 'PallasTrade::Store'

    validates :store, :mailer, :action, :to, presence: true

    STATUSES = %w[sent failed].freeze

    scope :recent, -> { order(sent_at: :desc) }
    scope :by_status, ->(status) { where(status: status) if status.present? }

    def failed?
      status == 'failed'
    end
  end
end
