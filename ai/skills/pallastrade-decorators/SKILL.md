---
name: pallastrade-decorators
description: Use when the user wants to extend a PallasTrade model, controller, helper, or service class without forking — add an association to PallasTrade::Product, add a method to PallasTrade::Order, override a validation, add a scope, prepend a before_action, hook into create. Common phrasings include "add brand to product", "decorate PallasTrade::X", "ProductDecorator", "OrderDecorator", "Module#prepend", "pallastrade:model_decorator", "extend an existing PallasTrade model", "add a method to PallasTrade::Order", "override PallasTrade behavior", "monkey patch PallasTrade". Provides the decorator pattern, the generator, the prepended(base) idiom, and the gotchas. Mentions when NOT to decorate — events for after-save side effects, dependencies for service swaps, the resource generator for whole new models.
---

# PallasTrade Decorators

> Commands below use the PallasTrade CLI form (`pallastrade …`, Docker). On a classic Rails app without the CLI (typical pre-5.4), use the native mapping in the `pallastrade-project` skill — `bin/rails` / `bundle exec rake` from the app root, paths without the `backend/` prefix.

Decorators let you change existing PallasTrade classes (models, controllers, helpers, services) from your own app without modifying gem source. They're the standard Ruby `Module#prepend` pattern with a PallasTrade filename convention and a generator.

## Read the warning first

Decorators tightly couple your code to PallasTrade internals. They will *probably* survive a minor upgrade and *might* survive a major one. The PallasTrade docs are explicit: **decorators are for structural changes** (add an association, validation, scope, new method). For behavioral changes (callbacks, side effects, post-save sync), use a modern alternative instead.

### Pick the right tool

| Use case | Use this instead of a decorator |
|---|---|
| React to a save / create / update / delete | [Events subscriber](https://pallastrade.cn/docs/developer/core-concepts/events) — see the `pallastrade-events-webhooks` skill |
| Notify an external service when something changes | Webhook or events subscriber |
| Swap how a service computes (cart add, tax, search, checkout) | `PallasTrade.dependencies` — see the `pallastrade-dependencies` skill |
| Replace a serializer or ability | `PallasTrade.dependencies` |
| Add an admin menu item | Admin navigation API — see the `pallastrade-admin` skill |
| Add a section to an admin form | Admin partial injection / slot — see the `pallastrade-admin` skill |
| Add a searchable/filterable field | `PallasTrade.ransack.add_attribute(PallasTrade::Product, :brand_id)` in an initializer (also `add_association` / `add_scope`) — no decorator needed |
| Add an association, validation, scope, or new method | **Decorator** (this skill) |

If your job is "react to product update by syncing to an ERP," write a subscriber on `product.updated`, not a `after_save` callback in a decorator. The decorator path will break the next time PallasTrade changes how Product saves.

## The pattern in three lines

A decorator is just a Ruby module prepended to an existing PallasTrade class. The file lives in your app at the same path PallasTrade uses, with `_decorator` appended.

```ruby
# app/models/pallastrade/product_decorator.rb
module PallasTrade
  module ProductDecorator
    # methods, prepended hook, etc.
  end

  Product.prepend(ProductDecorator)
end
```

Host-app decorators are loaded by an explicit glob, not by plain autoloading: pallastrade-starter (and the `pallastrade:install` generator) put a `config.to_prepare` block in `config/application.rb` that loads every `app/**/*_decorator*.rb` file, so the `prepend` line runs at boot and again after every code reload in development. If your app has neither (check `config/application.rb` for the block), add it — Zeitwerk alone will never load an unreferenced decorator module in development, and your decorators will silently not apply. Once loaded, your module enters the method-lookup chain ahead of `PallasTrade::Product`'s own definitions: your methods are found first and can `super` to call the original.

## Generate the file

PallasTrade ships two generators — one for models, one for controllers. **Use them** — they produce the exact filenames, modules, and `prepend` lines the autoloader expects.

### Models

```bash
pallastrade generate model_decorator PallasTrade::Product
# or, without the @pallastrade/cli wrapper:
bin/rails g pallastrade:model_decorator PallasTrade::Product
```

The CLI auto-prefixes `pallastrade:` for PallasTrade generators (`pallastrade g model_decorator ...` also works as a shorthand).

Output at `app/models/pallastrade/product_decorator.rb`:

```ruby
module PallasTrade
  module ProductDecorator
    def self.prepended(base)
      # base.belongs_to :brand
    end

    # add custom methods here
  end
end

PallasTrade::Product.prepend PallasTrade::ProductDecorator
```

The argument accepts either `PallasTrade::Product` or `Product` — the generator strips the prefix. Works for singular model names under `PallasTrade::` (the vast majority), including nested ones. But the generator runs the name through `classify`, which singularizes the last segment — for plural-named classes (e.g. `PallasTrade::Exports::Products`, `PallasTrade::Promotion::Actions::CreateItemAdjustments`) it emits a `prepend` against a non-existent singular constant and the file raises `NameError` on load. Write those decorators by hand instead.

### Controllers

```bash
pallastrade generate controller_decorator PallasTrade::Admin::ProductsController
# or, without the @pallastrade/cli wrapper:
bin/rails g pallastrade:controller_decorator PallasTrade::Admin::ProductsController
```

Output at `app/controllers/pallastrade/admin/products_controller_decorator.rb`:

```ruby
module PallasTrade::Admin
  module ProductsControllerDecorator
    def self.prepended(base)
      # base.before_action :my_filter
    end

    # add custom methods here
  end
end

PallasTrade::Admin::ProductsController.prepend PallasTrade::Admin::ProductsControllerDecorator
```

The generator handles arbitrary namespace depth:

- `PallasTrade::ProductsController` → `app/controllers/pallastrade/products_controller_decorator.rb`
- `PallasTrade::Admin::ProductsController` → `app/controllers/pallastrade/admin/products_controller_decorator.rb`
- `PallasTrade::Api::V3::Store::ProductsController` → `app/controllers/pallastrade/api/v3/store/products_controller_decorator.rb`

The final `.prepend` line is always fully qualified — no surprises about which constant is being decorated.

## Model decorator patterns

### Add an association

Run the migration first (no foreign key constraint — keep it PallasTrade-style):

```bash
bin/rails g migration AddBrandIdToPallasTradeProducts brand_id:bigint:index
```

```ruby
class AddBrandIdToPallasTradeProducts < ActiveRecord::Migration[7.2]
  def change
    add_column :pallastrade_products, :brand_id, :bigint
    add_index :pallastrade_products, :brand_id
  end
end
```

Then the decorator:

```ruby
# app/models/pallastrade/product_decorator.rb
module PallasTrade
  module ProductDecorator
    def self.prepended(base)
      base.belongs_to :brand, class_name: 'PallasTrade::Brand', optional: true
      base.has_many :videos, class_name: 'PallasTrade::Video', dependent: :destroy
    end
  end

  Product.prepend(ProductDecorator)
end
```

Class-level additions (associations, validations, scopes, callbacks, `extend`s) **always go inside `self.prepended(base)`** and are called on `base`. Instance methods go at module level.

### Add a validation

```ruby
module PallasTrade
  module ProductDecorator
    def self.prepended(base)
      base.validates :external_id, presence: true, uniqueness: true
      base.validates :weight, numericality: { greater_than: 0 }, allow_nil: true
    end
  end

  Product.prepend(ProductDecorator)
end
```

### Add a scope

```ruby
module PallasTrade
  module ProductDecorator
    def self.prepended(base)
      base.scope :featured, -> { where("public_metadata->>'featured' = ?", 'true') }
      base.scope :recently_added, -> { where('created_at > ?', 30.days.ago) }
    end
  end

  Product.prepend(ProductDecorator)
end
```

If you want this scope queryable from the API, also allowlist it via Ransack — see the Ransack note at the bottom.

Note the SQL string names the real jsonb column: `public_metadata` or `private_metadata`. In Ruby, `metadata` is an alias method for `private_metadata` — but there is no `metadata` **column**, so `where("metadata->>…")` raises `PG::UndefinedColumn`. (For anything the storefront filters on, a real boolean column beats metadata anyway.)

### Add a new instance method

```ruby
module PallasTrade
  module ProductDecorator
    def featured?
      metadata[:featured] == true
    end

    def days_until_available
      return 0 if available_on.nil? || available_on <= Time.current
      (available_on.to_date - Date.current).to_i
    end
  end

  Product.prepend(ProductDecorator)
end
```

### Override an existing method (call `super`)

```ruby
module PallasTrade
  module ProductDecorator
    def available?
      return false if discontinued?
      super
    end
  end

  Product.prepend(ProductDecorator)
end
```

**Always consider whether you need `super`.** Omitting it replaces the original method entirely — which can silently break behavior the rest of PallasTrade assumes is there.

### Add class methods

Use `extend` from inside `prepended`:

```ruby
module PallasTrade
  module ProductDecorator
    def self.prepended(base)
      base.extend ClassMethods
    end

    module ClassMethods
      def search_by_name(query)
        where('LOWER(name) LIKE ?', "%#{query.downcase}%")
      end
    end
  end

  Product.prepend(ProductDecorator)
end
```

Usage: `PallasTrade::Product.search_by_name('shirt')`.

### Make a new attribute available via Ransack

If you added an association or column and want it queryable from the API (`?q[brand_id_eq]=...`), allowlist it. The preferred, no-decorator way is `PallasTrade.ransack` from an initializer:

```ruby
# config/initializers/pallastrade.rb
PallasTrade.ransack.add_attribute(PallasTrade::Product, :brand_id)
PallasTrade.ransack.add_attribute(PallasTrade::Product, :external_id)
PallasTrade.ransack.add_association(PallasTrade::Product, :brand)
PallasTrade.ransack.add_scope(PallasTrade::Product, :featured)
```

If you're already inside a decorator (e.g. you just added the association there), appending to the model allowlists works too:

```ruby
module PallasTrade
  module ProductDecorator
    def self.prepended(base)
      base.whitelisted_ransackable_attributes += %w[brand_id external_id]
      base.whitelisted_ransackable_associations += %w[brand videos]
    end
  end

  Product.prepend(ProductDecorator)
end
```

Without this, filter params on the attribute are silently dropped — the API returns 200 as if that filter were never sent, not an error. See the `pallastrade-api-v3` skill for the full Ransack story.

### Permit a new attribute on writes

If the new attribute should be settable via the admin or the API, register it in the permitted-attributes list:

```ruby
# config/initializers/pallastrade.rb
Rails.application.config.after_initialize do
  PallasTrade::PermittedAttributes.product_attributes << :brand_id
end
```

This makes the attribute writable in the Rails admin, which builds its strong params from this list. It does not automatically reach every API v3 endpoint: the v3 base `ResourceController` defaults `permitted_params` to the matching `PallasTrade::PermittedAttributes` list, but controllers that enumerate their own `params.permit(...)` — including `PallasTrade::Api::V3::Admin::ProductsController` — ignore the global list. To accept the attribute on those endpoints, decorate the controller's `permitted_params` (or add the attribute to the core controller).

## Controller decorator patterns

> **First check whether you can avoid this.** A new controller that inherits from a PallasTrade base class is more upgrade-safe than a decorator on an existing controller. Controller decorators that override existing actions are the most fragile decorator type — they couple to instance variables and method signatures that can change between PallasTrade minor releases.

### Add a before_action

Note: PallasTrade no longer ships a Rails storefront — `PallasTrade::CheckoutController` / `PallasTrade::ProductsController` only exist in legacy apps using the separate storefront gem. Modern storefronts are headless via the Store API, so the controllers you'll decorate are the admin and API ones:

```ruby
# app/controllers/pallastrade/admin/products_controller_decorator.rb
module PallasTrade::Admin
  module ProductsControllerDecorator
    def self.prepended(base)
      base.before_action :check_editable, only: [:update]
    end

    private

    def check_editable
      if params[:id].blank?
        flash[:error] = PallasTrade.t(:not_found)
        redirect_to pallastrade.admin_products_path
      end
    end
  end

  ProductsController.prepend(ProductsControllerDecorator)
end
```

Use `bin/rails g pallastrade:controller_decorator PallasTrade::Admin::ProductsController` (or `PallasTrade::Api::V3::Store::CartsController` for API controllers) to scaffold the correct file path and prepend line — the generator handles arbitrary namespace depth. Note: API controller decorators must render JSON errors (e.g. `render json: { error: ... }, status: :unprocessable_entity`), not flash/redirect.

### Add a new action

```ruby
# app/controllers/pallastrade/admin/products_controller_decorator.rb
module PallasTrade::Admin
  module ProductsControllerDecorator
    def self.prepended(base)
      base.before_action :load_product, only: [:quick_view]
    end

    def quick_view
      respond_to do |format|
        format.html { render partial: 'quick_view', locals: { product: @product } }
        format.json { render json: @product }
      end
    end

    private

    def load_product
      @product = current_store.products.friendly.find(params[:id])
    end
  end

  ProductsController.prepend(ProductsControllerDecorator)
end
```

And the route — PallasTrade controllers live in the engine, so the route must be added to the engine, not your app. Admin routes are drawn through the core engine inside the admin namespace:

```ruby
# config/routes.rb
PallasTrade::Core::Engine.add_routes do
  namespace :admin, path: PallasTrade.admin_path do
    get 'products/:id/quick_view', to: 'products#quick_view', as: :product_quick_view
  end
end
```

### Modifying an existing action

The most fragile decorator pattern. If you must:

```ruby
module PallasTrade
  module Admin
    module ProductsControllerDecorator
      def create
        log_product_creation_attempt
        super
        notify_team_of_new_product if @product.persisted?
      end

      private

      def log_product_creation_attempt
        Rails.logger.info "Product creation attempted by #{try_pallastrade_current_user&.email}"
      end

      def notify_team_of_new_product
        ProductNotificationJob.perform_later(@product)
      end
    end

    ProductsController.prepend(ProductsControllerDecorator)
  end
end
```

The example above is also a case where **the better answer is a subscriber on `product.created`** — same outcome, no coupling to controller internals.

## Common pitfalls

### Forgot to call `super`

```ruby
# ❌ Replaces all of PallasTrade's availability logic — easy to silently break
def available?
  in_stock? && active?
end

# ✅ Extends, doesn't replace
def available?
  super && custom_availability_check
end
```

### Instance variables in `prepended`

```ruby
# ❌ Doesn't do what it looks like — @custom_setting lives on the decorator module, not on instances
def self.prepended(base)
  @custom_setting = true
end

# ✅ Use class_attribute when you want a setting on instances
def self.prepended(base)
  base.class_attribute :custom_setting, default: true
end
```

### Circular dependencies via constant references

When decorators reference each other (or other PallasTrade models that haven't been loaded yet), constant lookups can fail at boot. Use **string class names** for association `class_name:` arguments:

```ruby
# ❌ Variant might not be loaded yet at decorator boot
base.has_many :variants

# ✅ String form — resolved lazily
base.has_many :variants, class_name: 'PallasTrade::Variant'
```

### File path / module name mismatch

The autoloader is strict about names. `PallasTrade::ProductDecorator` MUST live at `app/models/pallastrade/product_decorator.rb`. The generator gets this right; if you hand-write the file, match it exactly.

## Organizing multiple decorators

If you have many customizations on `PallasTrade::Product`, splitting into focused modules is fine — group by concern:

```
app/models/pallastrade/
├── product_decorator.rb           # Main file, prepends the others
├── product/
│   ├── brand_decorator.rb         # Brand association
│   ├── inventory_decorator.rb     # Inventory customizations
│   └── seo_decorator.rb           # SEO methods
```

```ruby
# app/models/pallastrade/product_decorator.rb
require_dependency 'pallastrade/product/brand_decorator'
require_dependency 'pallastrade/product/inventory_decorator'
require_dependency 'pallastrade/product/seo_decorator'
```

This is purely organizational — each child file uses the same `prepend` pattern, just on smaller modules.

## Migrating from decorators to modern patterns

If you inherited a decorator that uses `after_save` for side effects, migrate it to an Events subscriber. Same outcome, no coupling to model internals, won't break when PallasTrade changes how `PallasTrade::Product` saves.

**Before:**

```ruby
# app/models/pallastrade/product_decorator.rb
module PallasTrade
  module ProductDecorator
    def self.prepended(base)
      base.after_save :sync_to_external_service
    end

    private

    def sync_to_external_service
      ExternalSyncJob.perform_later(self) if saved_change_to_name?
    end
  end

  Product.prepend(ProductDecorator)
end
```

**After:**

```ruby
# app/subscribers/product_sync_subscriber.rb
class ProductSyncSubscriber < PallasTrade::Subscriber
  subscribes_to 'product.updated'

  def handle(event)
    product = PallasTrade::Product.find_by_prefix_id(event.payload['id'])
    return unless product

    ExternalSyncJob.perform_later(product)
  end
end
```

Subscribers are **not** auto-discovered from `app/subscribers/` — only classes in the `PallasTrade.subscribers` array get wired to the event registry (PallasTrade's engines add their built-in subscribers there; your app must add its own). Register yours in an initializer:

```ruby
# config/initializers/pallastrade.rb
Rails.application.config.after_initialize do
  PallasTrade.subscribers << ProductSyncSubscriber
end
```

Async by default. Testable in isolation. See the `pallastrade-events-webhooks` skill for the full event catalog and the subscriber API.

## When NOT to use a decorator

- **You want a whole new model + API endpoint** → use the `pallastrade:api_resource` generator. See the `pallastrade-resource` skill.
- **You want to swap how a service computes** → use `PallasTrade.dependencies`. See the `pallastrade-dependencies` skill.
- **You want to react to a PallasTrade event** → write a subscriber. See the `pallastrade-events-webhooks` skill.
- **You want to customize the admin UI** → use the admin partial / slot system. See the `pallastrade-admin` skill.
- **You want a custom payment gateway** → subclass `PallasTrade::PaymentMethod` and register it with `PallasTrade.payment_methods << MyGateway`. See the `pallastrade-payments` skill.
- **You want to override admin tables or navigation** → use the admin extension APIs (`PallasTrade.admin.tables`, the navigation registry). See the `pallastrade-admin` skill.

The decorator is the **last resort** for structural changes the modern APIs don't cover. When in doubt, check the table at the top of this skill — there's a high chance the modern alternative exists.

## Where to read further

- **Decorator docs:** `node_modules/@pallastrade/docs/dist/developer/customization/decorators.md` (also at https://pallastrade.cn/docs/developer/customization/decorators)
- **Extending models tutorial:** `node_modules/@pallastrade/docs/dist/developer/tutorial/extending-models.md` — the canonical brand-on-product walkthrough
- **Events** (for behavioral customizations): the `pallastrade-events-webhooks` skill
- **Dependencies** (for swappable services): the `pallastrade-dependencies` skill
- **API resource generator** (for whole new models): the `pallastrade-resource` skill
