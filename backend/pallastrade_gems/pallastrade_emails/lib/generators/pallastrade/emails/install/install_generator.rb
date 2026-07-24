require 'rails/generators'
require 'pallastrade/core'

module PallasTrade
  module Emails
    module Generators
      # Kept as a no-op so `rake test_app` and any existing `rails g pallastrade:emails:install`
      # invocations keep working. Mailer previews now ship inside the gem and are served
      # automatically at /rails/mailers — there is nothing left to copy into the host app.
      class InstallGenerator < Rails::Generators::Base
        desc 'No-op. PallasTrade email previews are now bundled and served automatically at /rails/mailers.'

        def notify_previews_are_bundled
          say 'PallasTrade email previews are bundled with pallastrade_emails and served automatically at /rails/mailers — nothing to install.'
        end
      end
    end
  end
end
