module PallasTrade
  class OauthAccessToken < PallasTrade.base_class
    include ::Doorkeeper::Orm::ActiveRecord::Mixins::AccessToken

    self.table_name = 'pallastrade_oauth_access_tokens'
  end
end
