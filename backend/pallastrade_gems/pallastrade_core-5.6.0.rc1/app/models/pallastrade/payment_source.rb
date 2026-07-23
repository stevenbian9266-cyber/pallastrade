# This model is used to store payment sources for non-credit card payments, eg wallet, account, etc.
module PallasTrade
  class PaymentSource < PallasTrade.base_class
    has_prefix_id :ps

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
