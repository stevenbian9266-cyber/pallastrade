module PallasTrade
  module UserApiMethods
    extend ActiveSupport::Concern

    include PallasTrade::UserApiAuthentication
  end
end
