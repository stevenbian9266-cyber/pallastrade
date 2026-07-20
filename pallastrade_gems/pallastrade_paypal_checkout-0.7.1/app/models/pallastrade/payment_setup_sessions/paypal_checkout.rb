module PallasTrade
  class PaymentSetupSessions::PaypalCheckout < PaymentSetupSession
    # PayPal's Vault API uses setup tokens (temporary) that get exchanged for
    # permanent payment tokens once the buyer approves on PayPal.
    def paypal_setup_token_id
      external_id
    end

    def paypal_payment_token_id
      external_data&.dig('payment_token', 'id')
    end

    # The approve link the storefront redirects the buyer to.
    def approve_link
      Array(external_data&.dig('links')).find { |l| l['rel'] == 'approve' }&.dig('href')
    end

    def successful?
      status == 'completed'
    end
  end
end
