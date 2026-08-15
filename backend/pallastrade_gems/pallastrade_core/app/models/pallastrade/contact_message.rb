# frozen_string_literal: true

module PallasTrade
  # Inbound customer communication: complaints, feedback, inquiries — either
  # submitted via the storefront contact form or captured from inbound email
  # replies when the email reply switch is enabled.
  class ContactMessage < PallasTrade.base_class
    has_prefix_id :ctct

    include PallasTrade::SingleStoreResource

    belongs_to :store, class_name: 'PallasTrade::Store'

    KINDS = %w[complaint feedback inquiry reply].freeze
    STATUSES = %w[pending in_progress resolved].freeze

    validates :store, :email, :body, presence: true
    validates :kind, inclusion: { in: KINDS }
    validates :status, inclusion: { in: STATUSES }

    scope :pending, -> { where(status: 'pending') }
    scope :by_kind, ->(kind) { where(kind: kind) if kind.present? }
    scope :recent, -> { order(created_at: :desc) }
  end
end
