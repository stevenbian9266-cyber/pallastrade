# Shared dependencies between storefront and admin
pin '@rails/request.js', to: '@rails--request.js.js', preload: ['application-pallastrade-admin'] # @0.0.8
pin 'tailwindcss-stimulus-components', preload: ['application-pallastrade-storefront', 'application-pallastrade-admin'] # @3.0.4
pin 'stimulus-reveal-controller', preload: ['application-pallastrade-admin'] # @4.1.0
pin '@stimulus-components/auto-submit', to: '@stimulus-components--auto-submit.js', preload: ['application-pallastrade-admin'] # @6.0.0
pin 'stimulus-textarea-autogrow', preload: ['application-pallastrade-admin'] # @4.1.0

pin_all_from PallasTrade::Core::Engine.root.join('app/javascript/pallastrade/core/controllers'),
             under: 'pallastrade/core/controllers',
             to: 'pallastrade/core/controllers',
             preload: ['application-pallastrade-admin']
pin_all_from PallasTrade::Core::Engine.root.join('app/javascript/pallastrade/core/helpers'),
             under: 'pallastrade/core/helpers',
             to: 'pallastrade/core/helpers',
             preload: ['application-pallastrade-storefront', 'application-pallastrade-admin']
