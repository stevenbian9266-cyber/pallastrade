pin 'application-spree-paypal-checkout', to: 'pallastrade_paypal_checkout/application.js', preload: false

pin_all_from SpreePaypalCheckout::Engine.root.join('app/javascript/PALLASTRADE_paypal_checkout/controllers'),
             under: 'pallastrade_paypal_checkout/controllers',
             to: 'pallastrade_paypal_checkout/controllers',
             preload: 'application-spree-paypal-checkout'
