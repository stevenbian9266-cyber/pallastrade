module PallasTrade
  module Api
    module V3
      class BaseController < ActionController::API
        # API v3 uses flat params — disable Rails' automatic parameter wrapping
        wrap_parameters false

        include ActiveStorage::SetCurrent
        include CanCan::ControllerAdditions
        include PallasTrade::Core::ControllerHelpers::StrongParameters
        include PallasTrade::Core::ControllerHelpers::Store
        include PallasTrade::Api::V3::LocaleAndCurrency
        include PallasTrade::Api::V3::JwtAuthentication
        include PallasTrade::Api::V3::ApiKeyAuthentication
        include PallasTrade::Api::V3::ErrorHandler
        include PallasTrade::Api::V3::SecurityHeaders
        include PallasTrade::Api::V3::ResourceSerializer
        include PallasTrade::Api::V3::RateLimitHeaders
        include PallasTrade::Api::V3::Idempotent
        include Pagy::Method

        RATE_LIMIT_RESPONSE = -> {
          limit = PallasTrade::Api::Config[:rate_limit_per_key]
          window = PallasTrade::Api::Config[:rate_limit_window]
          body = { error: { code: 'rate_limit_exceeded', message: 'Too many requests. Please retry later.' } }
          headers = {
            'Content-Type' => 'application/json',
            'Retry-After' => window.to_s,
            'X-RateLimit-Limit' => limit.to_s,
            'X-RateLimit-Remaining' => '0'
          }
          [429, headers, [body.to_json]]
        }

        rate_limit to: PallasTrade::Api::Config[:rate_limit_per_key], within: PallasTrade::Api::Config[:rate_limit_window].seconds,
                   store: Rails.cache,
                   by: -> { request.headers['X-PallasTrade-Api-Key'] || request.remote_ip },
                   with: RATE_LIMIT_RESPONSE

        # Optional JWT authentication by default
        before_action :authenticate_user

        protected

        # Override to use current_user from JWT authentication
        # @return [PallasTrade.user_class]
        def pallastrade_current_user
          current_user
        end

        alias try_pallastrade_current_user pallastrade_current_user

        # CanCanCan ability
        # @return [PallasTrade::Ability]
        def current_ability
          @current_ability ||= PallasTrade::Ability.new(current_user, ability_options)
        end

        # Options passed to the CanCanCan ability
        # @return [Hash]
        def ability_options
          { store: current_store }
        end
      end
    end
  end
end
