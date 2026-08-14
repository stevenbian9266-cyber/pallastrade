module PallasTrade
  module Api
    module V3
      module Store
        class CustomersController < Store::BaseController
          allow_guest_storefront_access!
          rate_limit to: PallasTrade::Api::Config[:rate_limit_register], within: PallasTrade::Api::Config[:rate_limit_window].seconds, store: Rails.cache, only: :create, with: RATE_LIMIT_RESPONSE

          skip_before_action :authenticate_user, only: [:create]
          prepend_before_action :require_authentication!, only: [:show, :update]

          # POST /api/v3/store/customers
          def create
            unless turnstile_verified?
              return render_error(
                code: ErrorHandler::ERROR_CODES[:turnstile_verification_failed],
                message: PallasTrade.t(:turnstile_verification_failed, scope: :api),
                status: :unprocessable_content
              )
            end

            user = PallasTrade.user_class.new(permitted_params.except(:current_password))

            if user.save
              link_matching_newsletter_subscriber!(user)
              refresh_token = PallasTrade::RefreshToken.create_for(user, request_env: {
                ip_address: request.remote_ip,
                user_agent: request.user_agent&.truncate(255)
              })
              render json: {
                token: generate_jwt(user),
                refresh_token: refresh_token.token,
                user: user_serializer.new(user, params: serializer_params).to_h
              }, status: :created
            else
              render_errors(user.errors)
            end
          end

          # GET /api/v3/store/customer
          def show
            render json: serialize_resource(current_user)
          end

          # PATCH /api/v3/store/customer
          def update
            if sensitive_update? && !valid_current_password?
              return render_error(
                code: ErrorHandler::ERROR_CODES[:current_password_invalid],
                message: PallasTrade.t(:current_password_invalid, scope: :api),
                status: :unprocessable_content
              )
            end

            update_params = permitted_params.except(:current_password)

            if current_user.update(update_params)
              render json: serialize_resource(current_user)
            else
              render_errors(current_user.errors)
            end
          end

          protected

          def serializer_class
            PallasTrade.api.customer_serializer
          end

          def serializer_params
            {
              store: current_store,
              locale: current_locale,
              currency: current_currency,
              user: current_user,
              includes: [],
              hide_prices: hide_prices?
            }
          end

          def permitted_params
            params.permit(:email, :password, :password_confirmation, :first_name, :last_name,
                          :accepts_email_marketing, :phone, :current_password, metadata: {})
          end

          private

          # Turnstile gates registration only when the secret is configured. The
          # verification outcome is tri-state:
          #   true  → Cloudflare confirmed the token (pass)
          #   false → Cloudflare explicitly rejected the token (block)
          #   nil   → unable to verify (secret missing / network unreachable /
          #           upstream anomaly). In this case we degrade OPEN with a
          #           warning log: on CN-hosted servers challenges.cloudflare.com
          #           is frequently unreachable, and fail-closed there would make
          #           registration permanently impossible. An explicit rejection
          #           (false) is still respected.
          def turnstile_verified?
            return true unless PallasTrade::Api::Turnstile.configured?

            case PallasTrade::Api::Turnstile.verify(
              params[:turnstile_token].to_s,
              remote_ip: request.remote_ip
            )
            when true
              true
            when nil
              Rails.logger.warn(
                "[Turnstile] verification unreachable (network/timeout), " \
                "falling back open — ip=#{request.remote_ip}"
              )
              true
            else
              false
            end
          end

          def sensitive_update?
            (params[:email].present? && params[:email] != current_user.email) ||
              params[:password].present?
          end

          def valid_current_password?
            return false if params[:current_password].blank?

            if current_user.respond_to?(:valid_password?)
              current_user.valid_password?(params[:current_password])
            elsif current_user.respond_to?(:authenticate)
              current_user.authenticate(params[:current_password]).present?
            else
              false
            end
          end

          def user_serializer
            PallasTrade.api.customer_serializer
          end

          def link_matching_newsletter_subscriber!(user)
            subscriber = PallasTrade::NewsletterSubscriber.find_by(email: user.email, store: current_store)
            PallasTrade::Newsletter::LinkUser.new(subscriber: subscriber, user: user).call
          end
        end
      end
    end
  end
end
