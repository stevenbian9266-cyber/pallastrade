pin 'application-pallastrade-adyen', to: 'pallastrade_adyen/application.js', preload: false

pin_all_from PallasTradeAdyen::Engine.root.join('app/javascript/pallastrade_adyen/controllers'),
             under: 'pallastrade_adyen/controllers',
             to:    'pallastrade_adyen/controllers',
             preload: 'application-pallastrade-adyen'
pin "@adyen/adyen-web/auto", to: "@adyen--adyen-web.js" # @6.18.0
