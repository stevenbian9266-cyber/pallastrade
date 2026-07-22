module PallasTradePosts
  module Generators
    class InstallGenerator < ::Rails::Generators::Base
      desc 'Install PallasTrade Posts — creates initializer and migrations'
      source_root File.expand_path('templates', __dir__)

      def install_migrations
        # No-op: minimal fixture gem for extension testing
      end
    end
  end
end
