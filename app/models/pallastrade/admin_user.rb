class PallasTrade::AdminUser < PallasTrade.base_class
  include PallasTrade::AdminUserMethods

  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable
end
