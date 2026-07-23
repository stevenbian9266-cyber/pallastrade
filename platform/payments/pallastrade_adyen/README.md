# PallasTrade Adyen

Official Adyen payments platform integration for [PallasTrade Commerce](https://pallastrade.cn).

## Installation

1. Add this extension to your Gemfile with this line:

    ```ruby
    bundle add pallastrade_adyen
    ```

2. Run the install generator

    ```ruby
    bundle exec rails g pallastrade_adyen:install
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
require 'pallastrade_adyen/factories'
```

## Releasing a new version

```shell
bundle exec gem bump -p -t
bundle exec gem release
```

For more options please see [gem-release README](https://github.com/svenfuchs/gem-release)
