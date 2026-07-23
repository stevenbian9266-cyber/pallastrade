module PallasTrade
  module TestingSupport
    module UrlHelpers
      def pallastrade
        PallasTrade::Core::Engine.routes.url_helpers
      end
    end
  end
end
