module PallasTrade
  class OauthAccessGrant < PallasTrade.base_class
    include ::Doorkeeper::Orm::ActiveRecord::Mixins::AccessGrant

    self.table_name = 'pallastrade_oauth_access_grants'
  end
end
