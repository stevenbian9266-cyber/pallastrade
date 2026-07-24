require 'rails/generators'

module PallasTrade
  module Authentication
    class DeviseGenerator < Rails::Generators::Base
      desc 'Set up a PallasTrade installation with Devise as authentication'

      def self.source_paths
        paths = superclass.source_paths
        paths << File.expand_path('templates', __dir__)
        paths.flatten
      end

      def generate
        template 'authentication_helpers.rb.tt', 'lib/pallastrade/authentication_helpers.rb'

        file_action = File.exist?('config/initializers/PallasTrade.rb') ? :append_file : :create_file
        send(file_action, 'config/initializers/PallasTrade.rb') do
          %Q{
            Rails.application.config.to_prepare do
              require_dependency 'pallastrade/authentication_helpers'
            end\n}
        end

        user_class_file = Rails.root.join('app', 'models', "#{PallasTrade.user_class.name.underscore}.rb")

        if File.exist?(user_class_file)
          inject_into_file user_class_file, after: "class #{PallasTrade.user_class.name} < ApplicationRecord\n" do
            <<-RUBY
    # PallasTrade modules
    include PallasTrade::UserAddress
    include PallasTrade::UserMethods
    include PallasTrade::UserPaymentSource
            RUBY
          end
          gsub_file user_class_file, "< ApplicationRecord", "< PallasTrade.base_class"

          say "Successfully added PallasTrade user modules into #{user_class_file}"
        else
          say "Could not locate user model file at #{user_class_file}. Please add these lines manually:", :red
          say <<~RUBY
            # PallasTrade modules
            include PallasTrade::UserAddress
            include PallasTrade::UserMethods
            include PallasTrade::UserPaymentSource
          RUBY

          say "Please replace < ApplicationRecord with < PallasTrade.base_class in #{user_class_file}"
        end

        if PallasTrade.admin_user_class != PallasTrade.user_class
          admin_user_class_file = Rails.root.join('app', 'models', "#{PallasTrade.admin_user_class.name.underscore}.rb")

          if File.exist?(admin_user_class_file)
            inject_into_file admin_user_class_file, after: "class #{PallasTrade.admin_user_class.name} < ApplicationRecord\n" do
              <<-RUBY
    # PallasTrade modules
    include PallasTrade::AdminUserMethods
              RUBY
            end
            gsub_file admin_user_class_file, "< ApplicationRecord", "< PallasTrade.base_class"

            say "Successfully added PallasTrade admin user modules into #{admin_user_class_file}"
          else
            say "Could not locate admin user model file at #{admin_user_class_file}. Please add these lines manually:", :red
            say <<~RUBY
              # PallasTrade modules
              include PallasTrade::AdminUserMethods
            RUBY

            say "Please replace < ApplicationRecord with < PallasTrade.base_class in #{admin_user_class_file}"
          end
        end

        append_file 'config/initializers/PallasTrade.rb' do
          %Q{
            if defined?(Devise) && Devise.respond_to?(:parent_controller)
              Devise.parent_controller = "PallasTrade::BaseController"
            end\n}
        end
      end
    end
  end
end
