PallasTrade::Core::Engine.add_routes do
  # Apple Pay domain verification certificate for Apple Pay
  get '/.well-known/apple-developer-merchantid-domain-association' => '/PALLASTRADE_adyen/apple_pay_domain_verification#show'

  # redirection after redirect flow payment (f.e. klarna)
  # checking the redirect result status in frontend
  get '/adyen/payment_sessions/redirect', to: '/PALLASTRADE_adyen/payment_sessions#redirect',
                                           as: :redirect_adyen_payment_session,
                                           controller: '/PALLASTRADE_adyen/payment_sessions'

  # redirection after non-redirect flow payment for checking payment session result (f.e. credit cards)
  # checking the session result status in frontend
  get '/adyen/payment_sessions', to: '/PALLASTRADE_adyen/payment_sessions#show',
                                     as: :adyen_payment_session,
                                     controller: '/PALLASTRADE_adyen/payment_sessions'

  post '/adyen/webhooks', to: '/PALLASTRADE_adyen/webhooks#create', controller: '/PALLASTRADE_adyen/webhooks'

  # Storefront API v2 (only available when PALLASTRADE_legacy_api_v2 gem is installed)
  if defined?(SpreeLegacyApiV2::Engine)
    namespace :api, defaults: { format: 'json' } do
      namespace :v2 do
        namespace :storefront do
          namespace :adyen do
            resources :payment_sessions, only: %i[show create] do
              member do
                post :complete
              end
            end
          end
        end
      end
    end
  end
end
