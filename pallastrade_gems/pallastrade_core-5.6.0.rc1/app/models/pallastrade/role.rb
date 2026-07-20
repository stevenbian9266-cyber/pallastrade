module PallasTrade
  class Role < PallasTrade.base_class
    has_prefix_id :role

    include PallasTrade::UniqueName

    ADMIN_ROLE = 'admin'

    #
    # Associations
    #
    has_many :role_users, class_name: 'PallasTrade::RoleUser', dependent: :destroy
    has_many :users, through: :role_users, source: :user, source_type: PallasTrade.user_class.to_s
    has_many :admin_users, through: :role_users, source: :user, source_type: PallasTrade.admin_user_class.to_s
    has_many :invitations, class_name: 'PallasTrade::Invitation', dependent: :destroy

    #
    # Scopes
    #
    scope :admin, -> { where(name: ADMIN_ROLE) }

    #
    # Class Methods
    #
    def self.default_admin_role
      find_or_create_by(name: ADMIN_ROLE)
    end
  end
end
