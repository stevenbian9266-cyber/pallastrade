module PallasTrade
  module Api
    module V3
      module Store
        class WishlistItemsController < ResourceController
          prepend_before_action :require_authentication!

          protected

          def set_parent
            @parent = current_user.wishlists.find_by_prefix_id!(params[:wishlist_id])
          end

          def parent_association
            :wished_items
          end

          def model_class
            PallasTrade::WishedItem
          end

          def serializer_class
            PallasTrade.api.wished_item_serializer
          end

          def permitted_params
            params.permit(PallasTrade::PermittedAttributes.wished_item_attributes)
          end
        end
      end
    end
  end
end
