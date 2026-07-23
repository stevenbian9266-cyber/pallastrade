require 'rails/generators'

module PallasTradeExtension
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)

      desc 'Installs PallasTrade Extension CLI binstub into your application'

      def create_binstub
        template 'bin/pallastrade-extension', 'bin/pallastrade-extension'
        chmod 'bin/pallastrade-extension', 0o755
      end

      def show_post_install_message
        say_status :installed, 'bin/pallastrade-extension'
        say ''
        say 'You can now run PallasTrade Extension commands using:'
        say '  bin/pallastrade-extension version'
        say '  bin/pallastrade-extension create my_extension'
        say ''
      end
    end
  end
end
