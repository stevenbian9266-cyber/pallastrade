module PallasTrade
  module Api
    module V2
      module Storefront
        module Account
          class AddressesController < ::PallasTrade::Api::V2::ResourceController
            include PallasTrade::BaseHelper

            before_action :require_pallastrade_current_user

            def create
              pallastrade_authorize! :create, model_class

              result = create_service.call(user: pallastrade_current_user, address_params: address_params)
              render_result(result)
            end

            def update
              pallastrade_authorize! :update, resource

              result = update_service.call(address: resource, address_params: address_params)
              render_result(result)
            end

            def destroy
              pallastrade_authorize! :destroy, resource

              if resource.destroy
                head 204
              else
                render_error_payload(resource.errors)
              end
            end

            private

            def collection
              collection_finder.new(scope: scope, params: finder_params).execute
            end

            def scope
              super.where(user: pallastrade_current_user, country: available_countries).not_deleted
            end

            def model_class
              PallasTrade::Address
            end

            def collection_finder
              PallasTrade.api.storefront_address_finder
            end

            def collection_serializer
              PallasTrade.api.storefront_address_serializer
            end

            def resource_serializer
              PallasTrade.api.storefront_address_serializer
            end

            def create_service
              PallasTrade.api.storefront_address_create_service
            end

            def update_service
              PallasTrade.api.storefront_address_update_service
            end

            def address_params
              params.require(:address).permit(permitted_address_attributes)
            end
          end
        end
      end
    end
  end
end
