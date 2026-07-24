module PallasTradeAdyen
  class WebhooksController < ActionController::API
    include PallasTrade::Core::ControllerHelpers::Store

    before_action :validate_hmac!

    def create
      PallasTradeAdyen::Webhooks::HandleEvent.new(event_payload: webhook_params).call

      head :ok
    end

    private

    def validate_hmac!
      if hmac_validator_class.nil?
        Rails.logger.info("[PallasTradeAdyen][#{event_code}]: Skipping not supported event")
        head :ok
        return
      end

      validator = hmac_validator_class.new(
        request: request,
        params: webhook_params,
        gateway: current_store.adyen_gateway
      )

      return if validator.call

      Rails.logger.error("[PallasTradeAdyen]: Failed to validate hmac for #{event_code}")
      head :unauthorized
    end

    def hmac_validator_class
      PallasTradeAdyen.hmac_validators[event_code]
    end

    def event_code
      webhook_params.dig('notificationItems', 0, 'NotificationRequestItem', 'eventCode') || webhook_params['type']
    end

    def webhook_params
      @webhook_params ||= JSON.parse(request.raw_post).with_indifferent_access
    end
  end
end
