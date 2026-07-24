module PallasTrade
  module Authentication
    module Strategies
      class BaseStrategy
        attr_reader :params, :request_env, :user_class

        def initialize(params:, request_env:, user_class: nil)
          @params = params
          @request_env = request_env
          @user_class = user_class || PallasTrade.user_class
        end

        # Returns Result object with user on success
        # @return [PallasTrade::ServiceModule::Result]
        def authenticate
          raise NotImplementedError, 'Subclass must implement #authenticate'
        end

        # Returns provider identifier (e.g., 'google', 'email')
        # @return [String]
        def provider
          raise NotImplementedError, 'Subclass must implement #provider'
        end

        protected

        # Success result with user
        def success(user)
          PallasTrade::ServiceModule::Result.new(success: true, value: user)
        end

        # Failure result with error message
        def failure(message)
          PallasTrade::ServiceModule::Result.new(success: false, error: message)
        end

        # Find user by email
        def find_user_by_email(email)
          user_class.find_by(email: email)
        end

        # Find or create user identity
        def find_or_create_user_from_oauth(provider:, uid:, info:, tokens: {})
          PallasTrade::UserIdentity.find_or_create_from_oauth(
            provider: provider,
            uid: uid,
            info: info,
            tokens: tokens,
            user_class: user_class
          )
        end
      end
    end
  end
end
