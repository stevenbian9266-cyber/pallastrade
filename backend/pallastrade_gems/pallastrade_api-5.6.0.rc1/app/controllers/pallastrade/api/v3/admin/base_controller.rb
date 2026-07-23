module PallasTrade
  module Api
    module V3
      module Admin
        class BaseController < PallasTrade::Api::V3::BaseController
          include PallasTrade::Api::V3::AdminAuthentication
          include PallasTrade::Api::V3::ScopedAuthorization

          before_action :authenticate_admin!
        end
      end
    end
  end
end
