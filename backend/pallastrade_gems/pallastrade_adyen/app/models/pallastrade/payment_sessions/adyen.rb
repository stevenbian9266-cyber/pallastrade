module PallasTrade
  class PaymentSessions::Adyen < PaymentSession
    AVAILABLE_CHANNELS = {
      ios: 'iOS',
      android: 'Android',
      web: 'Web'
    }.freeze

    # Adyen-specific accessors from external_data
    def adyen_id
      external_id
    end

    def session_data
      external_data&.dig('session_data')
    end

    def client_key
      payment_method.preferred_client_key
    end

    def channel
      external_data&.dig('channel') || AVAILABLE_CHANNELS[:web]
    end

    def return_url
      external_data&.dig('return_url')
    end

    def accepted?
      status == 'completed'
    end

    def successful?
      status == 'completed'
    end

    def find_or_create_payment!(metadata = {})
      return unless persisted?
      return payment if payment.present?

      order.with_lock do
        existing_payment = order.payments.where(
          payment_method: payment_method,
          response_code: external_id
        ).first

        return existing_payment if existing_payment.present?

        # P0-1 (2026-09-02): 显式关联 originating PaymentSession。
        order.payments.create!(
          payment_method: payment_method,
          amount: amount,
          response_code: external_id,
          payment_session: self,
          skip_source_requirement: true
        )
      end
    end
  end
end
