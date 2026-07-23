# PallasTrade Extension

[![Gem Version](https://badge.fury.io/rb/pallastrade_extension.svg)](https://badge.fury.io/rb/pallastrade_extension)

CLI tool for generating and managing PallasTrade Commerce extensions.

## Installation

```bash
gem install pallastrade_extension
```

## Usage

### Create a new extension

```bash
pallastrade-extension create my_extension
```

This creates a `pallastrade_my_extension` directory with a complete extension scaffold including engine setup, tests, CI configuration, and more.

### Check version

```bash
pallastrade-extension version
```

## After generating

```bash
cd pallastrade_my_extension
bundle install
bundle exec rake test_app
bundle exec rspec
```

## Documentation

For more information on developing PallasTrade extensions, see the [PallasTrade Developer Documentation](https://pallastrade.cn/docs/developer).
