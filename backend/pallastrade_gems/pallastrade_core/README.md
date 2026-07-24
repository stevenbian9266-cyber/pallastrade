# PallasTrade Core

[![Gem Version](https://badge.fury.io/rb/pallastrade_core.svg)](https://badge.fury.io/rb/pallastrade_core)

PallasTrade Core is the foundation of PallasTrade Commerce, containing all the essential models, services, and business logic that power an e-commerce application.

## Overview

This gem provides:

- **Domain Models** - Products, Variants, Orders, Payments, Shipments, Taxons, Stores, and more
- **Services** - Cart operations, checkout flows, order management, inventory handling
- **State Machines** - Order and payment state management
- **Events System** - Publish/subscribe architecture for loose coupling
- **Dependencies Injection** - Swappable service implementations via `PallasTrade::Dependencies`
- **Permissions** - CanCanCan-based authorization with Permission Sets

## Installation

This gem is included in every PallasTrade installation. No additional steps are required.

## Key Components

### Models

All models are namespaced under `PallasTrade::` and include:

- `PallasTrade::Product` / `PallasTrade::Variant` - Product catalog
- `PallasTrade::Order` / `PallasTrade::LineItem` - Order management
- `PallasTrade::Payment` / `PallasTrade::PaymentMethod` - Payment processing
- `PallasTrade::Shipment` / `PallasTrade::ShippingMethod` - Shipping and fulfillment
- `PallasTrade::Taxon` / `PallasTrade::Taxonomy` - Product categorization
- `PallasTrade::Store` - Multi-store support
- `PallasTrade::Promotion` - Promotions and discounts
- `PallasTrade::GiftCard` - Gift card functionality

### Services

Services follow a consistent interface pattern and are located in `app/services/pallastrade/`:

```ruby
# Add item to cart
PallasTrade.cart_add_item_service.call(
  order: order,
  variant: variant,
  quantity: 1
)
```

### Events System

PallasTrade uses an event-driven architecture for decoupling components:

```ruby
# Publishing events
order.publish_event('order.completed')

# Subscribing to events
module PallasTrade
  module MySubscriber
    include PallasTrade::Event::Subscriber

    event_action :order_completed

    def order_completed(event)
      order = event.payload[:order]
      # Handle the event
    end
  end
end
```

### Dependencies

Swap out default implementations with custom services:

```ruby
# config/initializers/pallastrade.rb
PallasTrade::Dependencies.cart_add_item_service = 'MyCustom::CartAddItem'
```

## Configuration

Configure PallasTrade in an initializer:

```ruby
# config/initializers/pallastrade.rb
PallasTrade.config do |config|
  config.currency = 'USD'
  config.default_country_iso = 'US'
end
```

## Testing

PallasTrade Core includes testing support utilities:

```ruby
# spec/rails_helper.rb
require 'pallastrade/testing_support/factories'
require 'pallastrade/testing_support/authorization_helpers'
```

To run the test suite:

```bash
cd core
bundle exec rake test_app  # First time only
bundle exec rspec
```

## Documentation

- [Official Documentation](https://pallastrade.cn/docs/)
- [API Reference](https://pallastrade.cn/docs/api-reference)
- [Guides](https://pallastrade.cn/docs/developer)