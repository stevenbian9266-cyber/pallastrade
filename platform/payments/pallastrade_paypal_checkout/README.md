# PallasTrade PayPal Checkout

This is the official PayPal Checkout extension for [PallasTrade Commerce](https://pallastrade.cn).

This PayPal Checkout integration is bundled in the [PallasTrade Starter](https://github.com/stevenbian9266-cyber/pallastrade/) for your development convenience.

Or you could follow the [installation instructions](https://pallastrade.cn/docs/integrations/payments/paypal).

If you like what you see, consider giving this repo a GitHub star :star:

Thank you for supporting PallasTrade open-source :heart:

## Installation

1. Add this extension to your Gemfile with this line:

    ```ruby
    bundle add pallastrade_paypal_checkout
    ```

2. Run the install generator

    ```ruby
    bundle exec rails g pallastrade_paypal_checkout:install
    ```

3. Restart your server

  If your server was running, restart it so that it can find the assets properly.

## Developing

1. Create a dummy app

    ```bash
    bundle update
    bundle exec rake test_app
    ```

2. Add your new code
3. Run tests

    ```bash
    bundle exec rspec
    ```

When testing your applications integration with this extension you may use it's factories.
Simply add this require statement to your spec_helper:

```ruby
require 'pallastrade_paypal_checkout/factories'
```

## Releasing a new version

```shell
bundle exec gem bump -p -t
bundle exec gem release
```

For more options please see [gem-release README](https://github.com/svenfuchs/gem-release)
