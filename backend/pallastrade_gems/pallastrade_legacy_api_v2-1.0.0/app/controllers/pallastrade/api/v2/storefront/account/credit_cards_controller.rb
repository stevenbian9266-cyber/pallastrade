module PallasTrade
  module Api
    module V2
      module Storefront
        module Account
          class CreditCardsController < ::PallasTrade::Api::V2::ResourceController
            before_action :require_pallastrade_current_user

            def destroy
              pallastrade_authorize! :destroy, resource, resource

              destroy_service.call(card: resource)
            end

            private

            def resource
              params[:id].eql?('default') ? scope.default.first! : scope.find(params[:id])
            end

            def model_class
              PallasTrade::CreditCard
            end

            def scope
              super.not_expired.not_removed.where(
                user: pallastrade_current_user,
                payment_method: current_store.payment_methods.available_on_front_end
              )
            end

            def collection_serializer
              PallasTrade.api.storefront_credit_card_serializer
            end

            def collection_finder
              PallasTrade.api.storefront_credit_card_finder
            end

            def resource_serializer
              PallasTrade.api.storefront_credit_card_serializer
            end

            def destroy_service
              PallasTrade.api.storefront_credit_cards_destroy_service
            end
          end
        end
      end
    end
  end
end
