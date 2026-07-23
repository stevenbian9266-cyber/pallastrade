module PallasTrade
  module Api
    module V2
      module Storefront
        class PostsController < ::PallasTrade::Api::V2::ResourceController
          protected

          def sorted_collection
            sorter = PallasTrade.api.storefront_posts_sorter
            if sorter
              sorter.new(collection, params, allowed_sort_attributes).call
            else
              super
            end
          end

          def collection
            @collection ||= begin
              finder = PallasTrade.api.storefront_posts_finder
              if finder
                finder.new(scope: scope, params: finder_params).execute
              else
                result = scope
                result = result.search_by_title(params[:q]) if params[:q].present?
                result = result.where(post_category_id: params.dig(:filter, :category_ids).split(',')) if params.dig(:filter, :category_ids).present?
                result = result.tagged_with(params.dig(:filter, :tags).split(','), any: true) if params.dig(:filter, :tags).present?
                result
              end
            end
          end

          def resource
            @resource ||= find_with_fallback_default_locale { scope.friendly.find(params[:id]) } || scope.friendly.find(params[:id])
          end

          def collection_serializer
            PallasTrade::V2::Storefront::PostSerializer
          end

          def resource_serializer
            PallasTrade::V2::Storefront::PostSerializer
          end

          def model_class
            PallasTrade::Post
          end

          def scope
            model_class.for_store(current_store).published.includes(:post_category, image_attachment: :blob)
          end

          def allowed_sort_attributes
            super << :published_at << :title
          end
        end
      end
    end
  end
end
