module SpreePaypalCheckout
  # Builds the body of a PayPal Vault /v3/vault/setup-tokens request for tokenizing
  # a buyer's PayPal account without an immediate purchase.
  class SetupTokenPresenter
    def initialize(customer:, return_url:, cancel_url:)
      @customer = customer
      @return_url = return_url
      @cancel_url = cancel_url
    end

    def to_h
      {
        'body' => {
          'payment_source' => {
            'paypal' => {
              'usage_type' => 'MERCHANT',
              'experience_context' => {
                'return_url' => return_url,
                'cancel_url' => cancel_url
              }
            }
          }
        }.merge(customer_payload)
      }
    end

    private

    attr_reader :customer, :return_url, :cancel_url

    def customer_payload
      return {} unless customer&.id

      { 'customer' => { 'id' => "customer_#{customer.id}" } }
    end
  end
end
