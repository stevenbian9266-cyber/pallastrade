## 2026-07-15: Basic Stripe Connect payouts move to OSS; Enterprise repositions on money operations

stevenbian9266-cyber/pallastrade#13323 originally kept "Stripe Connect onboarding, KYC, automatic
payouts" in Enterprise. Amended by the issue author: the **basic** Stripe Connect
path ships **open-source in the monorepo**, registering
`PallasTrade::PayoutProvider::StripeConnect` — Express-account onboarding (hosted link +
`account.updated` status webhook) and on-fulfillment `Stripe::Transfer` execution
(`source_transaction`-tied), plus mapping the vendor payout schedule onto Stripe's
native schedule. It lands alongside the Stripe core gateway being pulled into the
monorepo from the standalone `pallastrade_stripe` repo — only the payment-sessions-API
gateway classes come over (likely into `pallastrade/core`); the legacy v2-API/storefront
code in that repo stays behind.

Rationale: the closest OSS competitor ships baseline Stripe transfers free —
"money moves automatically" is the demo that sells — and transfers are inseparable
from basic onboarding (a `Stripe::Transfer` requires a connected account), so a
transfers-only OSS cut was never buildable.

Enterprise keeps the money **operations**: automatic refund clawbacks (prorated
transfer reversals + negative-balance netting), KYC/account-health workflows beyond
hosted onboarding, ledger⇄Stripe reconciliation, payout reports incl. DAC7,
marketplace-facilitator taxes, and the Shopify/WooCommerce vendor apps. Ledger
correctness (reversal rows) stays OSS in every mode — only pullback execution is
paid. "Core runs the happy path; Enterprise operates the unhappy paths and
compliance at scale." #13323 to be updated accordingly.
Plan: `6.0-multi-vendor-marketplace.md`.

## 2026-07-14: `PallasTrade::Vendor` = marketplace seller; procurement source renamed `PallasTrade::Supplier`

Two 6.0 plans introduced a `PallasTrade::Vendor`: the marketplace seller
(`6.0-multi-vendor-marketplace.md`, prefix `ven_`) and the purchase-order
procurement source (`6.0-inventory-operations.md`, prefix `vnd_`). Same class
name, same `pallastrade_vendors` table, different domains — a hard collision.

Resolution: **the marketplace owns the `Vendor` name.** It is locked publicly
(stevenbian9266-cyber/pallastrade#13323, the user docs' "Vendors" area, the legacy Enterprise gem's
`ven_` prefix and its production data). The inventory-operations model is renamed
**`PallasTrade::Supplier`** (`pallastrade_suppliers`, prefix `sup_`, `/api/v3/admin/suppliers`) —
matching Shopify's purchase-order vocabulary and standard ERP terminology. They
are different lifecycles: a supplier is an address-book entry the merchant buys
stock from; a vendor is an onboarded selling party with users, commission, and
payouts.

Hybrid marketplaces (operator buys wholesale from a marketplace seller and
resells first-party) can later bridge the two with an optional
`PallasTrade::Supplier#vendor_id` link — not scoped for 6.0.

## 2026-06-16: Split 6.0 into Marketplace, defer B2B to 6.1

6.0 is themed as the **Marketplace release**, headlined by open-sourcing the
multi-vendor marketplace (per stevenbian9266-cyber/pallastrade#13323) alongside React dashboard GA and
the architecture/rename wave. B2B (Catalog + Company/CompanyLocation/CompanyContact
from `6.0-channels-catalogs-b2b.md` Phase 2) moves to **6.1**, marketed as the B2B
release. Rationale: a crowded 6.0 dilutes the launch; one sharp headline per release
earns more buzz, and the B2B Phase 2 work is plan-only (not started), so deferring
it frees capacity for the multi-vendor open-sourcing rather than parking finished code.

Multi-vendor OSS/Enterprise boundary per #13323 as of this date (**superseded in
part by 2026-07-15 above** — basic Stripe Connect execution later moved to OSS):
core ships Vendor identity, order splitting, the commission engine (with EU
commission taxation), the payout ledger (`PallasTrade::VendorPayout` — records what's
owed, provider-agnostic), vendor dashboard, CSV import/export, and Vendors API;
Enterprise keeps Stripe Connect/KYC and the *execution* of payouts (a
`PayoutProvider::StripeConnect` strategy), payout reports, Shopify/WooCommerce
sales-channel apps, and the category mapper. New plan:
`6.0-multi-vendor-marketplace.md`. The legacy Enterprise multi-vendor module is
rebuilt as native core models on top of the 6.0 Cart/Order split.

## 2026-03-17: Rename StockItem → StockLevel
`PallasTrade::StockItem` → `PallasTrade::StockLevel`, `pallastrade_stock_items` → `pallastrade_stock_levels`.
Prefix ID: `si_` → `sl_`.

Every other platform uses "level" for this concept — Shopify (`InventoryLevel`),
Medusa (`InventoryLevel`), Vendure (`StockLevel`), Saleor (`Stock`). "Item" sounds
like a physical object; "level" correctly describes "the quantity of a variant at
a location."

Part of the 6.0 model rename wave. Includes renaming the FK columns
(`stock_item_id` → `stock_level_id`) on StockMovement, StockReservation, and
any other referencing tables.

## 2026-03-16: Rename user_id → customer_id on customer-facing models
As part of the User → Customer rename (6.0-platform-auth.md), rename `user_id`
foreign key columns to `customer_id` on all models where the FK references a
storefront customer (not an admin user).

**Rename to `customer_id`** (11 models — FK references PallasTrade.customer_class):
- `pallastrade_orders.user_id` → `customer_id`
- `pallastrade_addresses.user_id` → `customer_id`
- `pallastrade_credit_cards.user_id` → `customer_id`
- `pallastrade_store_credits.user_id` → `customer_id`
- `pallastrade_wishlists.user_id` → `customer_id`
- `pallastrade_gift_cards.user_id` → `customer_id`
- `pallastrade_gateway_customers.user_id` → `customer_id`
- `pallastrade_payment_sources.user_id` → `customer_id`
- `pallastrade_newsletter_subscribers.user_id` → `customer_id`
- `pallastrade_promotion_rule_users.user_id` → `customer_id`
- `pallastrade_customer_group_users.user_id` → `customer_id`

**Keep as `user_id`** (5 models — FK references PallasTrade.admin_user_class or is polymorphic):
- `pallastrade_imports.user_id` — admin who ran the import
- `pallastrade_exports.user_id` — admin who ran the export
- `pallastrade_reports.user_id` — admin who generated the report
- `pallastrade_state_changes.user_id` — admin who triggered the change
- `pallastrade_user_identities.user_id` — polymorphic (Customer or AdminUser)

Single migration renames all 11 columns. Model associations updated:
`belongs_to :user` → `belongs_to :customer` with `class_name: PallasTrade.customer_class`.

## 2026-03-16: PaymentMethod and DeliveryMethod become SingleStoreResource
Both PaymentMethod and DeliveryMethod (renamed from ShippingMethod) switch from
multi-store join tables (`StorePaymentMethod`, `StoreShippingMethod`) to
`SingleStoreResource` with direct `belongs_to :store`.

In practice, different stores have different currencies, zones, and provider
accounts — sharing the same payment/delivery config across stores is rare.
If a merchant wants the same config on two stores, they create two records.

Changes:
- Add `store_id` column to `pallastrade_payment_methods` and `pallastrade_delivery_methods`
- Data migration: for each join record, set `store_id`; duplicate methods linked
  to multiple stores
- Drop `pallastrade_store_payment_methods` and `pallastrade_store_shipping_methods` join tables
- Both models include `PallasTrade::SingleStoreResource` concern

## 2026-03-16: Fix promotion rule/action STI namespacing
Rename `PallasTrade::Promotion::Rules::*` → `PallasTrade::PromotionRules::*` and
`PallasTrade::Promotion::Actions::*` → `PallasTrade::PromotionActions::*`.

The convention for STI subtypes is `PallasTrade::{BaseClass}s::{Subtype}` — pluralized
base class as the namespace. Every other hierarchy follows this already:

- `PallasTrade::PriceRules::VolumeRule`
- `PallasTrade::Metafields::ShortText`
- `PallasTrade::CollectionRules::Tag` (from categories plan)
- `PallasTrade::ReimbursementType::Credit`

Promotion was the only one nesting under the parent model (`PallasTrade::Promotion::Rules`)
instead of the base class (`PallasTrade::PromotionRules`).

Changes:
- Move files from `app/models/pallastrade/promotion/rules/` → `app/models/pallastrade/promotion_rules/`
- Move files from `app/models/pallastrade/promotion/actions/` → `app/models/pallastrade/promotion_actions/`
- Data migration: update `type` column in `pallastrade_promotion_rules` and `pallastrade_promotion_actions`
  (e.g., `PallasTrade::Promotion::Rules::Product` → `PallasTrade::PromotionRules::Product`)
- Deprecation aliases for one release

## 2026-03-16: Normalize state → status across all models
Settle on `status` as the standard column name for state machines. Newer models
(Product, PriceList, PaymentSession, Import, Invitation) already use `status`.

Order.state and Adjustment.state are removed entirely by other 6.0 plans
(cart-order-split, split-adjustments). Five remaining models need a column
rename from `state` → `status` in 6.0:

- **Payment** — `state` → `status`
- **Shipment** — `state` → `status`
- **InventoryUnit** — `state` → `status`
- **ReturnAuthorization** — `state` → `status`
- **GiftCard** — `state` → `status`

Single migration renaming all five columns. State machine declarations updated
to `state_machine :status, initial: ...`. Deprecation aliases
(`alias_attribute :state, :status`) for one release.

Models already correct (no change): Product, PriceList, PaymentSession,
PaymentSetupSession, Import, ImportRow, Invitation, ReturnItem
(`reception_status`/`acceptance_status`), Reimbursement (`reimbursement_status`).

## 2026-03-28: Simplify metafield visibility — display_on → storefront_visible boolean (6.0)
Replace three-way `display_on` (both/front_end/back_end) with `storefront_visible`
boolean (default: true) on CustomFieldDefinition. `front_end`-only was already
excluded from `MetafieldDefinition::DISPLAY` and never made sense.

This makes the two-system boundary razor-sharp:
- Custom Fields (storefront_visible: true) = public structured data
- Custom Fields (storefront_visible: false) = admin-only structured data
- Metadata = private developer-owned data (never exposed)

Matches Vendure (`public: boolean`) and Saleor (`visibleInStorefront: boolean`).
Ships with the 6.0 model rename wave. See `5.4-6.0-custom-fields-rename.md`.

## 2026-03-16: Consolidate metadata — drop public_metadata, keep metadata JSON column
Drop `public_metadata` column (never exposed in Store API, unused). Rename
`private_metadata` → `metadata` in the database. Simplify the `PallasTrade::Metadata`
concern to a single `metadata` JSON column with no alias indirection.

**Metadata** (JSON column) is a permanent, first-class system — the schemaless
developer escape hatch for integration IDs, sync state, ad-hoc flags. No
definition required, one-step API:
`PATCH /product { metadata: { erp_id: "123" } }`. Never exposed in Store API
(Stripe convention: write-only). Metadata is here to stay.

**Metafields** (→ Custom Fields in 6.0, see `5.4-6.0-custom-fields-rename.md`)
stay as merchant-defined structured data — typed values (short_text, number,
boolean, json, rich_text, long_text), require a `MetafieldDefinition`, have
`storefront_visible` boolean, searchable, CSV importable. With the
ProductType plan (6.0-product-types.md), metafields become schema-enforced
custom attributes driven by ProductType.

Two systems, two purposes, no overlap. No consolidation into one.
Metadata for machines, metafields/custom fields for humans.

## 2026-03-10: Product descriptions stay as plain column
Considered Action Text. Rejected for API-first performance —
serializing rich text adds overhead for every product response.
Also in the new Admin UI we will use TipTap for rich text editing.
