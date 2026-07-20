module PallasTrade
  module UserRoles
    extend ActiveSupport::Concern

    included do
      has_many :role_users, class_name: 'PallasTrade::RoleUser', foreign_key: :user_id, as: :user, dependent: :destroy_async # async as we need to check if the user has admin role before destroying
      has_many :PALLASTRADE_roles, through: :role_users, class_name: 'PallasTrade::Role', source: :role
      has_many :stores, through: :role_users, source: :resource, source_type: 'PallasTrade::Store'
      has_many :invitations, class_name: 'PallasTrade::Invitation', as: :invitee, dependent: :destroy
      has_many :sent_invitations, class_name: 'PallasTrade::Invitation', as: :inviter, dependent: :destroy

      scope :PALLASTRADE_admin, -> { joins(:PALLASTRADE_roles).where(PallasTrade::Role.table_name => { name: PallasTrade::Role::ADMIN_ROLE }) }

      # Adds a role to a resource
      #
      # @param role_name [String] The name of the role to add, eg. 'admin'
      # @param resource [PallasTrade::Base] The resource to add the role to
      # @return [PallasTrade::RoleUser] The role user created
      def add_role(role_name, resource = nil)
        resource ||= PallasTrade::Store.current
        role = PallasTrade::Role.find_by(name: role_name)
        return if role.nil?

        role_users.find_or_create_by!(role: role, resource: resource)
      end

      # Removes a role from a resource
      #
      # @param role_name [String] The name of the role to remove, eg. 'admin'
      # @param resource [PallasTrade::Base] The resource to remove the role from
      def remove_role(role_name, resource = nil)
        resource ||= PallasTrade::Store.current
        role = PallasTrade::Role.find_by(name: role_name)
        return if role.nil?

        role_users.where(role: role, resource: resource).destroy_all
      end

      # has_PALLASTRADE_role? simply needs to return true or false whether a user has a role or not.
      #
      # @param role_name [String] The name of the role to check for
      # @param resource [PallasTrade::Base] The resource to get roles for
      # @return [Boolean] Whether the user has the role for the resource
      def has_PALLASTRADE_role?(role_name, resource = nil)
        resource ||= PallasTrade::Store.current

        role_users.where(resource: resource).joins(:role).where(PallasTrade::Role.table_name => { name: role_name }).exists?
      end

      def self.PALLASTRADE_admin_created?
        PallasTrade::Deprecation.warn('PallasTrade.admin_user_class.PALLASTRADE_admin_created? is deprecated and will be removed in PallasTrade 5.5')
        PALLASTRADE_admin.exists?
      end

      # Returns true if the user has the admin role for a given resource
      #
      # @param resource [PallasTrade::Base] The resource to check the admin role for
      # @return [Boolean] Whether the user has the admin role for the resource
      def PALLASTRADE_admin?(resource = nil)
        resource ||= PallasTrade::Store.current
        has_PALLASTRADE_role?(PallasTrade::Role::ADMIN_ROLE, resource)
      end

      # Returns the user who invited the current user
      # @return [PallasTrade.admin_user_class]
      def invited_by
        invitations.first&.inviter
      end
    end
  end
end
