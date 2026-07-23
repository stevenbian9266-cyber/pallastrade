module PallasTrade
  module Api
    module V2
      module Storefront
        class PostCategoriesController < ::PallasTrade::Api::V2::ResourceController
          protected

          def collection
            @collection ||= scope
          end

          def resource
            @resource ||= find_with_fallback_default_locale { scope.friendly.find(params[:id]) } || scope.friendly.find(params[:id])
          end

          def collection_serializer
            PallasTrade::V2::Storefront::PostCategorySerializer
          end

          def resource_serializer
            PallasTrade::V2::Storefront::PostCategorySerializer
          end

          def model_class
            PallasTrade::PostCategory
          end

          def scope
            model_class.for_store(current_store)
          end

          def serializer_params
            super.merge(include_posts: action_name == 'show')
          end
        end
      end
    end
  end
end
