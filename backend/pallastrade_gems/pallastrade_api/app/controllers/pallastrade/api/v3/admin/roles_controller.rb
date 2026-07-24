module PallasTrade
  module Api
    module V3
      module Admin
        # Read-only list of roles available for staff role pickers (invite +
        # edit forms). Roles are global, not per-store; CRUD is handled
        # outside the SPA today and may grow into a richer permissions UI
        # later. The controller ignores `current_store` for that reason.
        class RolesController < ResourceController
          scoped_resource :settings

          protected

          def model_class
            PallasTrade::Role
          end

          def serializer_class
            PallasTrade.api.admin_role_serializer
          end

          def scope
            PallasTrade::Role.accessible_by(current_ability, :show)
          end
        end
      end
    end
  end
end
