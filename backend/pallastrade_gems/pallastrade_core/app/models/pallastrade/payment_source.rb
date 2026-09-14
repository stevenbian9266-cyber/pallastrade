# This model is used to store payment sources for non-credit card payments, eg wallet, account, etc.
module PallasTrade
  class PaymentSource < PallasTrade.base_class
    # PALLAS-CUSTOM (2026-09-14, PRD-20260914-other-paymentsource-prefix-disambiguation):
    # `ps` was shared with PaymentSession, so a `ps_…` id was ambiguous across both
    # resources (the v3 API implies the resource type from the prefix, and
    # PaymentSessionReservationSubscriber branches on `ps_` assuming a session).
    # PaymentSource now owns a unique prefix; PaymentSession keeps `ps` because the
    # storefront and SDK already depend on it.
    has_prefix_id :src

    include PallasTrade::Metafields
    include PallasTrade::Metadata
    include PallasTrade::PaymentSourceConcern

    #
    # Associations
    #
    belongs_to :payment_method, class_name: 'PallasTrade::PaymentMethod'
    belongs_to :user, class_name: PallasTrade.user_class.to_s, optional: true

    #
    # Validations
    #
    validates_uniqueness_of :gateway_payment_profile_id, scope: :type

    #
    # Delegations
    #
    delegate :profile_id, to: :gateway_customer, prefix: true, allow_nil: true

    # Returns the gateway customer for the user.
    # @return [PallasTrade::GatewayCustomer]
    def gateway_customer
      return if user.blank?

      payment_method.gateway_customers.find_by(user: user)
    end
  end
end
