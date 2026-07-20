module PallasTrade
  module Api
    module V3
      module Admin
        # Admin CRUD for `PallasTrade::CustomerGroup`. Scoped to the current
        # store so groups from sibling stores don't leak into pickers.
        class CustomerGroupsController < ResourceController
          scoped_resource :customers

          protected

          def model_class
            PallasTrade::CustomerGroup
          end

          def serializer_class
            PallasTrade.api.admin_customer_group_serializer
          end

          def scope
            super.for_store(current_store)
          end

          def permitted_params
            params.permit(:name, :description, customer_ids: [])
          end
        end
      end
    end
  end
end
