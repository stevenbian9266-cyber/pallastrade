---
name: pallastrade-extensions
description: Use when the user wants to install a specific third-party PallasTrade gem (Stripe, Adyen, PayPal, i18n, search, social login, etc.), build their own PallasTrade extension to share across apps, or swap a core PallasTrade service via `PallasTrade.dependencies`. Common phrasings include "add Stripe", "install pallastrade_X", "what payment gateways", "create a PallasTrade extension", "build a gem for PallasTrade", "pallastrade_dev_tools", "PallasTrade.dependencies", "service swap". For deciding which customization pattern to use, see the `pallastrade-customization` skill first — extensions are the last two rows of its decision tree and most single-app work doesn't need one.
---

# PallasTrade Extensions

> Commands below use the PallasTrade CLI form (`pallastrade …`, Docker). On a classic Rails app without the CLI (typical pre-5.4), use the native mapping in the `pallastrade-project` skill — `bin/rails` / `bundle exec rake` from the app root, paths without the `backend/` prefix.

This skill covers two distinct things: **installing a third-party PallasTrade gem** (`pallastrade_stripe`, `pallastrade_i18n`, etc.) and **building your own extension** to share across multiple PallasTrade apps. For single-app customization (the 99% case), use the `pallastrade-customization` skill to find the right pattern — usually it's a subscriber, dependency injection, or a decorator, not a gem.

PallasTrade extensions are Rails engines packaged as gems. They mount into the host Rails app the same way PallasTrade itself does. Adding one is a Gemfile entry + a generator run + a migrate.

## Installing an extension

Three steps. Same pattern for every PallasTrade extension. Requires the ejected dev stack: fresh `create-pallastrade-app` projects run a prebuilt image where `backend/` is not mounted into the container — run `pallastrade eject` once first to switch to the bind-mounted dev compose.

```bash
# 1. Add to Gemfile
echo "gem 'pallastrade_reviews'" >> backend/Gemfile

# 2. Install the gem
pallastrade bundle install

# 3. Run the extension's install generator
pallastrade rails g pallastrade_reviews:install
```

The install generator is a **convention** — every PallasTrade extension provides one at `<gem_name>:install`. It typically:
- Copies migrations into your app (`db/migrate/<ts>_<name>.<gem_name>.rb`)
- Adds an initializer (`config/initializers/<gem_name>.rb`)
- Registers itself with `PallasTrade.dependencies` or `PallasTrade.subscribers` if needed
- Sometimes copies admin views or installs admin slot extensions

After the install generator runs, apply migrations and restart:

```bash
pallastrade migrate
pallastrade dev                 # Ctrl+C the running one first; `pallastrade restart` does not reload Gemfile changes
```

## Extension gems bundled with `create-pallastrade-app`

When you scaffold via `npx create-pallastrade-app`, the resulting Gemfile already includes three payment providers plus i18n:

| Gem | What it provides |
|---|---|
| `pallastrade_stripe` | Stripe checkout — payment methods, sessions, webhooks |
| `pallastrade_adyen` | Adyen — drop-in component, methods, webhooks |
| `pallastrade_paypal_checkout` | PayPal Smart Buttons checkout |
| `pallastrade_i18n` | Translations for the admin UI across many locales |

These are commercially-significant integrations. If you remove one from your Gemfile, also strip its admin Settings → Payment methods entry. If you add one to an existing project that wasn't created with `create-pallastrade-app`, follow the standard three-step install above.

## Integrations and community extensions

The maintained integrations list is at `https://pallastrade.cn/docs/integrations` (source: `docs/integrations/integrations.mdx`) — it currently covers Stripe, Adyen, PayPal, RazorPay, Avalara (`pallastrade_avatax`), Meilisearch, Google Analytics / Tag Manager, and Klaviyo.

Beyond that there is a long tail of **legacy community extensions** from the PallasTrade 4.x era — `pallastrade_print_invoice`, `pallastrade_volume_pricing`, `pallastrade_products_qa`, `pallastrade_searchkick`, `pallastrade_easypost`, `pallastrade_shipstation`, `pallastrade_social`, `pallastrade_reviews`, `pallastrade_taxjar`, `pallastrade-product-assembly`, `pallastrade_related_products`, and others. These are not in the current docs and many are unmaintained — before adding one, verify against its GitHub repo that it supports your PallasTrade 5.x version (check the gemspec's `pallastrade_core` constraint and the CHANGELOG), and expect to fork/patch.

Compatibility is per-extension-version — when you upgrade PallasTrade, check each extension's CHANGELOG before bumping.

## `pallastrade_dev_tools` — first install on any project

`pallastrade_dev_tools` packages PallasTrade's test stack for host apps (RSpec, Factory Bot, Capybara, DatabaseCleaner) and loads the factories and helpers that ship inside `pallastrade_core` — PallasTrade's own gems wire those dependencies directly and don't use this gem. Projects scaffolded with `create-pallastrade-app` already include it in the `:development, :test` group; add it yourself only on apps that weren't:

```ruby
# backend/Gemfile
group :development, :test do
  gem 'pallastrade_dev_tools'
end
```

```bash
pallastrade bundle install
pallastrade rails g pallastrade_dev_tools:install   # copies helpers into spec/support/ and enables loading them from rails_helper.rb
```

What it adds:
- Factory Bot factories for every PallasTrade model (loaded via `require 'pallastrade/testing_support/factories'`)
- The `'API v3 Store'` shared context used by API specs (additionally requires `require 'pallastrade/api/testing_support/v3/base'` in the spec file — the install generator does not wire it)
- `stub_authorization!` for admin controller specs

See the `pallastrade-testing` skill for usage patterns.

## Building your own extension

Skip this section unless you're confident your customization belongs as a reusable gem. For one-app changes, put your code directly in `backend/app/` and use subscribers + dependency injection.

If you do need to build an extension:

```bash
gem install pallastrade_extension       # the PallasTrade extension scaffolder
pallastrade-extension simple_sales      # generates ./pallastrade_simple_sales/
cd pallastrade_simple_sales
```

The scaffold produces:

| File | Purpose |
|---|---|
| `lib/pallastrade_simple_sales/engine.rb` | the Rails engine declaration |
| `lib/generators/pallastrade_simple_sales/install/install_generator.rb` | the convention `<name>:install` generator |
| `app/` | your models, controllers, services live here (same `PallasTrade::` namespacing rules) |
| `db/migrate/` | your migrations (copied into the host app by the install generator) |

The engine declaration registers dependencies, subscribers, and admin UI extensions:

```ruby
# lib/pallastrade_simple_sales/engine.rb
module PallasTradeSimpleSales
  class Engine < ::Rails::Engine
    engine_name 'pallastrade_simple_sales'

    initializer 'pallastrade.simple_sales.subscribers' do
      PallasTrade.subscribers << PallasTradeSimpleSales::OrderSubscriber
    end

    initializer 'pallastrade.simple_sales.dependencies' do
      PallasTrade.dependencies do |deps|
        deps.cart_add_item_service = 'PallasTradeSimpleSales::Cart::AddItem'
      end
    end
  end
end
```

For the full tutorial — decorators, controller extensions, model decorators, route additions, testing — see `docs/developer/contributing/creating-an-extension.mdx`.

## Swapping a core service is NOT an extension

A common confusion: "I want my own version of an existing PallasTrade service — should I build an extension?" Almost always no. PallasTrade exposes 70+ swappable core injection points via `PallasTrade.dependencies` (or `PallasTrade.<name> = ...` directly) plus 300+ API injection points (serializers, finders, per-endpoint services) via `PallasTrade.api`. You subclass the default, register the override in `config/initializers/pallastrade.rb`, and PallasTrade calls your service everywhere. No gem packaging required.

```ruby
# config/initializers/pallastrade.rb
PallasTrade.cart_add_item_service = MyApp::Cart::AddItem
```

See the **`pallastrade-dependencies`** skill for the full pattern, the catalog of injection points, and the introspection rake tasks (`pallastrade:dependencies:list`, `pallastrade:dependencies:overrides`, `pallastrade:dependencies:validate`).

Extensions become the right shape when you want to **share** customization (including dependency overrides) across multiple PallasTrade apps — the extension's engine declaration registers the overrides at boot, so any host app that bundles the gem gets the swap automatically.

## When an extension is and isn't the right shape

Extensions are the wrong tool for most single-app customization. They make sense when:

- You maintain **multiple PallasTrade apps** and want to share customization between them.
- You're building **something the PallasTrade community would benefit from** (an open-source gem).

For one app: put the code directly in `app/` (subscribers, decorators, services, controllers). No extension overhead. See the `pallastrade-customization` skill for the full routing table; this skill picks up at "yes, I really want a gem."

## Common gotchas with extensions

- **Migrations don't auto-apply.** Each install generator copies migrations into `backend/db/migrate/`; you must run `pallastrade migrate` after. `pallastrade upgrade` bundle-updates every pallastrade-prefixed gem (extensions included), but its migration-install step (`pallastrade:install:migrations`) only covers PallasTrade core — and `pallastrade migrate` has the same limitation. After an extension version bump, re-run the extension's install generator (or `pallastrade rails railties:install:migrations`) to copy any new extension migrations, then `pallastrade migrate` to apply them.
- **Initializers can drift across upgrades.** When you bump an extension version, the initializer it generated may need new config keys. Check the extension's CHANGELOG before upgrading.
- **Extensions ship migrations with the engine name as a suffix** in the host app (e.g. `db/migrate/20260427130753_create_pallastrade_paypal_checkout_orders.pallastrade_paypal_checkout.rb`; PallasTrade core's own migrations use `.pallastrade.rb`). The suffix records which engine a migration was copied from: the install tasks use it to skip already-copied migrations, and PallasTrade's boot-time check uses it to warn when an engine's migrations are missing. Don't rename them.
- **Decorators in extensions** can collide with decorators in your app. If two reopen `PallasTrade::Order` and define a method with the same name, last-loaded wins (load order is alphabetical by gem name). Avoid decorating the same model in two places.
- **Engine-level subscribers** registered in an `initializer 'pallastrade.<name>.subscribers'` block are appended once at boot. Subscriber code hot-reloads — PallasTrade resets and re-registers all subscribers on each code reload. Only changes to the registration itself (the engine initializer) need a server restart.

## Where to read further

- **Integrations catalog:** https://pallastrade.cn/docs/integrations (source: `docs/integrations/integrations.mdx`)
- **Building extensions tutorial:** `docs/developer/contributing/creating-an-extension.mdx` (full walkthrough — generates a sale-price extension)
- **Customization patterns:** `docs/developer/customization/quickstart.mdx`, `docs/developer/customization/decorators.mdx`, `docs/developer/customization/dependencies.mdx`
- **Events for sync/notify scenarios:** the `pallastrade-events-webhooks` skill
