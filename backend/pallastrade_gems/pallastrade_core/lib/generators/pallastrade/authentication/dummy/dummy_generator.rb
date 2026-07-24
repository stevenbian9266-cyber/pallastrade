require 'rails/generators'

module PallasTrade
  module Authentication
    class DummyGenerator < Rails::Generators::Base
      desc 'Set up a PallasTrade installation with dummy authentication for testing. Creates a separate pallastrade_admin_users table.'

      def self.source_paths
        paths = superclass.source_paths
        paths << File.expand_path('templates', __dir__)
        paths.flatten
      end

      def create_authentication_helpers
        template 'authentication_helpers.rb.tt', 'lib/pallastrade/authentication_helpers.rb'
      end

      def configure_authentication_helpers
        file_action = File.exist?('config/initializers/PallasTrade.rb') ? :append_file : :create_file
        send(file_action, 'config/initializers/PallasTrade.rb') do
          <<~RUBY

            Rails.application.config.to_prepare do
              require_dependency 'pallastrade/authentication_helpers'
            end
          RUBY
        end
      end

      def create_admin_users_migration
        # Use a fixed early timestamp (20210913) to ensure this migration runs BEFORE
        # any PallasTrade core migrations that reference pallastrade_admin_users table.
        # The earliest such migration is 20250122113708_add_first_and_last_name_to_pallastrade_admin_class.rb
        # We use a timestamp before the main PallasTrade migration (20210914000000_pallastrade_four_three.rb)
        migration_file = File.join('db', 'migrate', '20210913000000_create_pallastrade_admin_users.rb')

        # Skip if migration already exists
        return if File.exist?(migration_file) || migration_exists?('create_pallastrade_admin_users')

        template 'create_pallastrade_admin_users.rb.tt', migration_file
      end

      private

      def migration_exists?(name)
        Dir.glob(File.join('db', 'migrate', "*_#{name}.rb")).any?
      end

      def migration_version
        "[#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}]"
      end
    end
  end
end
