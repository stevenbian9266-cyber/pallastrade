# PallasTrade Developer Tools

This is a PallasTrade development tools gem. It helps you work with PallasTrade applications, both extensions and standard Rails applications.

## Installation

Add it to your `Gemfile`:

```ruby
gem 'pallastrade_dev_tools', group: [:development, :test]
```

Run:

```bash
bundle install
```

And finally run the generator:

```bash
bundle exec rails g pallastrade_dev_tools:install
```

## Configuring

If you want to disable Simplecov set the `pallastrade_dev_tools_DISABLE_SIMPLECOV` ENV variable to any value.

## Contributing

If you'd like to contribute, please take a look at the
[instructions](CONTRIBUTING.md) for installing dependencies and crafting a good
pull request.
