pin 'application-pallastrade-paypal-checkout', to: 'pallastrade_paypal_checkout/application.js', preload: false

pin_all_from PallasTradePaypalCheckout::Engine.root.join('app/javascript/pallastrade_paypal_checkout/controllers'),
             under: 'pallastrade_paypal_checkout/controllers',
             to: 'pallastrade_paypal_checkout/controllers',
             preload: 'application-pallastrade-paypal-checkout'
