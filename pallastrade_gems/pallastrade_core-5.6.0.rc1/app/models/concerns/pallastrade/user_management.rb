module PallasTrade
  module UserManagement
    extend ActiveSupport::Concern

    included do
      has_many :role_users, class_name: 'PallasTrade::RoleUser', as: :resource, dependent: :destroy
      has_many :users, through: :role_users, source: :user, source_type: PallasTrade.admin_user_class.to_s
      has_many :invitations, class_name: 'PallasTrade::Invitation', as: :resource, dependent: :destroy
    end

    # Adds a user to the resource with the default user role
    # If no role is provided, the default user role will be used
    # If a role is provided, it will be used instead of the default user role
    # @param user [PallasTrade.admin_user_class] The user to add to the resource
    # @param role [PallasTrade::Role] The role to add the user to
    def add_user(user, role = nil)
      role = role || default_user_role
      role_users.find_or_create_by!(user: user, role: role)
    end

    # Revokes a user's access to the resource
    # @param user [PallasTrade.admin_user_class] The user to remove from the resource
    # @return [void]
    def remove_user(user)
      role_users.where(user: user).destroy_all
    end

    # this can be overridden in the base model to use a different user role, eg. 'vendor'
    def default_user_role
      PallasTrade::Role.default_admin_role
    end
  end
end
