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

The PallasTrade monorepo runs `normalize` on its YAML files; if you're modifying `pallastrade/admin/config/locales/en.yml` (the Rails admin), always normalize after.

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

The 5.4 plan covers translating MetafieldDefinition names + Metafield text values — see `docs/plans/5.4-metafield-translations.md` if you have the monorepo.

### Locale availability

`PallasTrade.always_use_translations?` is set per app:

```ruby
# config/initializers/pallastrade.rb
PallasTrade::Config[:always_use_translations] = false   # default — fallback to column for missing locale
PallasTrade::Config[:always_use_translations] = true    # never fallback — only use translation tables
```

`true` is the right choice for stores where the column value is meaningless (e.g. it's the merchant's internal admin-only string) and only translations are customer-facing. `false` is right for single-locale stores starting out.

### Detecting missing translations（含 AI 补全）

`fallback: false` 是**检测「这个语言还没翻译」**的官方方式：

```ruby
product.get_field_with_locale('zh-CN', :name, fallback: false)  # => nil 表示该语言缺这个字段
```

原因见上：请求上下文里 `PallasTrade::Locales::SetFallbackLocaleForStore` 把每个支持语言回退到店铺默认语言，读数会「看起来已翻译」。

**两种语言写法别混**：Mobility 存取用**语言代码**（`zh-CN`；写成 `zh_cn` 会抛 `Mobility::InvalidLocale`），而后台翻译抽屉的表单字段名用**归一化后缀**（`name_zh_cn` = downcase + `-`→`_`）。后端要处理抽屉来的参数时，先按 `Store#supported_locales_list` 把后缀映射回代码。

**AI 补全（Batch E-2）**：翻译抽屉的 `[AI Translate Missing]` 走 `PallasTrade::AI::Catalog::ProductTranslation` —— 源 = 店铺默认语言，**只补空字段、绝不覆盖已有译文**，无缺失时不发请求；结果只进预览，Accept 后写入表单、由商家保存（`harness verify ai-translate-rspec`）。

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

#### 后台专属陷阱：只加 `en` 不会让任何测试变红（2026-09-16 实测）

**admin 的 UI 语言不是默认 locale，而是门店偏好**：

```ruby
# pallastrade_admin/app/controllers/pallastrade/admin/base_controller.rb
def default_locale
  @default_locale ||= current_store&.preferred_admin_locale.presence || super
end
```

gem `pallastrade_admin/config/locales/en.yml` 只带 **en**，中文由**宿主**覆盖。因此：

- 只往 gem `en.yml` 加键 → **所有 spec 绿**（spec 用 en 渲染）、CI 绿；
- 但中文门店的后台**静默**整页 `Translation missing: zh-CN.pallastrade…`。

**惯例**：一个功能域一个宿主文件 `backend/config/locales/admin_<域>.zh-CN.yml`，
键集与 gem `en.yml` 的 `admin.<域>` **一一对应**（先例：`admin_ai`、`admin_currency_fx`、
`admin_dispute_rates`、`admin_payment_methods`、`admin_payouts`、`admin_nav`、`admin_shell`）。

**两条必做断言**（缺一条就会漏）：

1. **键集双向**——en 有的 zh-CN 必须有，zh-CN 也不能有 en 没有的孤儿键：

   ```ruby
   expect(zh_keys(domain) - en_keys(domain)).to be_empty   # 缺失
   expect(en_keys(domain) - zh_keys(domain)).to be_empty   # 孤儿
   ```

2. **页面级整页扫描**——只盯自己那个域会漏掉**外壳**（侧边栏 / 快速新建 / confirm 对话框）：

   ```ruby
   expect(response.body.scan(/translation missing: [^<"&]+/i)).to be_empty
   ```

**排查手法**：与其登录后台逐页比对，不如在 spec 里加上面的扫描并 `warn` 出来 ——
一次就能拿到**全部**缺失键（含自己没意识到的其它域）。2026-09-16 正是这样发现
后台外壳（侧边栏/快速新建/退出/confirm 等 15 键）一直是缺的。

#### 第二个陷阱：i18n 结果**不能**直接放进 HTML 属性（2026-09-16 实测）

`PallasTrade.t` 走的是 Rails 的 `TranslationHelper`。**缺 key 时它返回的不是纯文本，而是 HTML**：

```html
<span class="translation_missing" title="translation missing: ...">默认值</span>
```

把它写进 HTML 属性（`title="<%= helper %>"`）会把属性**撕开** —— 引号与尖括号当场破坏 DOM，
残渣泄漏成可见文本。实测：zh-CN 缺 `admin.products.ai.disabled_reason.*` 时，
`/admin/catalog_health` 的 AI 按钮渲染成 `Default"> AI 修复建议`，`title` 里塞满破碎的 span
（en 下 key 存在，所以这个缺陷**从未在英文环境暴露过**）。

**规则**：

| 文案去向 | 用什么 | 为什么 |
|---|---|---|
| **HTML 属性**（`title` / `aria-label` / `data-*`） | `I18n.t` + **纯文本兜底** | 必须保证返回纯字符串，绝不能带标签 |
| **HTML 正文** | `PallasTrade.t` 可用 | 缺失时的 span 在正文里反而是有用的定位信号 |

```ruby
# ✅ 属性安全：两级兜底，永不出现 translation missing，也永不带 HTML
fallback = I18n.t('pallastrade.admin.x.default', default: 'AI is not configured for this store yet.')
I18n.t(key, default: fallback).to_s.strip.presence

# ❌ 会把 <span class="translation_missing"> 写进属性
PallasTrade.t(key, default: PallasTrade.t('admin.x.default'))
```

**根治**：既然缺文案会连带撕坏 HTML，那么"补齐那个 locale 的键"才是真修复；
上面只是让**下一次**漏键时不至于连页面结构都坏掉。

#### 第三个陷阱：一个单词键能把整个功能域挤掉（2026-09-17 实测）

宿主 zh-CN 文件里常见这种"单词翻译"：

```yaml
zh-CN:
  pallastrade:
    ai:            # ← 功能域（Hash：run / admin / …）
      run: { … }
    ai: AI         # ← 同名单词键！
```

YAML **后键覆盖前键** → `pallastrade.ai` 变成字符串 `"AI"` → 整个 `ai.run.*` **全部失效**，
**且不报错、不 warning**。实测症状：文件顶层结构看起来完全正常，
但 `I18n.t('pallastrade.ai.run.id', locale: 'zh-CN')` 返回 nil：

```ruby
YAML.load_file('config/locales/admin_ai.zh-CN.yml')['zh-CN']['pallastrade']['ai']
# => "AI"   ← 应该是 Hash
```

**规则**：
- 单词键**不得与功能域同名**（`ai` / `view` / `run` / `model` 这类最容易撞）；
- 修正 scope 或搬运键之后，**必须验证取值**（`I18n.t(...)`），不要只看文件结构 ——
  "看起来对"正是这类错误藏身的地方；
- 这类错误只能靠**真实取值或渲染**发现，静态审查抓不到。

#### 第四个坑：嵌套结构必须与 en **逐层对应**（2026-09-17 实测）

翻译时很容易"把子层拍平"—— 例如把 en 的 `tables.operators.equals` 写成 `tables.equals`。
后果不是报错，而是**同时**产生一批缺失（`operators.*` 全缺）和一批孤儿（`equals` 等没人取）。

**做法**：拿键时**直接按 en 的层级输出**（例如 `operators.equals = equals`），
照抄层级而不是凭直觉归类；写完立刻跑键集断言 —— 它会把"缺失 + 孤儿"一起报出来，
这正是发现这类错误最快的途径。

#### 第五个坑：missing 文本里的 locale **大小写**会误导你（2026-09-17 实测）

中文后台看到 `translation missing: zh-cn.pallastrade.in_stock` —— 注意是**小写 `zh-cn`**。
这看起来像"某处把 locale 写成了小写、导致整片中文失效"，属于**最高优先级**的怀疑方向。
**实测结论：不是。locale 一直是对的，是这两个键真的缺。**

排查过程（三个插桩点，一次请求即出结论，成本很低）：

| 插桩位置 | 输出 |
|---|---|
| `Admin::BaseController#set_locale`（`super` 之后） | `I18n.locale=:"zh-CN"` |
| 渲染该单元格的 helper 内 | `I18n.locale=:"zh-CN"`，`caller` 直指 `.erb:3` |
| `PallasTrade.translate`（查表前） | `I18n.locale=:"zh-CN" opts_locale=nil` |

即：**发出 missing 的那一次调用，locale 就是 `:"zh-CN"`（大写）**。
小写来自 i18n 在 **fallback 链**（`I18n.fallbacks[:"zh-CN"] == [:"zh-CN", :zh]`）
上逐层尝试时的另一轮查表 —— 是表象，不是病因。

**规则**：看到 `translation missing: <locale>.…` 时的**首要动作**是
**确认该 locale 下这个 key 是否真的存在**：

```ruby
I18n.exists?('pallastrade.in_stock', :'zh-CN')   # false ⇒ 补键，收工
```

**只有**在 key 确实存在、却仍报 missing 时，才去查 locale 变量本身
（那时再插桩 `I18n.locale`，上表三个点照抄）。

**顺带记住的量化盲区**：只按 `admin.*` 前缀统计会漏掉**顶级键**
（`pallastrade.in_stock` 这种没有子层的叶子键，全仓 271 个）。
顶级键要**单独断言**——本次缺陷就是"顶级键不在任何检查视野里"，
却出现在**商家每天都会看的**商品列表库存列上（每行一个 missing）。
另外注意视图里对这些标签调了 `.downcase`，**中文不受影响**，可以放心补中文。

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

The Rails admin already ships a centralized Product Translations page: an overview grid with per-locale coverage stats at `/admin/product_translations`, plus bulk CSV export/import via `PallasTrade::Exports::ProductTranslations` / `PallasTrade::Imports::ProductTranslations`. Per-field editing for other translatable models (`PallasTrade.translatable_resources`: OptionType, OptionValue, Product, Taxon, Taxonomy, Store, Policy) lives on each record's own translations page (`/admin/translations/:resource_type/:id/edit`). The plan in `docs/plans/5.4-centralized-translations-admin.md` is still marked Draft, but its core scope — the product overview grid + CSV bulk operations — has already landed; only extensions beyond products remain open.

## Where to read further

- **Mobility gem docs:** https://github.com/shioyama/mobility — backends, fallbacks, dirty tracking.
- **PallasTrade docs:** `node_modules/@pallastrade/docs/dist/developer/core-concepts/translations.md` (resource + UI translations); `node_modules/@pallastrade/docs/dist/developer/core-concepts/markets.md` for locale/currency configuration per market.
- **`pallastrade_i18n` gem:** https://github.com/stevenbian9266-cyber/pallastrade — community translations.
- **Plan files (monorepo):** `docs/plans/5.4-centralized-translations-admin.md`, `docs/plans/5.4-metafield-translations.md`.
