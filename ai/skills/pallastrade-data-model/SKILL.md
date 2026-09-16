---
name: pallastrade-data-model
description: Use when the user is asking how PallasTrade's domain models relate — Orders, LineItems, Variants, Products, Stores, Channels, Markets, Payments, Shipments, Customers, Adjustments. Architecture and relationships only. Common phrasings include "how does X connect to Y", "what's the relationship between", "where does PallasTrade store X", "how do I query orders across stores", "how do channels work", "what's the difference between Cart and Order", "Store vs Channel vs Market". For adding new models / new API resources, use the `pallastrade-resource` skill. For field-level detail, see `docs/developer/core-concepts/` in the installed `@pallastrade/docs` package.
---

# PallasTrade Data Model

A relationship map for the most-asked-about PallasTrade models. Field-level documentation lives in the installed `@pallastrade/docs` package at `node_modules/@pallastrade/docs/dist/developer/core-concepts/`.

## The catalog → cart pipeline

```
Product → Variant → LineItem → Order
```

- **Product** is the brand-level entity (name, slug, description, category).
- **Variant** is the sellable SKU. Every Product has at least one Variant. Variants carry SKU, prices, dimensions, and link to inventory.
- **LineItem** links a Variant to an Order with `quantity` and price frozen at add-time.
- **Order** is the customer's transaction — the cart-in-progress and, after checkout, the completed transaction (same record, different `state`).

Variants relate to stock via `StockItem` (one per Variant per StockLocation) and the `StockMovement` history.

### Master vs default variant

A Product has a `master` variant (legacy concept, `is_master: true`) and a computed `default_variant` method: when `PallasTrade::Config[:track_inventory_levels]` is on, the first purchasable variant; otherwise the first non-master variant by `position`; master is only the fallback when the product has no other variants. `product.default_variant_id` just returns that computed variant's id. Neither is a database column in 5.5 — don't query or migrate against `default_variant_id` (a `default_variant_id` FK on `pallastrade_products` is planned for 6.0, implementation not started; see `docs/plans/6.0-remove-master-variant.md`). Use `product.variants` for the non-master sellable variants and `product.variants_including_master` only when you genuinely need the master row included.

## Back-in-stock subscriptions

`PallasTrade::BackInStockSubscription` (table `pallastrade_back_in_stock_subscriptions`)
captures a guest email for one product: `store_id`, `product_id`, `email`, `status`
(`active` → `notified`). Unique per `[product_id, email]`; the Store API
`POST /api/v3/store/products/:id/back_in_stock_subscriptions` is idempotent and
re-activates a notified row. `PallasTrade::BackInStockSubscriber` emails active rows on
`product.back_in_stock` and marks them `notified`. A `Store has_many back_in_stock_subscriptions`.

## Product reviews (P0-4 / F-1)

`PallasTrade::Review` (table `pallastrade_reviews`) captures a customer review for one product:
`store_id`, `product_id`, `user_id`, `rating` (1–5), `title`, `body`, `status`
(`pending` → `approved` | `rejected`, default `pending`), `verified_purchase` (boolean, auto-set
from the customer's completed orders). Unique per `[product_id, user_id]` (a customer reviews a
product once). `has_prefix_id :rev` (URL-safe `rev_…` ids). `SingleStoreResource` (store-scoped).
A `Store has_many :reviews`; a `Product has_many :reviews` + `has_many :approved_reviews`.

Photos (F-1, 2026-09-16): `has_many_attached :images` (ActiveStorage) with model constants
`MAX_IMAGES = 3`, `ALLOWED_IMAGE_TYPES = %w[image/jpeg image/png image/webp]`,
`MAX_IMAGE_BYTES = 5.megabytes` and a `images_are_acceptable` validation (count / type / size).
`#ordered_images` returns attachments in primary-key order. Blobs are created through
`POST /api/v3/store/direct_uploads` (customer JWT) which stamps `review_uploader_id` into the blob
metadata; review creation accepts only signed ids uploaded by that same customer.

Aggregation: `Product#average_rating` (average over approved, nil when none) and
`Product#review_count` (approved count) are exposed on `ProductSerializer` and feed the
storefront JSON-LD `AggregateRating`. Only `approved` reviews are public via the Store API
`GET /api/v3/store/products/:id/reviews` (paginated, `meta.rating_distribution` in the same
payload, computed from the same scope); moderation happens in the admin
`PallasTrade::Admin::ReviewsController` (approve / reject / delete) and the admin reviews table
carries a **photos** column. Pending reviews (and therefore their photos) are never public.

## Promotion redemptions (ledger)

`PallasTrade::PromotionRedemption` (table `pallastrade_promotion_redemptions`, prefix id
`redemption_…`) is the promotion occupancy/redemption ledger — one row per `(promotion, order)`:

- `state`: `reserved` → `committed` (written inside the `order.complete` transaction), or
  `released` with `release_reason` (`order_canceled` / `coupon_removed` / `reserved_timeout` / `refunded` / `manual`).
- nullable `coupon_code_id` (multi-code promos), `amount`/`currency`, `user_id`, and the
  `reserved_at` / `reserved_until` / `committed_at` / `released_at` timestamps.
- Constraints: unique `(promotion_id, order_id)`; **partial** unique `(coupon_code_id) WHERE state <> 'released'`
  (a released code can be reused).
- `Order has_many :promotion_redemptions`, `Promotion has_many :promotion_redemptions`,
  `Store has_many :promotion_redemptions`. `PromotionRedemption#release!` also returns the
  occupied `CouponCode` to `unused`.
- `Promotion#credits_count` / `#usage_limit_exceeded?` read **committed** rows (the ledger is the
  single source of truth for usage limits; the older `Adjustment`-based `Promotion#credits` is deprecated).

## Promotion columns cleanup (batch6, 2026-09-11)

`pallastrade_promotions` no longer carries the v2-era `advertise` (boolean) and `path` (string)
columns — removed by host migration `20260911000001_remove_advertise_and_path_from_pallastrade_promotions`
(PRD-20260911-promo-batch6). Both were dead weight: `advertise` was only read by
`Product#possible_promotions` (deleted, together with the now-unused
`ProductsHelper#cache_key_for_product` promo fragment) and `path` only by
`PromotionHandler::Page` (deleted). `Promotion` also drops `scope :advertised`, the `path`
normalizer and the `path` ransack whitelist; `PromotionHandler::FreeShipping` no longer filters
on `path: nil`.

Grouping is the remaining promotion-side dimension: `Promotion belongs_to :promotion_category,
optional: true` (table `pallastrade_promotion_categories`, prefix id `procat_…`, columns
`name`/`code`, **no `store_id`** — categories are installation-level and shared across stores).
Deleting a category does not delete promotions (the FK is nullable and there is no dependent
cascade).

## Disputes (DSP-P7-1, 2026-09-11)

`pallastrade_disputes` (prefix id `dsp_…`) is the durable aggregate for **provider-initiated money
reversals** (chargeback / inquiry / warning / representment) — deliberately **not** a Refund:

- Unique `(provider, provider_dispute_reference)` — the event idempotency key; a payment can carry
  **1:N** disputes and partial amounts.
- State machine (10 values, **forward-only by phase rank**): `opened` → `needs_response` →
  `submitted` → `under_review` → `won/lost/accepted/expired`, plus `closed` (archive) and
  `manual_review` (human). Backwards moves are rejected; corrections within the same phase and
  closed/manual_review entries are allowed.
- `evidence_due_at` is first-class (provider evidence window); `attention_reason` marks rows needing a human —
  written at ingestion (`unlinked_payment` / `non_positive_amount` / `invalid_transition`), by DSP-P7-6
  convergence (`provider_conflict` / `journal_gap` / `funds_evidence_missing`) and by the DSP-P7-7 admin console
  (`operator_review`, `Disputes::MarkManualReview`), **never overwriting** an existing
  reason (enum lives in `PallasTrade::Dispute::ATTENTION_REASONS`; `string` column, no DB check → zero DDL to extend).
- `funds_withdrawn_at` / `funds_reinstated_at` (DSP-P7-2) record when the provider actually withdrew /
  reinstated the money — written once by the funds events (replay never overwrites).
- `pallastrade_dispute_evidence_submissions` (DSP-P7-8) stores the **immutable receipts** of the two dangerous
  provider write actions (`evidence_submitted` / `accepted`): `payload_digest` (idempotency key, unique per
  `(dispute, kind)`), provider reference/status, actor columns, `late`, `accepted_reason`, `response_metadata`
  (jsonb) and the retained evidence files. **No amount columns** — money still moves through the provider
  webhook → DSP-P7-3 ledger path; the model rejects updates/destroys (`ImmutableError`).
- Written by `PallasTrade::Disputes::HandleProviderEvent` (webhook-driven, idempotent, upsert never nil-overwrites
  existing facts) and by `PallasTrade::Disputes::Recover` (DSP-P7-6 convergence: **forward-only** state repair from a
  provider snapshot + idempotent journal repair + manual review — never re-charges, never auto-refunds, never rewrites
  ledger entries). **No** order/inventory/payment/journal writes beyond the ledger repair above.
- `CommerceTransaction` stays `completed`: disputes never mutate the original transaction state.
- `pallastrade_dispute_deadline_alerts` (**D14 切片2**, 迁移 `20260916200000`) —— 证据期限**分档提醒台账**：
  `tier`（`t{n}` / `overdue`）、`alerted_at`、`evidence_due_at`、`hours_remaining`、`store_id`、`metadata`（`backfilled` /
  `missing_evidence` / `policy` 快照）。**append-only**：唯一键 `(dispute_id, tier)` = 幂等键（同一争议同一档位只落一行），
  索引 `(store_id, alerted_at)` 支撑后台看板计数。策略存在 `Store#private_metadata['dispute_deadline_policy']`
  （**无新列、无新表**：`tiers_days` / `auto_lose_on_overdue` / `auto_lose_limit`）——沿用「过渡期 metadata」形态。
  零资金列：该表**没有**任何金额字段，也不写 `funds_*` 时间戳（不触发资金入账事件）。

## 风控名单与评估留痕（D15 切片1, 2026-09-16）

- `pallastrade_payment_risk_lists`（§74.1 规划表名）：`list_type`（denylist/allowlist）× `subject_type`
  （card_fingerprint/bin/email/ip/device/customer/address/country）× `value`（归一化后）+ `value_hash`（SHA256）。
  **唯一键 `(list_type, subject_type, value_hash)`** = 幂等键；`store_id` **可空 = 全局**（非空 = 店铺）；
  `status`（active/revoked）+ `expires_at`（**生效率 = active 且未到期**，不是删除）；`added_by`（polymorphic）+ `reason` + `metadata`。
  索引：`(store_id, subject_type, status)`、`(status, expires_at)`。
- `pallastrade_payment_risk_assessments`：决策留痕（`order_id` / `store_id` / `decision` / `matched_entry_ids`(jsonb) /
  `signals`(jsonb) / `evaluated_at`）。**唯一键 `(order_id, evaluated_at)`**（同一秒并发只落一行）——
  业务上的重复投递去重靠服务层「同决策 + 同命中集」复用窗口（5 分钟），不靠数据库兜底。
- 两者均为**只新增表**（不回填）；无金额列，也不写 `funds_*` 时间戳（不触发资金入账事件）。

## 支付费率策略（D13 切片3, 2026-09-16）

- `pallastrade_payment_fee_policies`（§74.1 规划表名 `(scope_type, scope_id)` 索引要求）：
  `store_id` **可空 = 全局策略**（非空 = 店铺策略）；`scope_type`（global/store/provider/method）+ `scope_id`
  （provider → `payment_method_id` 字符串；method → **入口 method_key**；global/store **归一为 NULL**）；
  条件 `currency` / `card_type` / `region`（空 = 全部）；分量 `percent_fee` / `fixed_fee` / `platform_percent` /
  `cross_border_percent` / `cross_border_fixed` / `currency_conversion_percent`；保底封顶 `min_fee` / `max_fee`；
  判定基准 `home_country` / `settlement_currency`；窗口 `effective_from` / `effective_until`；
  `status`（active/revoked）+ `revoked_at`（**软撤销，历史行保留**）+ `created_by`(polymorphic) + `metadata`。
- 索引：`(scope_type, scope_id)`（名称 `idx_fee_policies_scope`）、`(store_id, status)`、`(status, effective_from)`。
- 金额精度 `decimal(12,2)`（与 `payout_lines` 同口径）、百分比 `decimal(6,4)`（0..100）。
- **只新增表**（不回填，不动既有列）；无 `funds_*` 时间戳、不触发资金入账事件；报表只读该表 + `pallastrade_payments` + `pallastrade_payout_lines`。

## 汇率域两表（D13 切片4, 2026-09-16）

- `pallastrade_currency_rates`：多源汇率。`store_id` **可空 = 全局**（本店优先于全局）/ `base_currency`（结算侧）/ `quote_currency`（展示侧）/
  `rate` **decimal(20,10)** / `source`（manual/provider/third_party）/ `priority`（**无列默认**，由模型按来源归一化：provider 30 / third_party 20 / manual 10）/
  `effective_from` / `effective_until` / `status`(active/revoked) + `revoked_at`（**软撤销，历史行保留**）/ `note` / `metadata`；
  **`identity_key` 唯一**（SHA256("rate:<store|global>:<base>:<quote>:<source>:<effective_from_iso>")）= 幂等键。
  索引：`identity_key`(unique)、`(base_currency, quote_currency, status)`、`(store_id, status)`、`(status, effective_from)`。
- `pallastrade_fx_snapshots`：逐单锁汇凭证 + 结算对比结果。`order_id` / `payment_id` / `currency_rate_id` / `base_currency` / `quote_currency` /
  `display_rate` + `up_charge_percent` + `effective_rate` / `rate_source` / `locked_at` / `locked_on`；
  结算侧 `settlement_rate` / `settlement_source` / `settlement_currency` / `settled_gross_amount` / `variance_bips`(int) / `variance_status` / `compared_at` / `reconciliation_case_id` / `occurrences` / `signals`。
  **唯一键 `(order_id, base_currency, quote_currency)`**（一单一种币对只锁一次）；索引 `(store_id, variance_status)`、`(variance_status, locked_at)`。
- 两者均为**只新增表**（不回填）；无 `funds_*` 时间戳、不触发资金事件；汇率快照不参与定价与资金计算。

## 拒付率预警台账（D14 切片3, 2026-09-16）

- `pallastrade_dispute_rate_alerts`：一行 = 「店铺 × 卡组织 × 评估日」的预警观测。
  `store_id`（必填）/ `network`（卡组织归一值）/ `tier`（`approaching` / `breached`）/ `evaluated_on`(date) / `window_days` /
  `count_ratio_bps` + `amount_ratio_bps`（**基点的整数**，避免浮点漂移；nil = 不可判定）/ `count_threshold_bps` + `amount_threshold_bps`（**当时的阈值留档**）/
  `transactions_count` + `disputes_count`（分母/分子笔数）/ `transactions_amount` + `disputes_amount` decimal(12,2) / `currency` /
  `triggered_metrics`(jsonb → `['count']`/`['amount']`)/ `dedupe_key`（**唯一** = `rate:<store>:<network>:<date>`）/ `detected_at` / `escalated_at` / `metadata`。
- 索引：`dedupe_key`(unique)、`(store_id, tier, evaluated_on)`、`(network, evaluated_on)`；**只新增表**，不回填。
- ⚠️ **支付无 currency 列**：交易的币种口径来自订单（`orders.currency`）；`pallastrade_payments` 只有 `order_id`/`amount`/`state`/`source_type`/`source_id` 等。
- ⚠️ `pallastrade_credit_cards` **无 BIN 列**（只有 `fingerprint`/`cc_type`/`last_digits`）→ BIN 级下钻不可得，业务侧以卡指纹替代。

## Order promotion snapshot (batch4a, 2026-09-10)

`pallastrade_order_promotions` carries the **成交快照** written at money-confirmed time
(`order.complete` / standard-flow `paid` / `commerce_transaction.payment_confirmed`):

- Snapshot columns: `name`, `kind`, `code`, `description`, `definition_digest`,
  `item_amount` / `order_amount` / `shipping_amount` / `total_amount`
  (`null: false, default: 0.0`), `currency`, `frozen_at` (`nil` = not frozen).
- `OrderPromotion#frozen?` = `frozen_at` + `name` present; readers are **snapshot-first**
  (`name` / `code` / `kind` / `description` fall back to the live promotion while unfrozen),
  so carts behave exactly as before and historical orders never drift.
- Amounts are copied from the batch2 `DiscountProjection` lines (never recomputed);
  `Promotion#definition_digest` is a `SHA256` over the canonical definition payload.
- Historical rows are frozen by `rake pallastrade:promotions:backfill_order_promotion_snapshots`
  (dry-run by default, `APPLY=1` writes, idempotent — frozen rows are never overwritten).

## Blog posts (CMS)

`PallasTrade::Post` (table `pallastrade_posts`) is the CMS blog article model.
A `Store has_many :posts`. Key fields: `store_id`, `title`, `slug` (FriendlyId,
unique per store), `excerpt`, `author`, `published_at`, `seo_title`, `seo_description`.
`published_at` nil = **draft**, a future value = **scheduled**, past/now = **published**
(`post.published?` / `post.scheduled?`).

It reuses the same infrastructure as `PallasTrade::Policy`:
- `PallasTrade::TranslatableResource` — `title`/`excerpt`/`seo_title`/`seo_description`
  are translatable (Mobility, `pallastrade_post_translations` table).
- ActionText rich body — `body` is a per-locale rich text field (RICH_TEXT_TRANSLATABLE_FIELDS).
- `has_one_attached :cover_image` (ActiveStorage).

Scopes: `published` / `drafts` / `scheduled` / `newest_first`
(`published_at DESC NULLS LAST`). The Store API only ever exposes published posts.

## The multi-channel / multi-store axis

```
Store → Channel → ProductPublication → Product
```

Available since PallasTrade 5.5.

- **Store** is the top-level brand (one organization = one Store, typically).
- **Channel** is a selling surface within a Store: the online storefront, in-person POS, marketplace integrations (Amazon, eBay), B2B wholesale, mobile apps. Every Store has at least a default Channel named "Online Store".
- **ProductPublication** is the join: which Products are visible on which Channel, with optional `published_at` / `unpublished_at` windows for scheduling.
- **Order** has `channel_id` so revenue can be attributed per channel.

The Store API resolves a channel per request from the `X-PallasTrade-Channel` header (matched against `channels.code` or a `ch_…` prefixed ID); without it the store's default channel is used. The Admin API does not consume `X-PallasTrade-Channel` — admin queries return data across all channels for the current store.

## Markets (regional config)

```
Market has_many :countries
Market  columns:  currency (string), default_locale (string)
Order belongs_to :market
```

A Market is a regional configuration: its set of countries, currency, and default locale. Stores typically get a default Market created automatically (when a default country is known at creation), but markets are optional — check `store.has_markets?`; currency and locale fall back to store-level defaults when no market exists. Orders are placed in a Market — that's what controls the currency the customer sees and what tax rules apply.

For full Market documentation see `node_modules/@pallastrade/docs/dist/developer/core-concepts/markets.md`.

## Cart vs Order

In PallasTrade, `PallasTrade::Order` is both the in-progress cart and the completed transaction. The `state` column tracks which phase: `cart`, `address`, `delivery`, `payment`, `confirm`, `complete`. Filter on state to distinguish:

```ruby
PallasTrade::Order.where(state: 'cart')      # in-progress carts
PallasTrade::Order.where(state: 'complete')  # finalized orders
PallasTrade::Order.complete                  # named scope — NOT equivalent: defined as where.not(completed_at: nil), so it matches any order that ever completed checkout, including ones later canceled or returned
```

`Order#token` (`has_secure_token :token, length: 35`) identifies an anonymous cart across requests. Logged-in carts are owned via the `user_id` FK.

## Order parent/child + split_from (P1, 数据层)

> P1（2026-08-26）为「父子单 / 拆单 / 合并支付」铺数据地基。以下关联已存在但**尚未接入任何业务流程**。

- `orders.parent_id`（可空自引用 FK）→ `Order#parent` / `#children`（`dependent: :nullify`）。
  - 语义方法：`parent_order?`（有 children）/ `child_order?`（有 parent）/ `single_order?`（两者皆无，未拆单订单）/ `sibling_orders` / `root_order`（沿父链到根，防环）。
  - 未拆单订单 `parent_id = NULL`，行为完全不变。
- `orders.split_from_id`（可空 FK）→ `Order#split_from` / `#split_orders`：拆单来源血缘（展示用）。
- `orders.payment_combination_id`（可空）→ 合并支付归属（跨父订单聚合支付）。
- **`PaymentCombination` / `PaymentSplit`**：见 `pallastrade-payments` SKILL（P1 数据层）。
- **统一拆单引擎**：`PallasTrade::Orders::Splitter`（P2）——把订单按分组拆成子订单，迁移行项目/分摊调整/分摊已付 `PaymentSplit`/重算金额；策略 `SplitStrategies::ByStockLocation` / `ByStore`。详见 `pallastrade-checkout` SKILL。

## Order 聚合派生 (P3, 只读派生)

> P3（2026-08-27）为父订单（有 children）提供金额/支付/发货状态聚合。**这些方法不覆写核心 `total` / `payment_total` / `outstanding_balance` / `shipment_state`**——核心方法仍被 `OrderUpdater` / 状态机 / 校验依赖；聚合方法仅供序列化器 / 查询在父订单时使用，无 children 时回退原值（零行为变化）。

- `combined_total`：own（item + shipment + adjustment）+ Σ children.combined_total（递归）。
- `combined_payment_total`：own completed payments + Σ children。
- `combined_outstanding_balance`：与 `outstanding_balance` 同规则（取消 → `-payment`；否则 `total - (payment + reimbursement)`），基于聚合值。
- `combined_amount_due`：`[combined_outstanding_balance - total_applied_store_credit, 0].max`。
- `combined_shipment_state`：聚合 own+children 状态，套 `OrderUpdater#update_shipment_state` 规则（backorder → `backorder`；多状态含 shipped → `partial`；含 pending → `pending`；否则 `ready`）。
- `combined_payment_state`：基于 `combined_outstanding_balance`（>0 → `balance_due`；<0 → `credit_owed`；=0 → `paid`；取消且 0 → `void`）。
- `effective_payment_total`：有 `PaymentSplit` 时用 `captured - refunded`（拆单记账分摊），否则 `payment_total`。
- 上述金额方法已注册 `money_methods`（`display_combined_*` 可用）。Store/Admin `OrderSerializer` 在 `parent_order?` 时用聚合值输出 `total` / `amount_due` / `payment_status` / `fulfillment_status`。

## 合并支付数据配套 (P4, 2026-08-27)

> P4 实现 `PaymentCombination` 服务层时的数据/模型配套（`payment_splits.payment_id` 由 NOT NULL 改为可空，迁移 `20260827000001`）：

- `payment_splits.payment_id` 可空：`PaymentCombinations::Create` 在支付发生前建 split（payment 后补），`Complete` 回填。
- `Payment#order` 改 `optional: true`：组合支付挂 `order_id=nil`；`update_order` / `invalidate_old_payments` / `currency`（`order&.currency || payment_combination&.currency`）已有 nil 守卫。
- `PaymentCombination#payments` 关联（`has_many :payments`，组合支付本身，`dependent: :nullify`）。
- `OrderUpdater#update_payment_total`：订单存在有效 `PaymentSplit` 时取 `captured - refunded`（组合/拆单成员订单的已付金额以 split 为准，因为组合 payment 不在 order.payments 里）。
- 服务层（Create/Complete/SettleJob/Webhook 分支）见 `pallastrade-payments` SKILL。

## Immutable Financial Journal 表（FIN-P4-2, 2026-09-06）

`pallastrade_financial_ledger_entries`（迁移 `20260906000001`，CommerceTransaction 先例直接放
`backend/db/migrate/`）——CommerceTransaction 级不可变资金账本：`commerce_transaction_id` NOT NULL FK；
可空 source FK `order_id/payment_id/refund_id/dispute_id/payment_combination_id/payment_split_id`（`dispute_id`
于 **DSP-P7-3** 追加：迁移 `20260912000004`，nullable + index——争议资金行直连 dispute 主体，
并使 posting key 避开「同 payment 1:N 争议」碰撞）；`entry_type`；带符号
`amount decimal(10,2)`；`currency`；`idempotency_key` UNIQUE；`reversal_of_id` 自引用（partial UNIQUE
WHERE state='posted'）；`state`(posted/reversed)；`effective_at`(事实时间)/`recorded_at`(入账时间，DB 默认
now)；`provider/provider_reference` 预留。模型 `PallasTrade::FinancialLedgerEntry`（`fle_`，append-only +
ImmutableError）。posting 输入 = `FinancialFact`（见 pallastrade-payments SKILL §Immutable Financial Journal）。

## Financial Fact（FIN-P4-1, 2026-09-06；transient value object，非 DB aggregate）

`PallasTrade::FinancialFact`（`backend/pallastrade_gems/pallastrade_core/app/models/pallastrade/financial_fact.rb`）是**不落库**的只读值对象——
非 AR、无表、无 migration。它标准化「Payment/Refund → 资金事实」语义（status/fact_type/
instrument_class/ownership/命名纪律见 `pallastrade-payments` SKILL §Financial Fact Resolution）。
CommerceTransaction/Payment/Refund/PaymentSplit 仍是唯一持久化资金与分摊载体；FinancialFact 是
FIN-P4-2 Immutable Financial Journal 之前的语义契约层，不替代任何现有模型。

## Checkout-side models

```
Order → Payment → PaymentMethod
Order → Shipment → ShippingRate → ShippingMethod
Order → Address (bill_address, ship_address)
```

- **Payment** has its own state machine (`checkout → processing → pending → completed`, plus `failed`, `void`, and `invalid`). Column is `state`.
- **Shipment** has its own state machine (`pending → ready → shipped` with `canceled`). Column is `state`.
- **ShippingRate** is a per-Shipment offer (e.g. UPS Ground $5.99, USPS Priority $8.99). The customer picks one.

## Payment options — 过渡期 metadata 形态（D1, 2026-09-15）

「支付商 × 支付方式 → 前台入口」过渡期**不建表**：`pallastrade_payment_methods` 一行 = 一个支付商账户
（Provider），商家启用的入口存 `private_metadata`（`metadata` 是其 API 别名，Stripe 式 write-only）：

```json
{
  "optionized": true,
  "options": [
    { "kind": "card", "active": true, "position": 1, "frontend_kind": "inline", "display_name": "Credit Card" }
  ],
  "last_test_connection": { "ok": true, "code": "credentials_present", "message": "…", "checked_at": "2026-09-15T08:00:00Z" }
}
```

- **门控（§63.4 零感迁移）**：`optionized` 缺失 = 未迁移 → `effective_payment_options` 回落 1 个默认入口
  （行为与今天一致）；`optionized=true` → 只认配置的可用入口，**0 可用 = 0 前台入口**（`frontend_visible?`
  从 `collect_frontend_payment_methods` 过滤掉整个 provider）。
- **只读安全**：`PaymentMethod#payment_options` 归一化——非 Hash 条目 / 缺 `kind` 一律忽略；
  `available_payment_options` 按 `position` 升序（相同保持配置顺序）。
- **命名避让**：入口 API 一律 `payment_option*` 前缀（`Gateway#options` 已存在，网关型 provider 会覆盖）。
- **正式形态**：D1 后半/D2 落 `pallastrade_payment_options`（provider_id/kind/…unique(provider_id, kind)），
  迁移时每个 provider 生成一条默认 option（业务方案 §74）。

### Payment environment & credential metadata（D9, 2026-09-15）

- **新列**：`pallastrade_payment_methods.environment`（string，`default: 'live'`，`null: false`）—— 存量数据零回归；白名单 `PallasTrade::PaymentMethod::ENVIRONMENTS`。
- **凭据生命周期元数据**（不建表）：`private_metadata['credentials'][key] = { 'rotated_at' => ISO8601, 'expires_on' => 'YYYY-MM-DD' }`；告警状态写 `private_metadata['credential_alerts'][key] = { 'level' => '30d|7d|1d|expired', 'alerted_at' => ISO8601 }`。
- **凭据值**仍存 `preferences`（YAML 序列化列，provider 声明 symbol 键）；值可为 `env:VAR` 引用（**只存引用**）。
- 写入用 `update_columns(private_metadata: …)`（脱开校验/回调），读用 `credential_status/credential_metadata`。
- 会话/支付测试标记：`PaymentSession#external_data['test_mode']` → `Payment#metadata['test_mode']`（`find_or_create_payment!` 自动继承）。

### Payment availability rule_set —— 同一过渡期 metadata 形态（D8, 2026-09-15）

同一份 `private_metadata['options'][i]` **additive** 增加 `rule_set`（无新表、无 migration；正式表仍待 §74 的
`pallastrade_payment_options`）：

```json
{
  "kind": "card", "active": true, "position": 1,
  "rule_set": {
    "match": "all",
    "include": [
      { "dimension": "market", "operator": "in", "values": ["12"] },
      { "dimension": "currency", "operator": "in", "values": ["EUR"] }
    ],
    "exclude": [ { "dimension": "country", "operator": "in", "values": ["US"] } ]
  }
}
```

- **读归一**：`PaymentMethod#payment_option_rule_set(kind)` / `payment_option_scope_summary(kind, labels:)`；
  规则集归一在 `PallasTrade::Payments::Availability::RuleSet.normalize`（非法维度/算子/空 values 丢弃；
  include+exclude 皆空 → `nil` = 全局可用）。
- **值域**：`market`/`zone` = **原始整型 ID 字符串**（非 prefix ID；prefix 只存在于后台表单与 API 投影）；
  `country` = 大写 ISO2；`currency` = 大写 ISO 4217。
- **后台不落库的输入**：capability 之外的维度（如 `amount`）、跨店 market ID、未知国家/币种 —— 写入时丢弃。

## Customer / User

```
PallasTrade.user_class (typically PallasTrade::User)
  ↓
Address (many, via pallastrade_addresses)
CreditCard (many)
GiftCard (many)
StoreCredit (many)
```

Use `PallasTrade.user_class` and `PallasTrade.admin_user_class` to reference user models — never `PallasTrade::User` directly. Apps can swap in their own user model via configuration.

### 用户黑名单（P8, 2026-08-28）

`pallastrade_users.blacklisted_at`（datetime，可空）——用户拉黑时间戳。由 `PallasTrade::Risk::BlacklistRule` 在下单前置校验时拦截（命中 → `user_blacklisted` 错误）。

## Adjustments (polymorphic)

```
Adjustable (Order, LineItem, Shipment) ← Adjustment
```

`Adjustment` is polymorphic — it attaches to any Order, LineItem, or Shipment via `adjustable_type` + `adjustable_id`. Each Adjustment has a `source` (the thing that created it: a TaxRate, PromotionAction, ReturnAuthorization, etc.) and built-in scopes to filter by source type:

```ruby
order.adjustments.tax                     # source_type: 'PallasTrade::TaxRate'
order.adjustments.promotion               # source_type: 'PallasTrade::PromotionAction'
order.adjustments.return_authorization
order.all_adjustments                     # adjustments on order + its line_items + shipments
```

## Prefixed IDs

Every PallasTrade model exposed via the v3 API has a Stripe-style prefixed ID:

```ruby
product.prefixed_id  # => "prod_86Rf07xd4z"
order.prefixed_id    # => "or_m3Rp9wXz"
variant.prefixed_id  # => "variant_k5nR8xLq"
```

IDs are computed from the integer PK via Sqids — no database column. The prefix is declared per-class via `has_prefix_id :<prefix>` on the model. The v3 API accepts and emits prefixed IDs everywhere; `find_by_prefix_id!` resolves them back to integer PKs.

The prefix is an **ownership constraint**, not decoration (PRD-20260914-other-prefixedid-ownership-validation, research §9.1 P0-f): `find_by_prefix_id!` / `find_by_prefix_id` only resolve ids carrying the caller class's own declared prefix — a foreign id (`or_…` passed to `Product`) raises `RecordNotFound` (404) or returns `nil` / empty set for filter-style lookups, never the other resource that happens to share the integer PK. `decode_prefixed_id` (module level) stays prefix-agnostic for generic parsing paths (ParamsNormalizer, exports, search providers); ownership-aware paths use `decode_with_prefix` / `decode_owned_prefixed_id`. When adding a model, pick a **globally unique** prefix — `backend/spec/models/pallastrade/prefixed_id_spec.rb` requires zero duplicate `has_prefix_id` declarations (the former `ps` collision between PaymentSession and PaymentSource was removed on 2026-09-14 by giving PaymentSource the `src_` prefix).

Conventions for the prefix:

- Long form for some resources: `prod` (Product), `variant` (Variant)
- Short codes for most others: `or` (Order), `py` (Payment, Stripe parity), `adj` (Adjustment), `li` (LineItem), `ctg` (Category/Taxon), `cus` (customer, Stripe parity), `ch` (Channel), `mkt` (Market)

Never expose raw integer PKs in API responses.

## `state` vs `status` (mixed on 5.5)

Different models use different column names depending on when they were introduced:

- `Order.state`, `Payment.state`, `Shipment.state` — older state machines
- `OrderApproval.status` — newer status column
- `Channel` doesn't use a state machine — it has an `active` boolean instead

When writing model code, follow the convention of the column the model actually has. When querying, check the model's source if you're not sure.

## `PallasTrade::Current` (per-request context)

Avoid passing store / currency / locale around as arguments. Use the ambient context:

```ruby
PallasTrade::Current.store      # The store handling this request
PallasTrade::Current.currency   # The currency to display prices in
PallasTrade::Current.locale     # The locale for translations
PallasTrade::Current.channel    # The resolved sales channel (falls back to the store's default channel)
PallasTrade::Current.market     # The resolved market (falls back to the store's default market)
```

Available in models, controllers, jobs, and services. Set automatically by controller before_actions on the API (with built-in fallbacks to store defaults inside `PallasTrade::Current`); you set it manually in jobs and rake tasks that need to address a specific store.

## When to read further

- **Field-level docs:** `node_modules/@pallastrade/docs/dist/developer/core-concepts/<topic>.md` for each model.
- **OpenAPI spec:** `node_modules/@pallastrade/docs/dist/api-reference/store.yaml` lists every API field and its type — better than guessing from the model source.
- **Adding new models / API resources:** use the `pallastrade-resource` skill.
- **Extending existing PallasTrade models** (add an association, validation, scope, method via decorator): use the `pallastrade-decorators` skill.

## Dispute fee / partial & multi-dispute (DSP-P7-9, 2026-09-13)

- `pallastrade_disputes.fee_amount` (decimal, nullable) is now **written once** by `Disputes::CaptureFee`
  (nil → value; replays never overwrite). There is **no** `fee_currency` column — the fee is booked in the
  dispute's own `currency` (provider evidence: the fee sits on the dispute's adjustment BT in the same currency).
- `FinancialFact::FACT_TYPES` and `FinancialLedgerEntry::ENTRY_TYPES` gained **`DISPUTE_FEE`** (append-only;
  `PSP_FEE` / `PSP_NET_SETTLEMENT` remain FIN-P4-5 reservations). The fee is an **outflow** entry that shares the
  provider BT reference with `DISPUTE_FUNDS_WITHDRAWN` but has its own posting key, and it is **never reversed**
  (a win reinstates the disputed amount only).
- Partial amounts and 1:N disputes per payment stay first-class (unique key stays
  `(provider, provider_dispute_reference)`); the disputed amount always comes from the dispute snapshot —
  `Dispute#partial?` is a derived, read-only predicate (no `payment` anchor → `false`, never guessed).
- Read-only projections introduced by this slice (`Disputes::PaymentDisputeSummary`) write nothing: payment-level
  totals are computed on the fly and withheld when currencies differ.

## Changelog (P0 Payment, 2026-09-03)

- INV-P3 (2026-09-05, PRD-20260905-shipping-库存事务集成与预留生命周期-p3): pallastrade_stock_reservations 生命周期状态化（state default 'reserved' + reserved/committed/released/expired_at + release_reason + commerce_transaction_id 可空 FK；唯一约束改 partial unique WHERE state='reserved'；索引 (stock_item_id,state,expires_at)）；StockReservation 状态机 RESERVED→COMMITTED（canonical physical consumption 后的事实确认，不改 count_on_hand）/RELEASED/EXPIRED，Release/Expire 不再硬删除；commerce_transactions +snapshot_schema_version（V2：snapshot_data.schema_version + participant inventory_demand evidence）；**无 lock_version**（沿用 with_lock+state guard，与 CommerceTransaction 一致）。

- TXN-P2-1 (2026-09-04, PRD-20260904-checkout-txn-p2-1): 新表 pallastrade_commerce_transactions（txn_，state/purpose/checkout_version/price_version/snapshot_fingerprint/snapshot_data jsonb/amount/currency/payment_combination_id 可空/生命周期时间戳/recovery_attempts/last_error_*）+ pallastrade_transaction_orders（transaction_id+order_id 唯一，role primary|participant，amount_snapshot，completion_status pending|completed|failed）。CommerceTransaction 为 durable 编排上下文（非 payment aggregate；snapshot 为 immutable 证据非价格源）；状态机 created→payment_pending→payment_confirmed→finalizing→completed（+canceled/recovery_required/manual_review；禁止 payment_confirmed→payment_pending）。**无 lock_version 列**（同上 CHK-P1-2 教训）。

- P0 (2026-09-03): 新表 pallastrade_payment_webhook_events（provider/provider_event_id UNIQUE/status/attempt_count/payload）、pallastrade_audit_logs（actor/resource/request_id/before/after）；pallastrade_payments.payment_session_id FK（P0-1）。
- CHK-P1-2 (2026-09-03): pallastrade_orders 新增 checkout_version(integer default 0)/price_version(string)/checkout_expires_at(datetime)（lock_version 曾短暂加入后移除——AR locking_column 被 state_machines 占用）。

- F-5 (2026-09-16, PRD-20260916-catalog-batch-f5-helpful-vote): 新表 **pallastrade_review_votes**（`review_id` / `user_id` / `store_id` + 时间戳；唯一索引 `(review_id, user_id)` = 一人一票的**数据层**保证，前缀 `rv`）+ `pallastrade_reviews.helpful_votes_count`（integer default 0 / NOT NULL，**counter cache**，使列表读票数不产生 N+1）。投票始终带身份（顾客 JWT），但对外只暴露聚合值与调用者自己的状态——**永不暴露投票者**；只有 `approved` 评论可被投票（与读者可见范围同源）。

- D-3 (2026-09-16, PRD-20260916-catalog-d3-product-merge): 新表 **pallastrade_product_merges**（`store_id` / `survivor_id` / `absorbed_id` + actor 快照 + `moved`/`counts`/`skips` jsonb + `redirect_ids` jsonb + `absorbed_status_before` + `undone_at`/`undone_by_label`；partial unique `(store_id, absorbed_id) WHERE undone_at IS NULL` = 同一被合并商品同时只有一条**未撤销**的合并，前缀 `pmg`）。合并**只改归属**：历史交易表（line_items / orders / payments / commerce_transactions）零改写；被合并商品用 `update_columns(deleted_at:)` **纯软删**（不走 `dependent: :destroy`）；台账的关联必须带 `with_deleted`（被合并商品合并后就是软删状态）。

- G-7 (2026-09-16, PRD-20260916-catalog-health-trend-snapshot): 新表 **pallastrade_catalog_health_snapshots**（`store_id` / `issue_key`（必须 ∈ `CatalogHealth::Issues::KEYS`）/ `captured_on`(date) / `count`(integer NOT NULL default 0)；唯一索引 `(store_id, issue_key, captured_on)` = 同店同日同 issue **只有一行**，让补跑/重跑**幂等**——先例 `(order_id, evaluated_at)`）。设计要点：**每日一行而不是事后重算**——issue 判定口径会随代码演进（如 `old_drafts` 的 30 天阈值），历史必须按**当日口径**保存，重算 = 篡改历史；计 0 也要留行（0 是事实，“没有行”是缺失）。
