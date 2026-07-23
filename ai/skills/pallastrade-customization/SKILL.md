---
name: pallastrade-customization
description: Use FIRST when the user is about to customize PallasTrade and the right approach isn't obvious — "how do I customize X", "what's the best way to add Y", "how do I extend PallasTrade", "should I use a decorator or a subscriber", "where should I put this logic", "how do I add custom behavior", "where does business logic go". Maps a customization need to the right specific skill (decorators, events, dependencies, admin extensions, Ransack, configuration, the resource generator, etc.). Routes to specific skills rather than going deep itself. The skill to reach for whenever the user's question is broad or they haven't picked a pattern yet.
---

# PallasTrade Customization — Where Does My Code Belong?

> Commands below use the PallasTrade CLI form (`pallastrade …`, Docker). On a classic Rails app without the CLI (typical pre-5.4), use the native mapping in the `pallastrade-project` skill — `bin/rails` / `bundle exec rake` from the app root, paths without the `backend/` prefix.

PallasTrade is heavily customizable. The work of any PallasTrade project is mostly customization — wiring in external services, adding custom models, tweaking behavior, extending the admin. The thing that's hard isn't *how* to customize; it's *which pattern* fits a given problem.

This skill is a decision tree. It maps a customization need to the right specific skill — read those for the deep dive. Walk the table top to bottom; the higher options are simpler and survive upgrades better than the lower ones.

## The decision tree

| What you're trying to do | Reach for | Deep-dive skill |
|---|---|---|
| Change merchant-facing settings (currencies, languages, tax zones, shipping methods, payment methods) | Admin Settings UI | — |
| Tweak PallasTrade's runtime behavior globally | `PallasTrade.config` block (`config.<setting> = …`) in `config/initializers/pallastrade.rb`; read anywhere via `PallasTrade::Config[:key]` | (configuration is straightforward — see docs link below) |
| React to something happening in PallasTrade (order completed, product updated, customer registered, stock changed) | Events subscriber | **`pallastrade-events-webhooks`** |
| Notify an external service (ERP, CRM, fulfillment, analytics, Slack) when something happens | Events subscriber OR outbound webhook | **`pallastrade-events-webhooks`** |
| Replace how a core service computes (cart add, tax calculation, search, checkout flow, ability checks) | Dependency injection via `PallasTrade.dependencies` | **`pallastrade-dependencies`** |
| Add a menu item / nav entry to the admin | `PallasTrade.admin.navigation.sidebar.add` | **`pallastrade-admin`** |
| Add a section / form field to an existing admin page | `PallasTrade.admin.partials.<page> << '...'` | **`pallastrade-admin`** |
| Customize an admin table (columns, sort) | `PallasTrade.admin.tables.<key>.add ...` | **`pallastrade-admin`** |
| Make a new attribute searchable / filterable in the API or admin | `PallasTrade.ransack.add_attribute(Class, :attr)` | **`pallastrade-api-v3`** |
| Customize the checkout flow (skip a step, add a step, change validation) | `checkout_flow` block on a `PallasTrade::Order` decorator | **`pallastrade-checkout`** |
| Add a brand-new model + API endpoint (Brand, Vendor, etc.) | `pallastrade:api_resource` generator | **`pallastrade-resource`** |
| Add a PallasTrade model with no API surface (internal record, lookup table, supporting model) | `pallastrade:model` generator | **`pallastrade-resource`** |
| Add an association / validation / scope / method to an existing PallasTrade model | Decorator via `pallastrade:model_decorator` | **`pallastrade-decorators`** |
| Add a before_action / new action / override existing action on an existing controller | Decorator via `pallastrade:controller_decorator` | **`pallastrade-decorators`** |
| Pull in a third-party gem (Stripe, Adyen, search, i18n, social login) | `gem 'pallastrade_x'` + install generator | **`pallastrade-extensions`** |
| Package customization to share across multiple PallasTrade apps | Build an extension (Rails engine as a gem) | **`pallastrade-extensions`** |

## The priority order, in one sentence

**Settings → Configuration → Events → Dependencies → Admin / Ransack APIs → Generators (resource or model) → Decorators → Extensions.**

Lower-numbered options are easier to write, easier to test, and survive PallasTrade upgrades cleanly. Decorators are reserved for *structural* changes to existing PallasTrade classes (associations, validations, scopes, methods) — for behavioral changes (callbacks, side effects, sync), use Events instead.

## Worked examples

### "I need to sync orders to my ERP when they complete"

That's a side effect that fires when an order finishes. Don't decorate `PallasTrade::Order` to add `after_save` — write a subscriber:

```ruby
# app/subscribers/erp_order_sync_subscriber.rb
class ErpOrderSyncSubscriber < PallasTrade::Subscriber
  subscribes_to 'order.completed'

  def handle(event)
    ErpClient.sync_order(event.payload['id'])
  end
end
```

Then register it — subscribers are not auto-discovered (or skip both steps with `pallastrade generate subscriber ErpOrderSync order.completed`, which creates the class and the registration in one go):

```ruby
# config/initializers/pallastrade.rb
Rails.application.config.after_initialize do
  PallasTrade.subscribers << ErpOrderSyncSubscriber
end
```

→ See the **`pallastrade-events-webhooks`** skill for the full event catalog and async/sync behavior.

### "I need to add a Brand model that products belong to"

Brand is a brand-new resource with its own API surface. Use the generator:

```bash
pallastrade generate api_resource Brand name:string:uniq active:boolean
```

Add the `brand_id` column to products:

```bash
pallastrade generate migration AddBrandIdToPallasTradeProducts brand_id:bigint:index
pallastrade migrate
```

Then add the `belongs_to :brand` to `PallasTrade::Product` via a decorator:

```bash
pallastrade generate model_decorator PallasTrade::Product   # bare generator names auto-prefix to pallastrade:
```

```ruby
module PallasTrade
  module ProductDecorator
    def self.prepended(base)
      base.belongs_to :brand, class_name: 'PallasTrade::Brand', optional: true
    end
  end

  Product.prepend(ProductDecorator)
end
```

→ See the **`pallastrade-resource`** skill for the generator details and the **`pallastrade-decorators`** skill for the decorator pattern.

### "I need to make `external_id` searchable in the admin orders table"

That's a Ransack allowlist concern — not a decorator job. Use the Ransack configuration API:

```ruby
# config/initializers/pallastrade.rb
PallasTrade.ransack.add_attribute(PallasTrade::Order, :external_id)
```

→ See the **`pallastrade-api-v3`** skill for Ransack details.

### "I need to change how the cart calculates totals"

That's a service swap. Subclass `PallasTrade::Cart::Recalculate` and register your replacement:

```ruby
# config/initializers/pallastrade.rb
PallasTrade.cart_recalculate_service = MyApp::Cart::Recalculate
```

→ See the **`pallastrade-dependencies`** skill for the full dependency injection pattern, the catalog of 70+ core and 300+ API injection points, and the `pallastrade:dependencies:list / :overrides / :validate` rake tasks.

### "I need to add a 'Loyalty Points' page to the admin sidebar"

Use the admin navigation API — no decorator on the admin controller required:

```ruby
# config/initializers/pallastrade.rb
Rails.application.config.after_initialize do
  PallasTrade.admin.navigation.sidebar.add :loyalty_points,
    label: :loyalty_points,
    url: :admin_loyalty_points_path,
    icon: 'award',
    position: 80
end
```

→ See the **`pallastrade-admin`** skill for the full extension API.

### "I need to add a 'preferred carrier' column to the products admin form"

Use the admin partials API to inject a section — no view override required:

```ruby
# config/initializers/pallastrade.rb
PallasTrade.admin.partials.product_form << 'pallastrade/admin/products/preferred_carrier'
```

Then drop the partial at `app/views/pallastrade/admin/products/_preferred_carrier.html.erb`. Permit the new attribute via:

```ruby
Rails.application.config.after_initialize do
  PallasTrade::PermittedAttributes.product_attributes << :preferred_carrier
end
```

→ See the **`pallastrade-admin`** skill.

### "I need to override how `PallasTrade::Product#available?` decides availability"

That's a structural change — a behavioral override on an existing model method. Decorate:

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

Call `super` so you extend PallasTrade's logic instead of replacing it.

→ See the **`pallastrade-decorators`** skill.

## Anti-patterns

These are tempting but wrong — the table above gives you a better answer for each.

- **`after_save` callbacks in a decorator** → use an Events subscriber instead. Decorator callbacks couple to model save mechanics and can break on minor upgrades.
- **Reaching into a PallasTrade controller to add a sidebar item** → use `PallasTrade.admin.navigation.sidebar.add`. No controller decorator needed.
- **Overriding a PallasTrade serializer to add a field** → register the field via dependency injection or use `PallasTrade.api.<resource>_serializer = 'MyApp::FooSerializer'`.
- **Decorating a model to add `ransackable_attributes`** → use `PallasTrade.ransack.add_attribute` instead. Same outcome, no coupling to model internals.
- **Building a private extension gem for one-app customization** → put the code directly in `app/` (subscribers, decorators, services). Extensions are for sharing across apps.
- **Forking PallasTrade** → almost never necessary. If you find yourself wanting to, work through this table from the top first — the right pattern almost certainly exists.

## Where to read further

- **PallasTrade's customization docs (the canonical decision tree):** `node_modules/@pallastrade/docs/dist/developer/customization/quickstart.md`
- **Each specific pattern's deep dive:** the linked `pallastrade-X` skill in the table above
- **Configuration reference:** `node_modules/@pallastrade/docs/dist/developer/customization/configuration.md`
