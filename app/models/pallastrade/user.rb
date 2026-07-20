class PallasTrade::User < PallasTrade.base_class
  include PallasTrade::UserAddress
  include PallasTrade::UserMethods
  include PallasTrade::UserPaymentSource

  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable
end
