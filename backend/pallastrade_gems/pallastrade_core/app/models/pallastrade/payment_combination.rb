module PallasTrade
  # A PaymentCombination bundles multiple unpaid orders into a single checkout
  # payment (合并支付). It is deliberately DECOUPLED from the parent/child order
  # structure — a combination may cover orders from different parents, or plain
  # single orders.
  #
  # Contract:
  #   - one PaymentCombination -> one PaymentSession (on the primary order)
  #   - one PaymentCombination -> one Payment (amount = server-computed total)
  #   - one PaymentSplit per member order (authoritative paid/refundable split)
  #
  # State machine is business-safe: invalid transitions raise
  # PaymentCombination::InvalidTransitionError (code + message), never a bare
  # StateMachines::InvalidTransition (lesson learned from the 2026-08 PaymentGroup).
  class PaymentCombination < PallasTrade.base_class
    has_prefix_id :pcom

    include PallasTrade::Metafields
    include PallasTrade::Metadata
    include PallasTrade::SingleStoreResource

    self.event_prefix = 'payment_combination'

    publishes_lifecycle_events

    belongs_to :store, class_name: 'PallasTrade::Store'
    belongs_to :customer, class_name: PallasTrade.user_class.to_s, optional: true

    has_many :payment_splits, class_name: 'PallasTrade::PaymentSplit',
                              inverse_of: :payment_combination, dependent: :destroy
    has_many :orders, through: :payment_splits
    # P4 (2026-08-27): 组合支付本身（挂组合 order_id=nil，session ↔ payment 保持 1:1）
    has_many :payments, class_name: 'PallasTrade::Payment',
                        inverse_of: :payment_combination, dependent: :nullify
    # P5 (2026-08-27): 组合支付会话（挂 primary order，组合一个会话）
    has_many :payment_sessions, class_name: 'PallasTrade::PaymentSession',
                                inverse_of: :payment_combination
    # TXN-P2 (2026-09-05): durable CommerceTransaction 包装（FK 在 commerce_transactions.payment_combination_id）
    has_one :commerce_transaction, class_name: 'PallasTrade::CommerceTransaction',
                                   inverse_of: :payment_combination

    extend PallasTrade::DisplayMoney

    money_methods :amount

    validates :store, :currency, presence: true
    validates :amount, presence: true, numericality: { greater_than_or_equal_to: 0 }

    state_machine :status, initial: :pending do
      state :pending
      state :processing
      state :succeeded
      state :failed
      state :canceled
      state :expired

      event :process do
        transition pending: :processing
      end

      event :succeed do
        transition [:pending, :processing] => :succeeded
      end

      event :fail do
        transition [:pending, :processing] => :failed
      end

      event :cancel do
        transition [:pending, :processing] => :canceled
      end

      event :expire do
        transition [:pending, :processing] => :expired
      end

      after_transition to: :processing, do: :publish_processing_event
      after_transition to: :succeeded,  do: :publish_succeeded_event
      after_transition to: :failed,     do: :publish_failed_event
      after_transition to: :canceled,   do: :publish_canceled_event
      after_transition to: :expired,    do: :publish_expired_event
    end

    scope :not_expired, -> { where('expires_at IS NULL OR expires_at > ?', Time.current) }
    scope :active, -> { not_expired.where(status: %w[pending processing]) }

    delegate :name, to: :store, prefix: true, allow_nil: true

    def amount_in_cents
      money.cents
    end

    def money
      @money ||= PallasTrade::Money.new(amount, currency: currency)
    end

    # P5 (2026-08-27): 组合支付会话（一个组合一个会话，挂 primary order）
    def payment_session
      payment_sessions.order(:id).last
    end

    def expired?
      expires_at.present? && expires_at <= Time.current
    end

    # Server-computed outstanding total across member orders (never client-supplied).
    def total_minus_store_credits
      orders.to_a.sum(&:total_minus_store_credits)
    end

    # Recompute and persist the combination amount from its member orders.
    def recalculate!
      update!(amount: total_minus_store_credits)
    end

    # --- Business-safe transitions --------------------------------------
    # Non-bang state_machines events return false on invalid transition; the
    # bang variants below convert that into a domain error (code + message)
    # instead of letting StateMachines::InvalidTransition bubble up.
    class InvalidTransitionError < StandardError
      attr_reader :code

      def initialize(code:, message:)
        @code = code
        super(message)
      end
    end

    %i[process succeed fail cancel expire].each do |event|
      define_method("#{event}!") do
        unless public_send(event)
          raise InvalidTransitionError.new(
            code: "payment_combination_cannot_#{event}",
            message: "Cannot #{event} payment combination from state '#{status}'"
          )
        end
        true
      end
    end

    private

    def publish_processing_event
      publish_event('payment_combination.processing')
    end

    def publish_succeeded_event
      publish_event('payment_combination.succeeded')
    end

    def publish_failed_event
      publish_event('payment_combination.failed')
    end

    def publish_canceled_event
      publish_event('payment_combination.canceled')
    end

    def publish_expired_event
      publish_event('payment_combination.expired')
    end
  end
end
