module PallasTrade
  module Api
    module V3
      module Store
        class NewsletterSubscribersController < Store::BaseController
          allow_guest_storefront_access!
          rate_limit to: PallasTrade::Api::Config[:rate_limit_register],
                     within: PallasTrade::Api::Config[:rate_limit_window].seconds,
                     store: Rails.cache,
                     only: [:create, :verify],
                     with: RATE_LIMIT_RESPONSE

          # POST /api/v3/store/newsletter_subscribers
          def create
            subscriber = PallasTrade::NewsletterSubscriber.subscribe(
              email: params[:email],
              user: current_user,
              store: current_store,
              redirect_url: validated_redirect_url
            )

            if subscriber.errors.any?
              render_errors(subscriber.errors)
            else
              render json: serialize_resource(subscriber), status: :created
            end
          end

          # POST /api/v3/store/newsletter_subscribers/verify
          def verify
            token = params[:token]

            if token.blank?
              return render_error(
                code: ERROR_CODES[:parameter_missing],
                message: 'token is required',
                status: :unprocessable_content
              )
            end

            subscriber = PallasTrade::NewsletterSubscriber.for_store(current_store).unverified.find_by(verification_token: token)

            unless subscriber
              return render_error(
                code: ERROR_CODES[:invalid_token],
                message: PallasTrade.t(:newsletter_verification_token_invalid, scope: :api),
                status: :unprocessable_content
              )
            end

            PallasTrade::Newsletter::Verify.new(subscriber: subscriber).call

            render json: serialize_resource(subscriber)
          end

          protected

          def serializer_class
            PallasTrade::Api::V3::NewsletterSubscriberSerializer
          end

          private

          # Drop redirect_url when it isn't in the store's allow-list — secure-by-default,
          # mirrors password_resets. Returning nil omits it from the webhook payload rather
          # than rejecting the request, so callers can't probe the allow-list via 4xx errors.
          def validated_redirect_url
            redirect_url = params[:redirect_url]
            return nil if redirect_url.blank?
            return nil unless current_store.allowed_origin?(redirect_url)

            redirect_url
          end
        end
      end
    end
  end
end
