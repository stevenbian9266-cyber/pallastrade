module PallasTradePaypalCheckout
  class Gateway < ::PallasTrade::Gateway
    module PaymentSetupSessions
      extend ActiveSupport::Concern

      def setup_session_supported?
        true
      end

      def payment_setup_session_class
        PallasTrade::PaymentSetupSessions::PaypalCheckout
      end

      # Creates a PayPal Vault setup token (temporary, awaiting buyer approval)
      # and persists a PallasTrade::PaymentSetupSessions::PaypalCheckout record.
      #
      # @param customer [PallasTrade::User] the customer to vault the PayPal account for
      # @param external_data [Hash] optional :return_url and :cancel_url for the
      #   PayPal redirect flow
      # @return [PallasTrade::PaymentSetupSessions::PaypalCheckout]
      def create_payment_setup_session(customer:, external_data: {})
        return_url = external_data[:return_url] || external_data['return_url'] || default_setup_return_url
        cancel_url = external_data[:cancel_url] || external_data['cancel_url'] || default_setup_cancel_url

        protect_from_error do
          response = client.vault.create_setup_token(
            PallasTradePaypalCheckout::SetupTokenPresenter.new(
              customer: customer,
              return_url: return_url,
              cancel_url: cancel_url
            ).to_h
          )

          payment_setup_session_class.create!(
            customer: customer,
            payment_method: self,
            status: 'pending',
            external_id: response.data.id,
            external_data: response.data.as_json.merge(
              'return_url' => return_url,
              'cancel_url' => cancel_url
            )
          )
        end
      end

      # Completes a setup session by exchanging the approved setup token for a
      # permanent payment token, creates a PallasTrade::PaymentSource representing the
      # vaulted PayPal account, and transitions the session.
      #
      # @param setup_session [PallasTrade::PaymentSetupSessions::PaypalCheckout]
      # @param params [Hash] unused — PayPal needs no params beyond the setup_session
      def complete_payment_setup_session(setup_session:, params: {})
        protect_from_error do
          response = client.vault.create_payment_token(
            'body' => {
              'payment_source' => {
                'token' => {
                  'id' => setup_session.external_id,
                  'type' => 'SETUP_TOKEN'
                }
              }
            }
          )

          payment_token = response.data

          setup_session.payment_source = build_payment_source_from_token(setup_session, payment_token)
          setup_session.update!(
            external_data: setup_session.external_data.to_h.merge('payment_token' => payment_token.as_json)
          )
          setup_session.complete if setup_session.can_complete?
        rescue PaypalServerSdk::APIException => e
          setup_session.fail if setup_session.can_fail?
          raise PallasTrade::Core::GatewayError, "PayPal Vault error: #{e.message}"
        end

        setup_session
      end

      private

      def build_payment_source_from_token(setup_session, payment_token)
        paypal = payment_token.as_json.dig('payment_source', 'paypal') || {}
        account_id = paypal['email_address'] || payment_token.id

        source = PallasTradePaypalCheckout::PaymentSources::Paypal.find_or_initialize_by(
          payment_method: self,
          gateway_payment_profile_id: payment_token.id
        )
        source.update!(
          user: setup_session.customer,
          email: paypal['email_address'],
          name: [paypal.dig('name', 'given_name'), paypal.dig('name', 'surname')].compact.join(' ').strip.presence,
          account_id: account_id,
          account_status: paypal['account_status']
        )
        source
      end

      def default_setup_return_url
        store = stores.first
        return nil unless store

        "#{store.storefront_url}/paypal/payment_setup_sessions/return"
      end

      def default_setup_cancel_url
        store = stores.first
        return nil unless store

        "#{store.storefront_url}/paypal/payment_setup_sessions/cancel"
      end
    end
  end
end
