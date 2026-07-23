module PallasTrade
  module Api
    module V2
      module Storefront
        module Account
          class OrdersController < ::PallasTrade::Api::V2::ResourceController
            before_action :require_pallastrade_current_user

            private

            def collection
              collection_finder.new(user: pallastrade_current_user, store: current_store).execute
            end

            def resource
              resource = resource_finder.new(user: pallastrade_current_user, number: params[:id], store: current_store).execute.take
              raise ActiveRecord::RecordNotFound if resource.nil?

              resource
            end

            def allowed_sort_attributes
              super << :completed_at
            end

            def collection_serializer
              PallasTrade.api.storefront_order_serializer
            end

            def resource_serializer
              PallasTrade.api.storefront_order_serializer
            end

            def collection_finder
              PallasTrade.api.storefront_completed_order_finder
            end

            def resource_finder
              PallasTrade.api.storefront_completed_order_finder
            end

            def model_class
              PallasTrade::Order
            end
          end
        end
      end
    end
  end
end
