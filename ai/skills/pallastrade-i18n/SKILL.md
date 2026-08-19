---
name: pallastrade-i18n
description: Use when the user is translating PallasTrade — adding a new locale, translating product names/descriptions, fixing missing translations, configuring RTL languages, building a multilingual storefront, working with Mobility, or wrangling PallasTrade.t / I18n.t key lookups. Common phrasings include "add Spanish to PallasTrade", "translate products", "Mobility", "translation tables", "RTL", "missing translation", "PallasTrade.t", "fallback locale", "translated columns", "translation admin". Covers both UI strings (config/locales/*.yml) and data translations (Mobility on Product, Taxon, etc.).
---

# PallasTrade I18n + Translations

Two distinct translation surfaces, each with its own mechanism:

| What | Mechanism | Where it lives |
|---|---|---|
| **UI strings** (labels, buttons, errors, emails) | Standard Rails I18n + `PallasTrade.t` | `config/locales/<locale>.yml` |
| **Data** (product names, category names, descriptions) | [Mobility gem](https://github.com/shioyama/mobility) translation tables | `pallastrade_<model>_translations` tables |

You need both for a multilingual store. UI strings are about how the app speaks; data translations are about what merchant content the customer sees.

## UI strings — `PallasTrade.t` and the YAML files

Every PallasTrade gem ships its own English locale file. `PallasTrade.t` looks up a key scoped under `pallastrade.*` in the active locale:

```ruby
PallasTrade.t(:save)                             # => "Save"
PallasTrade.t('i18n.this_file_language')         # => "English (US)"
PallasTrade.t(:paid, scope: 'payment_states')    # => "Paid"
PallasTrade.t(:missing_key, default: 'Fallback') # => "Fallback"
```

In views / helpers, the shorthand is just `PallasTrade.t(...)`. In ERB templates, you can also use `<%= t('.relative_key') %>` for lazy lookup based on the controller + action name (standard Rails).

### Adding a new UI language

1. **Install the translations gem** (community-maintained):

   ```ruby
   # Gemfile
   gem 'pallastrade_i18n'   # ships translations for 40+ locales
   ```

   This adds `config/locales/<locale>.yml` files for every PallasTrade gem in the bundle.

2. **Add the locale to your store's supported list:**

   ```ruby
   # backend/config/initializers/pallastrade.rb
   I18n.available_locales = %i[en es fr de it ja]
   I18n.default_locale = :en
   ```

3. **(Optional) Add the locale to the relevant market's supported_locales** so the storefront language switcher offers it. Locales are configured per Market, not on the store:

   ```ruby
   store = PallasTrade::Store.default
   store.default_market.update!(supported_locales: ['es', 'fr'])
   ```

   `supported_locales` accepts an Array or a comma-separated string; `default_locale` also lives on the market. When a store has markets (the norm — stores created with a `default_country_iso`, including seeds and the admin flow, get a default market automatically), market values take precedence: `Store#supported_locales_list` comes entirely from the markets, and `Store#default_locale` returns the default market's locale — falling back to the store column only when the market's `default_locale` is blank. With no markets at all, the store-level columns are used directly.

4. **Customize keys** by overriding in your app's `config/locales/<locale>.yml` — Rails merges later-loaded locale files over earlier ones, and your app's `config/locales/` is loaded last by default.

### Adding a new key

If a string isn't in any locale yet:

```yaml
# config/locales/en.yml in your app
en:
  pallastrade:
    custom_feature:
      title: "Loyalty rewards"
      cta: "Join now"
```

```ruby
PallasTrade.t('custom_feature.title')   # => "Loyalty rewards"
```

Then add the same key under `es`, `fr`, etc. in matching files.

### Normalizing translation keys

PallasTrade uses [`i18n-tasks`](https://github.com/glebm/i18n-tasks) to keep locale files clean. After adding keys:

```bash
bundle exec i18n-tasks normalize          # sort + dedupe
bundle exec i18n-tasks missing            # list missing keys
bundle exec i18n-tasks unused             # list unused keys
bundle exec i18n-tasks health             # all of the above
```

The PallasTrade monorepo runs `normalize` on its YAML files; if you're modifying `backend/pallastrade_gems/pallastrade_admin/config/locales/en.yml` (the Rails admin), always normalize after.

### Default + fallback

```ruby
# config/application.rb (or config/environments/production.rb)
config.i18n.default_locale = :en
config.i18n.fallbacks = [:en]   # missing :es key falls back to :en
```

Rails only mixes `I18n::Backend::Fallbacks` into the backend when `config.i18n.fallbacks` is set — assigning `I18n.fallbacks` directly in an initializer does not enable fallback lookups. For Mobility data translations no setup is needed: PallasTrade configures store-based fallbacks per request via `PallasTrade::Locales::SetFallbackLocaleForStore` (each supported locale falls back to the store's default locale).

`PallasTrade::Current.locale` is the per-request locale. The Store API resolves the per-request locale from the `x-pallastrade-locale` header, then the `?locale=` param (each honored only if in the store's supported locales), then `PallasTrade::Current.locale` (market default → store default).

## Data translations — Mobility

PallasTrade uses [Mobility](https://github.com/shioyama/mobility) for translatable model attributes. Each model declares which fields translate:

```ruby
# pallastrade/core/app/models/pallastrade/product.rb (paraphrased)
class PallasTrade::Product < PallasTrade.base_class
  TRANSLATABLE_FIELDS = %i[name description slug meta_description meta_title].freeze
  translates(*TRANSLATABLE_FIELDS, column_fallback: !PallasTrade.always_use_translations?)
end
```

Translations are stored in **a separate per-model table** (e.g. `pallastrade_product_translations`) keyed by a unique `(pallastrade_product_id, locale)` index:

```
pallastrade_product_translations
  ├── id
  ├── pallastrade_product_id
  ├── locale       ('en', 'es', 'fr', ...)
  ├── name
  ├── description
  ├── slug         (also uniquely indexed per (locale, slug))
  ├── meta_description
  ├── meta_keywords
  ├── meta_title
  └── deleted_at   (paranoid; plus created_at/updated_at)
```

### Reading translations

Mobility transparently returns the translated value for `I18n.locale`:

```ruby
I18n.with_locale(:es) do
  product.name   # => "Camiseta"
end

I18n.with_locale(:en) do
  product.name   # => "T-shirt"
end
```

If the translation for the current locale is missing, behavior depends on `column_fallback`:
- **`column_fallback: true` (default unless `PallasTrade.always_use_translations?`)** — falls back to the model's own column (which holds the default-locale value).
- **`column_fallback: false`** — skips the base column entirely; reads always hit the translation table. Note this does not mean missing translations return `nil` in practice: in request contexts (Store API and controllers), PallasTrade configures Mobility's store-based fallbacks per request (`PallasTrade::Locales::SetFallbackLocaleForStore`), mapping every supported locale to the store's default locale — so a missing translation returns the store-default-locale value. Reads return `nil` only outside that configuration (e.g. a bare console) or when bypassing fallbacks explicitly with `product.name(fallback: false)` — use the latter if you genuinely need to detect/hide missing translations.

### Writing translations

Two patterns:

```ruby
# Via locale block
I18n.with_locale(:es) do
  product.update(name: 'Camiseta', description: 'Una camiseta cómoda')
end

# Via the translation association directly
product.translations.find_or_initialize_by(locale: 'es').update!(
  name: 'Camiseta',
  description: 'Una camiseta cómoda',
)
```

### Which models translate

Out of the box (5.x+):
- `PallasTrade::Product` — name, description, slug, meta_description, meta_title
- `PallasTrade::Taxon` (Category) — name, pretty_name, description, permalink
- `PallasTrade::Taxonomy` — name
- `PallasTrade::OptionType` — presentation
- `PallasTrade::OptionValue` — presentation
- `PallasTrade::Store` — name, meta_description, meta_keywords, seo_title, customer_support_email, address, contact_phone
- `PallasTrade::Policy` — name, body

The 5.4 plan covers translating MetafieldDefinition names + Metafield text values — see `platform/docs/plans/5.4-metafield-translations.md` if you have the monorepo.

### Locale availability

`PallasTrade.always_use_translations?` is set per app:

```ruby
# config/initializers/pallastrade.rb
PallasTrade::Config[:always_use_translations] = false   # default — fallback to column for missing locale
PallasTrade::Config[:always_use_translations] = true    # never fallback — only use translation tables
```

`true` is the right choice for stores where the column value is meaningless (e.g. it's the merchant's internal admin-only string) and only translations are customer-facing. `false` is right for single-locale stores starting out.

## RTL languages (Arabic, Hebrew, Persian)

For RTL support:

1. **Locale config:**
   ```ruby
   I18n.available_locales = %i[en ar he]
   ```
2. **Storefront direction:** storefronts are external (Next.js) apps, so RTL direction is the storefront's responsibility — set `dir="rtl"` in its own layout based on the active locale. On the Ruby side, `PallasTrade::Locale.new(code: locale).rtl?` / `.direction` is the source of truth (there's no `i18n.dir` locale key).
3. **Admin UI direction:** the admin flips to RTL automatically — its layouts set `dir="<%= html_dir %>"` (via `PallasTrade::Admin::RtlHelper#html_dir` → `PallasTrade::Locale#direction`) and the gem ships an RTL stylesheet (`_rtl.css`). RTL triggers for locales whose language code is in `PallasTrade::Locale::RTL_LANGUAGE_CODES` (`ar he fa ur yi`); no extra setup needed.
4. **Mobility data** works the same — you store Arabic strings in `pallastrade_product_translations` with `locale: 'ar'`.

## Storefront integration

The Store API responds in the locale specified by the `X-PallasTrade-Locale` header (or per-request `?locale=es`). Pass the exact locale code the store supports (e.g. `es`, not `es-ES`); unsupported values silently fall back to the store's default locale. Translated fields are returned in that locale; if the locale isn't available, fallback applies.

```bash
curl -H "X-PallasTrade-Api-Key: pk_…" \
     -H "X-PallasTrade-Locale: es" \
     https://my-pallastrade.example.com/api/v3/store/products/cool-shirt
# => { "name": "Camiseta", ... }
```

The `@pallastrade/sdk` exposes `setLocale`:

```ts
const client = createClient({ baseUrl, publishableKey, locale: 'es' })
// or
client.setLocale('es')
```

See the `pallastrade-typescript-sdk` and `pallastrade-api-v3` skills for more.

## Common problems

### "I see `translation missing: es.pallastrade.…`"

The key doesn't exist in the active locale. Either:
- Add the key to `config/locales/es.yml` in your app.
- Install `pallastrade_i18n` gem if the missing key is a PallasTrade-core string.
- Add a fallback: `config.i18n.fallbacks = [:en]` in `config/application.rb` or an environment file (the standard Rails production.rb already sets `config.i18n.fallbacks = true`).

### "Product name shows English even after I set Spanish"

Walk this list:
1. `I18n.locale` is actually `:es`? Add a `puts I18n.locale` in the controller to confirm.
2. `product.translations.find_by(locale: 'es')` exists and has `name` set?
3. `column_fallback: true` would return the English column value. Check the `translates` declaration on the model; if you want strict translations, override with `column_fallback: false` in a decorator.
4. Mobility caching — calls in the same request memoize. Reload the product (`product.reload`) after writing translations in the same process.

### "Adding a new translated field"

Two steps:

1. **Generate the migration** to add columns to the per-model translation table:
   ```ruby
   class AddCustomFieldToPallasTradeProductTranslations < ActiveRecord::Migration[7.2]
     def change
       add_column :pallastrade_product_translations, :custom_field, :text
     end
   end
   ```

2. **Declare it on the model** (via decorator):
   ```ruby
   module PallasTrade::ProductDecorator
     def self.prepended(base)
       fields = base::TRANSLATABLE_FIELDS + [:custom_field]
       base.send(:remove_const, :TRANSLATABLE_FIELDS)
       base.const_set(:TRANSLATABLE_FIELDS, fields.freeze)
       base.translates :custom_field, column_fallback: !PallasTrade.always_use_translations?
     end
     PallasTrade::Product.prepend self
   end
   ```

   (`TRANSLATABLE_FIELDS` is frozen — mutating it with `<<` raises `FrozenError`; redefine the constant instead.)

   If the model also stores the field on the base table (for fallback), add a column there too.

### "Storefront language switcher doesn't show my new locale"

Supported locales are aggregated from the store's **markets** — the legacy `Store#supported_locales` column is only used when a store has no markets (rare; a default market is auto-created). Add the locale to a market:

```ruby
# Stores with markets (the default since PallasTrade 5.4) derive locales from their markets:
store.default_market.update!(supported_locales: ['en', 'es', 'fr', 'de'])

# Stores without markets fall back to the legacy store-level column:
store.update!(supported_locales: 'en,es,fr,de')
```

Switchers should read `store.supported_locales_list` (markets' locales + the store default locale). Headless storefronts fetch it via `GET /api/v3/store/locales` (`client.locales.list()` in `@pallastrade/sdk`). If your locale isn't on any market, it's hidden even when present in `I18n.available_locales`.

### "Translations admin is missing for new content"

The Rails admin already ships a centralized Product Translations page: an overview grid with per-locale coverage stats at `/admin/product_translations`, plus bulk CSV export/import via `PallasTrade::Exports::ProductTranslations` / `PallasTrade::Imports::ProductTranslations`. Per-field editing for other translatable models (`PallasTrade.translatable_resources`: OptionType, OptionValue, Product, Taxon, Taxonomy, Store, Policy) lives on each record's own translations page (`/admin/translations/:resource_type/:id/edit`). The plan in `platform/docs/plans/5.4-centralized-translations-admin.md` is still marked Draft, but its core scope — the product overview grid + CSV bulk operations — has already landed; only extensions beyond products remain open.

## Where to read further

- **Mobility gem docs:** https://github.com/shioyama/mobility — backends, fallbacks, dirty tracking.
- **PallasTrade docs:** `node_modules/@pallastrade/docs/dist/developer/core-concepts/translations.md` (resource + UI translations); `node_modules/@pallastrade/docs/dist/developer/core-concepts/markets.md` for locale/currency configuration per market.
- **`pallastrade_i18n` gem:** https://github.com/stevenbian9266-cyber/pallastrade — community translations.
- **Plan files (monorepo):** `platform/docs/plans/5.4-centralized-translations-admin.md`, `platform/docs/plans/5.4-metafield-translations.md`.
