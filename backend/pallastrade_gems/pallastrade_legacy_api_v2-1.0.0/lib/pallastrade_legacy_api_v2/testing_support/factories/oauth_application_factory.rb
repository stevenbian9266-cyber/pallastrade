FactoryBot.define do
  factory :oauth_application, class: PallasTrade::OauthApplication do
    name { 'Test Application' }
    redirect_uri { '' }
    scopes { '' }
  end
end
