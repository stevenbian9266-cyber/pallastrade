module PallasTrade
  module Authentication
    module Strategies
      # Google OAuth (Google Identity Services) sign-in strategy.
      #
      # The storefront obtains a Google ID token via the GIS JS SDK and sends:
      #   { "provider": "google", "id_token": "<google-id-token>" }
      # to POST /api/v3/store/auth/login. This strategy verifies the token with
      # Google's tokeninfo endpoint, enforces the audience (client id), and
      # creates/binds a PallasTrade user via UserIdentity.
      #
      # Requires ENV["GOOGLE_CLIENT_ID"]. When missing, the strategy fails
      # cleanly (provider disabled) instead of raising.
      class GoogleStrategy < BaseStrategy
        def authenticate
          id_token = params[:id_token]

          return failure('id_token is required') if id_token.blank?
          return failure('Google sign-in is not configured') if google_client_id.blank?

          profile = validator.google(id_token)
          return failure('Invalid Google credential') unless profile

          user = find_or_create_user_from_oauth(
            provider: provider,
            uid: profile[:provider_uid],
            info: {
              email: profile[:email],
              first_name: profile[:first_name],
              last_name: profile[:last_name],
              email_verified: profile[:email_verified]
            }
          )

          success(user)
        rescue => e
          Rails.logger.error "GoogleStrategy authentication failed: #{e.message}"
          failure('Authentication failed')
        end

        def provider
          'google'
        end

        private

        def google_client_id
          ENV['GOOGLE_CLIENT_ID']
        end

        def validator
          @validator ||= PallasTrade::Authentication::OAuthTokenValidator.new(
            google_client_id: google_client_id
          )
        end
      end
    end
  end
end
