module PallasTrade
  module Api
    module V2
      module Storefront
        module Stripe
          class SetupIntentsController < BaseController
            before_action :require_pallastrade_current_user

            def create
              setup_intent = SpreeStripe::CreateSetupIntent.call(gateway: stripe_gateway, user: try_pallastrade_current_user)

              render_serialized_payload(200) { setup_intent.value }
            end
          end
        end
      end
    end
  end
end
