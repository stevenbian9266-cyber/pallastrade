---
name: pallastrade-catalog
description: Use when the user is working with PallasTrade's product catalog — Products, Variants, Options, Categories, search, images, product publication on channels. Common phrasings include "add a product type", "variants vs options", "product taxonomy", "categorize products", "product images", "Meilisearch reindex", "search broken", "product not showing in store", "publish product on channel", "master variant", "default variant", "SKU". Provides the catalog graph and the operations on it; defers to local @pallastrade/docs for field-level detail.
---

# PallasTrade Catalog

> Commands below use the PallasTrade CLI form (`pallastrade …`, Docker). On a classic Rails app without the CLI (typical pre-5.4), use the native mapping in the `pallastrade-project` skill — `bin/rails` / `bundle exec rake` from the app root, paths without the `backend/` prefix.

The catalog is everything that's for sale: Products, the Variants underneath them, the Options that distinguish those Variants, the Categories that group them, and the search index that makes them findable.

## The catalog graph

```
Product
  ├── Variant (one master + zero or more "real" variants; master flagged via `is_master`)
  │     ├── Price (per currency)
  │     ├── StockItem (per stock location)
  │     ├── VariantMedia (images, videos, focal point — 5.5)
  │     └── OptionValue × OptionValueVariant
  ├── Category × Classification (the join)
  ├── ProductPublication × Channel (5.5 — which channels surface this product)
  ├── ProductPromotionRule (which promos this product qualifies for)
  └── Metafield (custom fields — 5.4+)
```

## Product vs Variant

The **Product** is the storefront concept — name, slug, description, category. It rarely changes once published.

> **Slug 与 URL 变更（2026-08）**：商品 slug 由 friendly_id 管理（`Product::Slugs`，
> `use: [:history, :slugged, :scoped, :mobility]`）。**改名不会自动改 slug**（slug 固定，
> 仅手动改 slug 才会变）；手动改 slug 时 friendly_id `:history` 会把旧 slug 记入
> `friendly_id_slugs` 表（sluggable_type=`PallasTrade::Product`，按 locale）。因此
> 「商品 URL 变更清单」可直接查 `friendly_id_slugs`（服务见 `PallasTrade::ProductUrlChange`），
> 用于引导创建 SEO 301 重定向（Admin Redirects 页）。

The **Variant** is the SKU — what gets added to a cart, what has a price, what has inventory. A Product has at least one Variant.

### Master variant and default variant

Every Product has a "master" Variant — `Product.master` — which historically holds default attributes (price, weight, SKU) when the Product has no real variants. Real variants override.

```ruby
product = PallasTrade::Product.find_by(slug: 'cool-shirt')
product.master            # => the master variant (default attributes)
product.variants          # => non-master "real" variants (color/size combos)
product.variants_including_master   # => everything
```

If a Product has variants (color × size), the master is mostly a placeholder; default pricing/SKU still lives there as a fallback.

`Product#default_variant` is a computed helper, not a stored column. With `PallasTrade::Config[:track_inventory_levels]` enabled it returns the first purchasable (in-stock or backorderable) variant; if none qualifies — or inventory tracking is off — it returns the first variant by position. A product with no real variants falls back to the master:

```ruby
product.default_variant   # => first purchasable (or first-by-position) variant; master if the product has no variants
```

A real `default_variant_id` FK on Product is planned for 6.0 (`6.0-remove-master-variant.md`, implementation not started). Today `Product#default_variant_id` is just a memoized method returning `default_variant.id`, and `master` is still the live mechanism — not a backwards-compatibility accessor.

## Options + OptionTypes + OptionValues

This is how Variants distinguish themselves.

```
OptionType  "Size"          ─┐
OptionType  "Color"         ─┤
                             │
ProductOptionType  Product ──┘  (which OptionTypes apply to which Product)

OptionValue  Size: "S"      ─┐
OptionValue  Size: "M"      ─┤
OptionValue  Color: "Red"   ─┤
OptionValue  Color: "Blue"  ─┘

OptionValueVariant  Variant ──┘  (which Values apply to which Variant)
```

A Product declares which OptionTypes apply via `product_option_types`. Each Variant of that Product picks one OptionValue per OptionType. So a "T-Shirt" Product with `[Size, Color]` OptionTypes has Variants like `[Size=M, Color=Red]`, `[Size=L, Color=Blue]`, etc.

```ruby
product.option_types       # => [Size, Color]
variant.option_values      # => [Size=M, Color=Red]
variant.options_text       # => "Size: M, Color: Red"
```

### OptionType `kind` (5.4)

OptionType has a `kind` field controlling how it renders in the admin: `dropdown`, `color_swatch`, `buttons`. OptionValue's `color_code` field stores the hex for `color_swatch` rendering.

```ruby
size = PallasTrade::OptionType.create!(name: 'size', presentation: 'Size', kind: 'buttons')
color = PallasTrade::OptionType.create!(name: 'color', presentation: 'Color', kind: 'color_swatch')

red = color.option_values.create!(name: 'red', presentation: 'Red', color_code: '#ff0000')
```

## Categories (formerly Taxons)

PallasTrade 5.5 added `PallasTrade::Category`, a subclass of `PallasTrade::Taxon` — the merchant-facing concept for the hierarchical product grouping.

```
Category (hierarchical — left/right via awesome_nested_set)
  ├── Classification (the join — multiple Products per Category, multiple Categories per Product)
  ├── permalink         (URL slug, hierarchical: "men/shirts/casual")
  └── i18n on name + description
```

`PallasTrade::Category < PallasTrade::Taxon`, sharing the `pallastrade_taxons` table — but they are not interchangeable: a Category is owned directly via `store_id` and needs no `Taxonomy` (it default-scopes to manually-curated taxons), while a plain `Taxon` requires a parent `Taxonomy`. Use `PallasTrade::Category` in new code; `PallasTrade::Taxon` remains for backwards compatibility.

```ruby
shirts = PallasTrade::Category.find_by(permalink: 'men/shirts')
shirts.products                          # => Products directly in this Category
shirts.descendants                       # => sub-categories
shirts.active_products_with_descendants  # => active Products in this Category or any descendant
```

### Admin Category Management

Categories are managed from the Admin panel at `/admin/categories`. The admin interface supports:

- **Three-level hierarchy**: Top-level (一级) → Child (二级) → Grandchild (三级)
- **Nested display**: The index page shows the full tree with indent levels
- **Product count**: Each category shows its direct product count and children count

Key model behaviors:
- `acts_as_nested_set` provides `parent`, `children`, `descendants`, `root?`, `leaf?`, `depth`
- `Category < Taxon` with `default_scope { manual }` — no Taxonomy required
- `has_prefix_id :ctg` — all category IDs are `ctg_xxx` format
- Validations: `name` presence, `store` presence, uniqueness within store scope
- `SingleStoreResource` concern ensures store-scoped queries

```ruby
# Category hierarchy examples
current_store.categories.roots          # All top-level (一级) categories
category.children                       # Direct children (二级)
category.descendants                    # All descendants (二级 + 三级 + ...)
category.depth                          # 0 = root, 1 = first child, 2 = grandchild
```

## ProductPublication (5.5 — channel-scoped visibility)

In 5.5, products belong to a Store via `store_id` (single owner). Visibility per Channel is managed via `ProductPublication`:

```ruby
product.product_publications                                           # ProductPublication × Channel
product.product_publications.where(channel: store.default_channel)     # publication for the default channel
```

A ProductPublication has `published_at` and `unpublished_at` windows. The `Product.for_store(store)` scope returns products owned by a store (`store_id`); per-channel visibility is checked via `Product.for_channel(channel)` / ProductPublications; `Product.active(currency)` filters to products that are live with prices in the requested currency.

**Pre-5.5 (4.x, early 5.x):** Products were on Stores directly via `pallastrade_products_stores`. The 5.4→5.5 upgrade migrates this.

## Search

PallasTrade ships a pluggable search provider system in 5.4+:

| Provider | Class | Use when |
|---|---|---|
| Database (default) | `PallasTrade::SearchProvider::Database` | Small catalogs (<10K products); case-insensitive substring (LIKE) matching — no typo tolerance |
| Meilisearch | `PallasTrade::SearchProvider::Meilisearch` | Real-time facets, typo tolerance, large catalogs |

Configured via `PallasTrade.search_provider = 'PallasTrade::SearchProvider::Meilisearch'` in `backend/config/initializers/pallastrade.rb`.

### Reindexing

```bash
pallastrade rake pallastrade:search:reindex
```

The task is a no-op on the Database provider (no index to maintain) and a full catalog push on Meilisearch. Required after:
- Bulk product imports
- Schema changes (new searchable attribute)
- Switching providers
- The 5.4→5.5 channels upgrade (products gain `store_id` and become visible to `for_store`)

### Custom searchable attributes

PallasTrade's search-indexed fields come from `PallasTrade::Product#search_presentation`, which returns the array of document hashes (one per market × locale combination) that gets pushed to the index. Override via a decorator or — preferred — swap the presenter via `PallasTrade::Dependencies.search_product_presenter_class`. After changes, reindex.

## Images + Media

5.5 added product-level media. Media records (`PallasTrade::Asset` subclasses) have a `media_type` from `PallasTrade::Asset::MEDIA_TYPES = %w[image video external_video]`. Images use ActiveStorage attachments; both video media types (`video`, `external_video`) require a URL in `external_video_url` — hosted video-file uploads are not supported. `focal_point` enables crop-aware thumbnails on images.

```ruby
product.media                                       # all media for the product
product.media.where(media_type: 'image').first      # first image
```

The legacy variant-level `PallasTrade::Image` (via `PallasTrade::Asset`) still exists for variants. Variants also expose `variant_media`, `associated_media`, and `gallery_media` for finer-grained queries.

Images use ActiveStorage. Resized derivatives (mini/small/medium/large/xlarge/og_image — see `PallasTrade::Config.product_image_variant_sizes`) are declared with `preprocessed: true`, so ActiveStorage generates WebP variants in background jobs right after upload.

## Brand (custom — your Product's brand)

PallasTrade doesn't ship a Brand model out of the box (different merchants want different brand models — sometimes a Category, sometimes a separate concept with logo/banner/SEO). The `pallastrade:api_resource Brand` generator scaffolds one. See the `pallastrade-resource` skill.

If you scaffold a Brand model, link it from Product via a decorator:

```ruby
module PallasTrade::ProductDecorator
  def self.prepended(base)
    base.belongs_to :brand, class_name: 'PallasTrade::Brand', optional: true
    base.delegate :name, to: :brand, prefix: true, allow_nil: true
  end

  PallasTrade::Product.prepend self
end
```

## Common catalog operations

### "My product isn't showing in the store"

Walk this list:

1. **Is it on the store?** `PallasTrade::Product.for_store(store).where(id: id).exists?` — if false, the Product's `store_id` doesn't point at this store. (Publication checks come next.)
2. **Is it published on the current channel?** `product.product_publications.where(channel: PallasTrade::Current.channel).any?` — if false, no ProductPublication for the channel in scope. (equivalently: `PallasTrade::Product.for_channel(PallasTrade::Current.channel).exists?(id: product.id)`)
3. **Is the publication window active?** (`published_at` is nil OR `published_at <= Time.current`) AND (`unpublished_at` is nil OR `unpublished_at > Time.current`).
4. **Does it have a price in the current currency?** `product.master.prices.where(currency: PallasTrade::Current.currency).any?`
5. **Is it in stock?** `product.in_stock?` — false if no `track_inventory` variant has positive stock.
6. **Is the search index stale?** If using Meilisearch, run `pallastrade rake pallastrade:search:reindex`.

### "Bulk-update prices"

For currency-wide price changes, batch via `PallasTrade::Price.where(currency: 'USD').update_all('amount = amount * 1.1')`. After: the product is fine, but if you have PriceHistory enabled (EU Omnibus), note that `update_all` bypasses the `after_save` callback that records history — iterate and save instead (`PallasTrade::Price.where(currency: 'USD').where.not(amount: nil).find_each { |p| p.update!(amount: p.amount * 1.1) }`) or create `PallasTrade::PriceHistory` rows explicitly. (`pallastrade rake pallastrade:price_history:seed` is only a one-time post-migration backfill that skips any price that already has history rows.) See the `pallastrade-pricing` skill.

### "Add a custom field to Products"

Use Metafields (5.4) — no decorator, no schema change. First create a `MetafieldDefinition` (in the admin or via seed/migration) with a namespace + key + type + `display_on` (`back_end` or `both` — the admin UI doesn't offer a `front_end`-only option for metafields). Then set values per record:

```ruby
product.set_metafield('catalog.season', 'fall-2026')
product.get_metafield('catalog.season')&.value   # => "fall-2026" (get_metafield returns the PallasTrade::Metafield record, or nil)
```

`display_on: front_end` (or `both`) surfaces the metafield on the Store API; `back_end` is admin-only. See `PallasTrade::Metafields` concern and the `pallastrade-resource` skill (`--metafields` flag) for built-in support.

## Stock buckets for shoppers（Catalog F-2，2026-09-16）

`PallasTrade::Catalog::StockStatus` 把精确库存折叠成**枚举桶**给前台用：
`in_stock | low_stock | preorder | backorder | out_of_stock`（`> 阈值` / `1..阈值` / `0+preorderable` /
`0+backorderable` / 其余）。两条铁律：

1. **口径同源**：可用量一律经 `PallasTrade::Stock::Quantifier`（`total_on_hand`）读取 —— 与
   `Variant#in_stock?` / `#purchasable?` 同一个对象，因此桶与布尔字段不可能互相矛盾；
   `should_track_inventory?` 为 false 时供给无限 → 恒 `in_stock`（**不制造稀缺**）。
2. **不下发数字**：精确 `count_on_hand` / `total_on_hand` 不得出现在任何 Store API 响应里（规格断言）。
   阈值来自 `Store#preferred_low_stock_threshold`（默认 5，非法值归一到默认）。

product 层的桶取「最优变体」（in_stock > low_stock > preorder > backorder > out_of_stock）；列表侧
必须预加载 `variants → stock_items → active_stock_reservations`，否则会退化成 N+1。

配送时效（`estimated_transit_business_days_min/max`）是 `ShippingMethod` 上的**既有字段**，
F-2 只是把它经 `PallasTrade::Shipping::Estimate` 与 `delivery_method_serializer` 下发到前台，
**不改结算定价**（权威运费仍在 `Carts::Submit` 时算）。

**配送方式的适用性口径（收口批次，2026-09-16，PRD-20260916-shipping-catalog-observability-scope）**：
`Estimate#scoped_methods` 只返回**该商品真能选**的前台方式 ——

1. **排除数字商品专用方式**（`Calculator::Shipping::DigitalDelivery`）：它零价且 `display_on = 'both'`，
   曾被 `zero_price_method?` 计为候选，让**实体商品**显示"免运费"、并把 PDP 方法数抬高。
   `ShippingMethod#digital` 是它的**唯一权威 scope** —— 不要在读模型里重写计算器类型匹配。
2. **按商品配送分类匹配**：关联了分类的方式必须服务该商品的 `shipping_category`，否则前台会展示
   顾客在结算时选不了的服务。
3. **未关联任何分类的历史方式保留**：模型有 `at_least_one_shipping_category` 校验，这一支只为历史行
   兜底（测试用 `save(validate: false)` 构造）；直接删掉会让商品突然没有任何配送方式。

> 口径修正属**框架内部读模型**改动（`pallastrade_gems` 是团队产品，AGENTS §1 允许直改），不是宿主定制 ——
> 与 F-2 的测试隔离无关：F-2 当时只让 spec 不再受 seed 数据影响，生产口径直到本批才修。

## Back-in-stock subscriptions（SKU 级，2026-09-15 Batch C-2）

`PallasTrade::BackInStockSubscription` 现在**两个粒度共存**（PRD-20260915-catalog-batch-c2-sku-back-in-stock）：

| 粒度 | `variant_id` | 事件 | 通知对象 |
|---|---|---|---|
| SKU 级（推荐） | 有值 | `variant.back_in_stock`（`StockMovement::CustomEvents` 在**该变体**从不可买→可买时发布，载荷 `{ id: 变体前缀 id, product_id: 商品前缀 id }`） | 仅该变体的 `active` 订阅 |
| 商品级（历史兼容） | `NULL` | `product.back_in_stock`（整个商品回到可买） | 仅 `variant_id IS NULL` 的 `active` 订阅（SKU 订阅者由自己的事件服务，**不再被商品级事件误发**） |

数据库约束（迁移 `20260915130000`）：Postgres 唯一索引对 NULL 不去重，所以用**两个 partial 唯一索引**同时保住两套语义——
`(product_id, variant_id, email) WHERE variant_id IS NOT NULL` + `(product_id, email) WHERE variant_id IS NULL`。模型层同步：
`belongs_to :variant, optional: true` + `variant` 必须属于该 `product` + 唯一性 scope 纳入 `variant_id`；scope `for_variant(id)` / `product_level`。

链路与调用点：
- Store API：`POST /api/v3/store/products/:product_id/back_in_stock_subscriptions`（可选 `variant_id`，前缀 `variant_…` 或整数 id，不属于该商品 → 404；幂等按 (商品, SKU, 邮箱)）
- 前台：PDP `BackInStockNotify` 按**所选变体**订阅（`ProductDetails` 传 `selectedVariant?.id`）
- 后台：订阅表格 `variant` 列显示 SKU（商品级显示 —），搜索 `email_or_product_name_or_variant_sku_cont`
- 回归验证：`harness verify back-in-stock-rspec`

改这类能力时的铁律：**事件载荷必须自带解析所需的 id**（事件总线不持有上下文）；发送后立即 `mark_notified!`（幂等）；
邮件失败记日志且保持 `active`（可重试），绝不静默标已读。

## 重复商品（Duplicate Detection，2026-09-15 Batch D-2）

商品层**没有任何防重约束**，所以重复商品会真实存在：`variant.sku` 的唯一性校验可被 `disable_sku_validation` 关闭、允许为空且仅限未删除行；
`pallastrade_variants.barcode` **有列有索引，但完全无校验**；`product.name` 无约束。唯一“自动去重”的是 slug（`Product::Slugs#ensure_slug_is_unique` 冲突时补 uuid）——因此 **slug 不能当重复信号**。

后台 `Products → Duplicate Products`（`PallasTrade::Products::DuplicateCandidates`）按 `duplicate_barcode` / `duplicate_sku` / `duplicate_name` 三类信号给候选分组（只读）；**合并**已由 D-3 提供，见下节。

## 商品合并（Merge Product，2026-09-16 D-3）

`Products::MergePreview` / `Products::Merge` / `Products::UndoMerge` 三件套 + `pallastrade_product_merges` 台账；
入口在 `Products → Duplicate Products`（比较页选「保留哪个 / 合并哪个」→ 预检页 → 确认执行，工作台可撤销）。

- **预检只读**：`MergePreview` 回答「会发生什么」（每段 move/skip 计数 + 跳过原因 + 旧 URL 301 计划 + 历史引用计数），
  执行复用同一份结果 —— 两者口径构造上不可能不一致（历史引用**只统计**）。
- **迁移守恒**：能搬的搬（variants / 主变体库存行 / reviews / media / classifications / promotions），
  冲突的**跳过并留在原处**：`sku_conflict` / `review_conflict` / `stock_location_conflict` / `taxon_duplicate` / `promotion_duplicate`。
- **历史交易永不改写**：`line_items` / `orders` / `payments` / `commerce_transactions` 在合并与撤销前后**逐字节不变**（spec 用快照断言）。
- **被合并商品**：`archived` + **纯软删**（`update_columns(deleted_at:)`，**不得**走 `destroy` —— `reviews/media/variants` 是 `dependent: :destroy`，会把被跳过的评论真删）+ `private_metadata['merged_into']` 标记。
- **旧 URL**：按店铺默认国家 × 支持语言建 `Redirect`；storefront middleware 拿的是**完整 pathname**，所以 from_path 必须带 `/{country}/{locale}` 前缀。
- **撤销**：台账记逐条 id；撤销逐项搬回 + 恢复原状态（`absorbed_status_before`）+ 停用 redirect；任一清单项缺失/易主 → `Blocked` **整体拒绝**（不做部分撤销）；重复撤销幂等。
- **服务不得依赖调用方的关联缓存**：一律显式 `where(product_id: …)` 查询（工厂/调用方刚插入的行可能还没进 `product.variants` 缓存）。

回归验证：`harness verify d3-product-merge-rspec`。
口径：`LOWER(TRIM(...))` 分组 + `HAVING COUNT(DISTINCT products.id) > 1`，同店 + 未删除 + 非 archived。

## AI 采纳审计（Acceptance Audit，2026-09-16，PRD-20260916-catalog-ai-acceptance-audit）

生成侧一直有留痕（每次调用写 `PallasTrade::AI::Run` + `AI::Artifact`，三个 copilot 服务的 `Result`
**已带 `run_id`**、端点也已下发），但**采纳侧此前是空白** —— 商家点 Accept / Discard 只改表单与 UI、
**不发任何请求**，于是「AI 接受率」无从计算（商品域审计 G-5）。

- **字段**：`pallastrade_ai_runs.acceptance_state`（`accepted` / `discarded` / NULL）+ `accepted_at`
  （记的是**决定时刻**，改判会刷新）。`nil` = "还没决定" —— 刻意**没有** `pending` / `rejected`：
  "没人点过"与"没看过"无法区分，编一个状态只会制造假数据。
- **端点**：`POST /admin/ai/acceptances`（`run_id` + `state`）。run 经 `for_store(current_store)` 查找 →
  **跨店 404 且零写入**；非法 state → 422 零写入；重复同状态**幂等**（不移动时间戳），改判则覆盖并刷新。
- **前端**：`ai_assist_controller.js` 的 `accept()` / `discard()` 上报（fire-and-forget + try/catch）——
  **观测数据不得反过来影响商家操作**（AP-009b 精神）。端点常量放在 JS 顶部（admin 挂载点固定，
  不必让 5 个助手面板各加一个 data 属性）。
- **后台可见**：`/admin/ai/runs` 新增「Acceptance」列（未处理显示 "Not decided"）。
- **本切片不做 `edited`**（Accept 之后、Save 之前又被改动）：需要 3 个入口表单携带 `ai_run_id` 并在
  保存时对比草稿（含 Trix/TinyMCE 取值），留下一片；字段与链路已就位。

回归验证：`harness verify ai-acceptance-rspec`（生成侧另跑 `ai-copilot-rspec` / `ai-translate-rspec` / `ai-health-suggestion-rspec`）。

> ⚠️ **服务类不要 `prepend PallasTrade::ServiceModule::Base`**（当你要返回自定义结果形态时）：
> 它的 `call` 会**把返回值换成它自己的** `Result`（`success/value/error`），自定义的 `status` /
> `error_code` 会被丢掉 —— 端点因此把"非法输入"当成成功（200 而非 422）。需要自有返回形态时，
> 用普通类 + `def self.call(...) = new.call(...)`。本批的 `AI::Catalog::RecordAcceptance` 即如此。
>
> 另一处顺手修的既有缺陷：`/admin/ai/runs` 视图调用了 Kaminari 的 `paginate`，而本项目分页用
> **pagy**（`ResourceController` 里 `pagy(:countish, ...)`）→ 页面一渲染就 `NoMethodError`。

## Catalog Health 的 AI 修复建议（AI Fix Suggestion，2026-09-16 Batch E-3）

Catalog Health 工作台（7 类 issue）与商品编辑页侧栏卡片都能生成「怎么修」的建议：`PallasTrade::AI::Catalog::HealthFixSuggestion`（能力 `catalog.health_fix_suggestion`，**只读**——不自动修复、不写库）。

口径铁律（沿用 B-2）：**建议里的计数与工作台的计数必须同源**（`Report#count_for`），不得另算；商品级命中判定复用 `Issues.product_relation(Product.where(id:), key, store:)`，而 `missing_translations` 按「该商品在店铺其它支持语言下 `name` 缺失的语言数」单独判定（与覆盖率页同规则）。

采样只取该 issue 作用域前 5 个商品的**最小事实**（名称/状态/价格有无/库存），不拿客户、订单、成本、供应商数据；无商品关系可过滤的两类 issue（`missing_translations` / `redirect_unresolved`）采样为空并只给工具性步骤。

`redirect_unresolved` **不属商品级**（URL 变更不是商品行事实）——商品卡片不列它，工作台仍有。

回归验证：`harness verify ai-health-suggestion-rspec`。

## Where to read further

- **Core concepts:** `node_modules/@pallastrade/docs/dist/developer/core-concepts/products.md`
- **Media:** `node_modules/@pallastrade/docs/dist/developer/core-concepts/media.md`
- **Search + filtering:** `node_modules/@pallastrade/docs/dist/developer/core-concepts/search-filtering.md`
- **Custom search provider:** `node_modules/@pallastrade/docs/dist/developer/how-to/custom-search-provider.md`
