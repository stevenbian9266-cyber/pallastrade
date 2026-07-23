class EnablePolymorphicResourceOwner < ActiveRecord::Migration[5.2]
  def change
    add_column :pallastrade_oauth_access_tokens, :resource_owner_type, :string
    add_column :pallastrade_oauth_access_grants, :resource_owner_type, :string
    change_column_null :pallastrade_oauth_access_grants, :resource_owner_type, false

    add_index :pallastrade_oauth_access_tokens,
              [:resource_owner_id, :resource_owner_type],
              name: 'polymorphic_owner_oauth_access_tokens'

    add_index :pallastrade_oauth_access_grants,
              [:resource_owner_id, :resource_owner_type],
              name: 'polymorphic_owner_oauth_access_grants'

    PallasTrade::OauthAccessToken.reset_column_information
    PallasTrade::OauthAccessToken.update_all(resource_owner_type: PallasTrade.user_class)

    PallasTrade::OauthAccessGrant.reset_column_information
    PallasTrade::OauthAccessGrant.update_all(resource_owner_type: PallasTrade.user_class)
  end
end
