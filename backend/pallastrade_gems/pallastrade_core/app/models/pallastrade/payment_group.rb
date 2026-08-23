# PALLAS-CUSTOM: 多订单合并支付（PRD-20260823-checkout-多订单拆分与合并支付）
#
# A PaymentGroup bundles multiple unpaid orders into a single payment. It is the
# carrier for "合并支付" (combined payment): one Stripe Checkout Session / PaymentIntent
# covers every member order, and a single successful webhook completes them all.
#
# Membership rules (validated in PallasTrade::PaymentGroups::Create):
#   - same store, same user, same currency
#   - orders are not yet paid (no completed payment covering the full total)
#   - orders belong to the current store
module PallasTrade
  class PaymentGroup < PallasTrade.base_class
    has_prefix_id :pg

    acts_as_paranoid

    include PallasTrade::Metafields
    include PallasTrade::Metadata
    include PallasTrade::SingleStoreResource

    self.event_prefix = 'payment_group'

    publishes_lifecycle_events

    belongs_to :store, class_name: 'PallasTrade::Store'
    belongs_to :customer, class_name: PallasTrade.user_class.to_s, optional: true

    has_many :orders, class_name: 'PallasTrade::Order', inverse_of: :payment_group
    has_many :payment_sessions, class_name: 'PallasTrade::PaymentSession', inverse_of: :payment_group

    extend PallasTrade::DisplayMoney
    money_methods :amount

    validates :store, :currency, presence: true
    validates :amount, presence: true, numericality: { greater_than_or_equal_to: 0 }

    state_machine :status, initial: :pending do
      state :pending
      state :processing
      state :completed
      state :failed
      state :canceled
      state :expired

      event :process do
        transition pending: :processing
      end

      event :complete do
        transition [:pending, :processing] => :completed
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
      after_transition to: :completed, do: :publish_completed_event
      after_transition to: :failed, do: :publish_failed_event
      after_transition to: :canceled, do: :publish_canceled_event
      after_transition to: :expired, do: :publish_expired_event
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

    def expired?
      expires_at.present? && expires_at <= Time.current
    end

    # Total still outstanding across all member orders (server-computed, never client-supplied).
    def total_minus_store_credits
      orders.to_a.sum(&:total_minus_store_credits)
    end

    # Recompute and persist the group amount from its member orders.
    def recalculate!
      update!(amount: total_minus_store_credits)
    end

    # The primary order is the first member order — used to keep the existing
    # single-order PaymentSession contract (store/currency/customer delegation).
    def primary_order
      orders.first
    end

    private

    def publish_processing_event
      publish_event('payment_group.processing')
    end

    def publish_completed_event
      publish_event('payment_group.completed')
    end

    def publish_failed_event
      publish_event('payment_group.failed')
    end

    def publish_canceled_event
      publish_event('payment_group.canceled')
    end

    def publish_expired_event
      publish_event('payment_group.expired')
    end
  end
end
