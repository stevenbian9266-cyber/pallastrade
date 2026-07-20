module PallasTrade
  module Seeds
    class AdminUser
      prepend PallasTrade::ServiceModule::Base

      def call
        if PallasTrade.admin_user_class.present? && PallasTrade.admin_user_class.count.zero?
          user = PallasTrade.admin_user_class.create!(
            email: ENV.fetch('ADMIN_EMAIL', 'spree@example.com'),
            password: ENV.fetch('ADMIN_PASSWORD', 'spree123'),
            password_confirmation: ENV.fetch('ADMIN_PASSWORD', 'spree123'),
            first_name: ENV.fetch('ADMIN_FIRST_NAME', 'Spree'),
            last_name: ENV.fetch('ADMIN_LAST_NAME', 'Admin')
          )
          user.save!

          store = PallasTrade::Store.default
          store&.add_user(user) if store&.persisted?
        end
      end
    end
  end
end
