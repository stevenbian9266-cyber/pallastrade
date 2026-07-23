# PallasTrade Commerce Backend

This is a Rails application powered by [PallasTrade Commerce](https://pallastrade.cn).

## PallasTrade Documentation

If `@pallastrade/docs` is installed (via the parent project's `package.json`), full developer docs are at:
`../node_modules/@pallastrade/docs/dist/`

Key resources:
- `dist/developer/core-concepts/` — Products, orders, payments, inventory, etc.
- `dist/developer/customization/` — Decorators, extensions, configuration, dependencies
- `dist/api-reference/store.yaml` — OpenAPI 3.0 spec with all Store API endpoints, parameters, and response schemas. Read this when working on API integrations or building against the Store API.

Otherwise, refer to:
- https://pallastrade.cn/docs/llms.txt - links to all documentation pages in markdown
- https://pallastrade.cn/docs/api-reference/store.yaml - Store API OpenAPI 3.0 spec

## Architecture

- Rails app with PallasTrade engines mounted at `/`
- Admin dashboard at `/admin`
- Store API v3 at `/api/v3/store/`
- Admin API v3 at `/api/v3/admin/`
- Background jobs via Sidekiq at `/sidekiq`
- Search via Meilisearch (when `MEILISEARCH_URL` is set)

## Key Files

| File | Purpose |
|------|---------|
| `config/initializers/pallastrade.rb` | PallasTrade configuration, dependencies, permissions |
| `config/routes.rb` | Route mounting and authentication |
| `Gemfile` | PallasTrade gem versions and extensions |
| `.env` | Environment variables (`PALLASTRADE_PATH` for local dev) |

## Customization Patterns

MUST use this in this order — decorators should be a last resort as they couple your code to PallasTrade internals and make upgrades harder.

### 1. Events & Subscribers (preferred for side effects)

React to model changes without touching PallasTrade source. Use for syncing to external services, sending notifications, updating caches, etc.

```ruby
# app/subscribers/pallastrade/my_order_subscriber.rb
module MyApp
  class OrderSubscriber < PallasTrade::Subscriber
    subscribes_to 'order.complete'

    def handle(event)
      order = PallasTrade::Order.find_by_prefix_id(event.payload['id'])
      ExternalService.notify(order)
    end
  end
end
```

Register in `config/initializers/pallastrade.rb`:

```ruby
Rails.application.config.after_initialize do
  PallasTrade.subscribers << MyApp::OrderSubscriber
end
```

### 2. Swapping Services (Dependencies)

Create a new service inheritting from PallasTrade service, eg.

```ruby
module MyApp
  module Cart
    class AddItem < PallasTrade::Cart::AddItem
      def call(order:, variant:, quantity: nil, metadata: {}, public_metadata: {}, private_metadata: {}, options: {})
        ApplicationRecord.transaction do
          run :add_to_line_item
          run :my_app_custom_logic_here
          run PallasTrade.cart_recalculate_service
        end
      end
      
      def my_app_custom_logic_here
        # ...
      end
    end
  end
end
```

Regiser in `config/initializers/pallastrade.rb`:

```ruby
PallasTrade.dependencies do |dependencies|
  dependencies.cart_add_item_service = 'MyApp::Cart::AddItem'
end
```

### 3. Adding Extensions

Add to `Gemfile`

```ruby
gem 'pallastrade_stripe'
```

Run `bundle install`

Run extension installator. eg `bin/rails g pallastrade_stripe:install`
Convention is `bin/rails g <extension_name>:install`

### 4. Decorators (last resort)

Only use for structural changes (adding associations, validations, scopes). Avoid for callbacks and side effects — use subscribers instead.

```ruby
# app/models/pallastrade/product_decorator.rb
module PallasTrade
  module ProductDecorator
    def self.prepended(base)
      base.has_many :reviews, class_name: 'MyApp::Review', dependent: :destroy
      base.validates :custom_field, presence: true
    end
  end

  Product.prepend ProductDecorator
end
```

## Development

```bash
bin/setup              # Install dependencies, prepare database, index search
bin/dev                # Start all processes (web, admin CSS watcher, Sidekiq)
bin/rails console      # Rails console
bin/rails db:migrate   # Run migrations
bin/rails db:seed      # Seed the databases
```

## Coding Conventions

- All custom code goes in `app/` — never modify gem source
- Use decorators in `app/models/pallastrade/` for model extensions
- Use `PallasTrade.user_class` / `PallasTrade.admin_user_class` — never reference `PallasTrade::User` directly
- All PallasTrade models are namespaced under `PallasTrade::` (e.g., `PallasTrade::Product`, `PallasTrade::Order`)
- Use `PallasTrade::Current.store`, `PallasTrade::Current.currency`, `PallasTrade::Current.locale` for request context
- Prefixed IDs in API (e.g., `prod_86Rf07xd4z`) — never expose raw database IDs
- Events system for side effects: `order.publish_event('order.completed')`
- CanCanCan for authorization, Ransack for filtering, Pagy for pagination

## Testing

Native (host Ruby):

```bash
bundle exec rspec                           # Full test suite
bundle exec rspec spec/models/              # Model specs only
bundle exec rspec spec/models/my_model.rb   # Single file
```

Docker (via `@pallastrade/cli`): `pallastrade rspec …` runs the same commands inside the web container with `RAILS_ENV=test`, against the `pallastrade_test` database. First run: `pallastrade rails db:test:prepare`.
