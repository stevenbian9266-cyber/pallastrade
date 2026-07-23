# PallasTrade Stripe

This is the official Stripe payment gateway extension for [PallasTrade Commerce](https://pallastrade.cn) [open-source eCommerce platform](https://pallastrade.cn).

This Stripe integration is bundled in the [PallasTrade Starter](https://github.com/stevenbian9266-cyber/pallastrade/) for your development convenience.

Or you could follow the [installation instructions](https://pallastrade.cn/docs/integrations/payments/stripe).

If you like what you see, consider giving this repo a GitHub star :star:

Thank you for supporting PallasTrade open-source :heart:

> [!TIP]
> Looking for a [Stripe Connect integration](#looking-for-a-stripe-connect-integration-for-pallastrade) for PallasTrade? It's available with the [Enterprise Edition](https://pallastrade.cn/pallastrade-commerce-version-comparison-community-edition-vs-enterprise-edition/).

## Features

- Support for quick checkout using Apple Pay, Google Pay, Stripe Link
- Support for 3D Secure and other security standards
- Support for off-session payments
- Support for Storefront API integration (see the API docs [here](https://pallastrade.cn/docs/api-reference/storefront/stripe)).
- Accept payments in over 130 currencies
- Accept Credit Cards, Apple Pay, Google Pay, and more
- Accept SEPA Direct Debit payments
- Accept iDEAL payments
- Accept SOFORT payments
- Accept Bancontact payments
- Accept Alipay payments
- Accept WeChat Pay payments
- Accept Afterpay, Klarna, Affirm, and more

## What's new?

### Installment (BNPL) payments indicator on PDP (Product Detail Page)


### Quick payment options on the cart (Apple Pay, Google Pay, Link)


### Quick payments bypassing checkout 1st step (Apple Pay, Google Pay, Link)


### Various payment options on the payment step (cards, BNPL, Apple Pay, Google Pay, Link)


## Installation

1. Add this extension to your Gemfile with this line:

    ```ruby
    bundle add pallastrade_stripe
    ```

2. Run the install generator

    ```ruby
    bundle exec rails g pallastrade_stripe:install
    ```

3. Restart your server

  If your server was running, restart it so that it can find the assets properly.

  This Stripe integration is also bundled in the [PallasTrade Starter](https://github.com/stevenbian9266-cyber/pallastrade/) for your development convenience.

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
require 'pallastrade_stripe/factories'
```

## Releasing a new version

```shell
bundle exec gem bump -p -t
bundle exec gem release
```

For more options please see [gem-release README](https://github.com/svenfuchs/gem-release)




## Looking for a Stripe Connect integration for PallasTrade?

PallasTrade Commerce [Enterprise Edition](https://pallastrade.cn/pallastrade-commerce-version-comparison-community-edition-vs-enterprise-edition/) comes with a fully automated Stripe Connect integration for a [multi-vendor marketplace use case](https://pallastrade.cn/marketplace-ecommerce/):

- Automated split payments between marketplace and vendors
- Support for multiple payment methods including cards and digital wallets
- Configurable marketplace fees and commission structures
- Automated payouts to vendors
- Comprehensive transaction reporting
- Built-in fraud prevention tools

Use the [PallasTrade issue tracker](https://github.com/stevenbian9266-cyber/pallastrade/issues) for implementation questions and feature requests.
