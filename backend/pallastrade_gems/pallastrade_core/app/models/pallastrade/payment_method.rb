module PallasTrade
  class PaymentMethod < PallasTrade.base_class
    has_prefix_id :pm  # Stripe: pm_

    acts_as_paranoid
    acts_as_list

    include PallasTrade::SingleStoreResource
    include PallasTrade::Metafields
    include PallasTrade::Metadata
    include PallasTrade::DisplayOn
    if defined?(PallasTrade::Security::PaymentMethods)
      include PallasTrade::Security::PaymentMethods
    end
    # Multi-store sharing moved to the pallastrade_multi_store extension in 5.6.
    include PallasTrade::LegacyMultiStoreSupport unless defined?(PallasTradeMultiStore)

    scope :active,    -> { where(active: true).order(position: :asc) }
    scope :available, -> { active.where(display_on: [:front_end, :back_end, :both]) }
    scope :store_credit, -> { where(type: 'PallasTrade::PaymentMethod::StoreCredit') }

    after_initialize :set_name, if: :new_record?

    validates :name, presence: true
    validates :store, presence: true, unless: -> { PallasTrade::Config[:disable_store_presence_validation] }
    normalizes :name, with: ->(value) { value&.to_s&.squish&.presence }

    belongs_to :store, class_name: 'PallasTrade::Store'

    has_many :payments, class_name: 'PallasTrade::Payment', inverse_of: :payment_method, dependent: :nullify
    has_many :credit_cards, class_name: 'PallasTrade::CreditCard', dependent: :destroy # CCs are soft deleted

    has_many :payment_sessions, class_name: 'PallasTrade::PaymentSession', dependent: :destroy
    has_many :payment_setup_sessions, class_name: 'PallasTrade::PaymentSetupSession', dependent: :destroy
    has_many :gateway_customers, class_name: 'PallasTrade::GatewayCustomer', dependent: :destroy

    def self.providers
      PallasTrade.payment_methods
    end

    def provider_class
      raise ::NotImplementedError, 'You must implement provider_class method for this gateway.'
    end

    # The class that will process payments for this payment type, used for @payment.source
    # e.g. CreditCard in the case of a the Gateway payment type
    # nil means the payment method doesn't require a source e.g. check
    def payment_source_class
      return unless source_required?

      raise ::NotImplementedError, 'You must implement payment_source_class method for this gateway.'
    end

    # The class used for payment sessions with this payment method.
    # Override in gateway subclasses to provide a provider-specific session class
    # that inherits from PallasTrade::PaymentSession (STI).
    # nil means the payment method doesn't support payment sessions.
    def payment_session_class
      nil
    end

    # Creates a payment session via the provider.
    # Override in gateway subclasses to implement provider-specific session creation.
    def create_payment_session(order:, amount: nil, external_data: {})
      raise ::NotImplementedError, 'You must implement create_payment_session method for this gateway.'
    end

    # Updates an existing payment session via the provider.
    # Override in gateway subclasses to implement provider-specific session updates.
    def update_payment_session(payment_session:, amount: nil, external_data: {})
      raise ::NotImplementedError, 'You must implement update_payment_session method for this gateway.'
    end

    # Completes a payment session via the provider.
    # Override in gateway subclasses to implement provider-specific session completion.
    #
    # Responsibilities:
    # - Verify payment status with the provider
    # - Create/update the PallasTrade::Payment record
    # - Patch order data from provider (e.g. wallet billing address)
    # - Transition payment session to completed/failed
    #
    # Must NOT complete the order — that is handled by Carts::Complete
    # (called by the frontend or by the webhook handler).
    def complete_payment_session(payment_session:, params: {})
      raise ::NotImplementedError, 'You must implement complete_payment_session method for this gateway.'
    end

    # PALLAS-CUSTOM: TXN-P2-3 (PRD-20260904-payments-txn-p2-3)
    # Read-only provider status contract. Queries the provider for the current
    # authoritative status of a payment session WITHOUT mutating any local
    # state (no Payment creation, no state transitions). Consumed by
    # PallasTrade::Transactions::PaymentFactResolver (money-fact resolution).
    #
    # @param payment_session [PallasTrade::PaymentSession]
    # @return [Hash] normalized status:
    #   { status: Symbol, amount_cents: Integer, currency: String, provider_reference: String }
    #   status ∈ :paid | :unpaid | :processing | :requires_capture |
    #            :requires_action | :canceled | :failed | :expired
    # @raise [::NotImplementedError] when the gateway has no read-only contract
    # @raise [PallasTrade::Core::GatewayError] on provider/network failure
    def fetch_payment_status(payment_session:)
      raise ::NotImplementedError, 'You must implement fetch_payment_status method for this gateway.'
    end

    # Parses an incoming webhook payload from the payment provider.
    # Override in gateway subclasses to implement provider-specific webhook parsing.
    #
    # @param raw_body [String] the raw request body
    # @param headers [Hash] the request headers
    # @return [Hash, nil] normalized result or nil for unsupported events
    #   { action: :captured/:authorized/:failed/:canceled,
    #     payment_session: <PallasTrade::PaymentSession>,
    #     metadata: {} }
    # @raise [PallasTrade::PaymentMethod::WebhookSignatureError] if signature is invalid
    def parse_webhook_event(raw_body, headers)
      raise ::NotImplementedError, 'You must implement parse_webhook_event method for this gateway.'
    end

    # Returns the webhook URL for this payment method.
    # @return [String, nil]
    def webhook_url
      return nil unless store

      "#{store.url_or_custom_domain}/api/v3/webhooks/payments/#{prefixed_id}"
    end

    class WebhookSignatureError < StandardError; end

    # Whether this payment method supports setup sessions (saving payment methods for future use).
    # Override in gateway subclasses that support tokenization without a payment.
    def setup_session_supported?
      false
    end

    # The class used for payment setup sessions with this payment method.
    # Override in gateway subclasses to provide a provider-specific session class.
    def payment_setup_session_class
      nil
    end

    # Creates a payment setup session via the provider for saving a payment method.
    # Override in gateway subclasses to implement provider-specific setup session creation.
    def create_payment_setup_session(customer:, external_data: {})
      raise ::NotImplementedError, "#{self.class.name} does not implement #create_payment_setup_session"
    end

    # Completes a payment setup session via the provider.
    # Override in gateway subclasses to implement provider-specific setup session completion.
    def complete_payment_setup_session(setup_session:, params: {})
      raise ::NotImplementedError, "#{self.class.name} does not implement #complete_payment_setup_session"
    end

    def method_type
      type.demodulize.downcase
    end

    def default_name
      self.class.name.demodulize.titleize.gsub(/Gateway/, '').strip
    end

    def payment_icon_name
      type.demodulize.gsub(/(^PallasTrade::Gateway::|Gateway$)/, '').downcase.gsub(/\s+/, '').strip
    end

    def self.find_with_destroyed(*args)
      unscoped { find(*args) }
    end

    def confirmation_required?
      false
    end

    def payment_profiles_supported?
      false
    end

    def source_required?
      true
    end

    def session_required?
      false
    end

    def show_in_admin?
      true
    end

    # Custom gateways should redefine this method. See Gateway implementation
    # as an example
    def reusable_sources(_order)
      []
    end

    def auto_capture?
      auto_capture.nil? ? PallasTrade::Config[:auto_capture] : auto_capture
    end

    def supports?(_source)
      true
    end

    def cancel(_response)
      raise ::NotImplementedError, 'You must implement cancel method for this payment method.'
    end

    def store_credit?
      self.class == PallasTrade::PaymentMethod::StoreCredit
    end

    # Custom PaymentMethod/Gateway can redefine this method to check method
    # availability for concrete order.
    def available_for_order?(order)
      !order.covered_by_store_credit?
    end

    def available_for_store?(store)
      return true if store.blank?

      store_id == store.id
    end

    def public_preferences
      public_preference_keys.each_with_object({}) do |key, hash|
        hash[key] = preferences[key]
      end
    end

    protected

    def public_preference_keys
      []
    end

    def set_name
      self.name ||= default_name
    end
  end
end
