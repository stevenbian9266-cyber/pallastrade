module PallasTrade
  module TestingSupport
    module UrlHelpers
      def spree
        PallasTrade::Core::Engine.routes.url_helpers
      end
    end
  end
end
