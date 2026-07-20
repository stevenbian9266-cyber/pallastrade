# Default implementation of User.
require 'bcrypt'

module PallasTrade
  class LegacyUser < PallasTrade.base_class
    include PallasTrade::UserAddress
    include PallasTrade::UserPaymentSource
    include PallasTrade::UserMethods

    self.table_name = 'pallastrade_pallastrade_users'

    attr_accessor :password, :password_confirmation

    validates :email, presence: true, uniqueness: { case_sensitive: false }
    validates :password, confirmation: true, if: :password

    before_save :encrypt_password, if: :password

    # Simple password validation for testing purposes
    # In production, PallasTrade.user_class should be overridden with a proper auth solution (e.g., Devise)
    def valid_password?(check_password)
      return false if encrypted_password.blank?

      BCrypt::Password.new(encrypted_password) == check_password
    end

    private

    def encrypt_password
      self.encrypted_password = BCrypt::Password.create(password)
    end
  end
end
