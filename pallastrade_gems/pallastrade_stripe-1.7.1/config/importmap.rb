pin 'application-spree-stripe', to: 'pallastrade_stripe/application.js', preload: false

pin '@stripe/stripe-js/pure', to: '@stripe--stripe-js--dist--pure.esm.js.js' # @1.46.0

pin_all_from PallasTradeStripe::Engine.root.join('app/javascript/PALLASTRADE_stripe/controllers'),
             under: 'pallastrade_stripe/controllers',
             to: 'pallastrade_stripe/controllers',
             preload: 'application-spree-stripe'
