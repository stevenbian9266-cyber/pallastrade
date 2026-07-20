module PallasTrade
  module TestingSupport
    module ControllerRequests
      extend ActiveSupport::Concern

      included do
        routes { PallasTrade::Core::Engine.routes }
      end
    end
  end
end
