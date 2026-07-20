pin 'application-spree-adyen', to: 'pallastrade_adyen/application.js', preload: false

pin_all_from SpreeAdyen::Engine.root.join('app/javascript/PALLASTRADE_adyen/controllers'),
             under: 'pallastrade_adyen/controllers',
             to:    'pallastrade_adyen/controllers',
             preload: 'application-spree-adyen'
pin "@adyen/adyen-web/auto", to: "@adyen--adyen-web.js" # @6.18.0
