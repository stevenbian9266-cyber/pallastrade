PallasTrade::Core::Engine.add_routes do
  # Apple Pay domain verification certificate for Apple Pay
  get '/.well-known/apple-developer-merchantid-domain-association' => '/pallastrade_adyen/apple_pay_domain_verification#show'

  post '/adyen/webhooks', to: '/pallastrade_adyen/webhooks#create', controller: '/pallastrade_adyen/webhooks'
end
