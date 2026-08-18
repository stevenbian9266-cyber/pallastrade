module PallasTrade
  module Authentication
    module Strategies
      # Facebook Login strategy.
      #
      # The storefront obtains a Facebook user access token via the FB JS SDK
      # and sends:
      #   { "provider": "facebook", "access_token": "<fb-user-token>" }
      # to POST /api/v3/store/auth/login. This strategy verifies the token with
      # the Graph API (debug_token + /me) and creates/binds a PallasTrade user
      # via UserIdentity.
      #
      # Requires ENV["FACEBOOK_APP_ID"] and ENV["FACEBOOK_APP_SECRET"]. When
      # missing, the strategy fails cleanly (provider disabled).
      class FacebookStrategy < BaseStrategy
        def authenticate
          access_token = params[:access_token]

          return failure('access_token is required') if access_token.blank?
          return failure('Facebook sign-in is not configured') if facebook_app_id.blank? || facebook_app_secret.blank?

          profile = validator.facebook(access_token)
          return failure('Invalid Facebook credential') unless profile

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
          Rails.logger.error "FacebookStrategy authentication failed: #{e.message}"
          failure('Authentication failed')
        end

        def provider
          'facebook'
        end

        private

        def facebook_app_id
          ENV['FACEBOOK_APP_ID']
        end

        def facebook_app_secret
          ENV['FACEBOOK_APP_SECRET']
        end

        def validator
          @validator ||= PallasTrade::Authentication::OAuthTokenValidator.new(
            facebook_app_id: facebook_app_id,
            facebook_app_secret: facebook_app_secret
          )
        end
      end
    end
  end
end
