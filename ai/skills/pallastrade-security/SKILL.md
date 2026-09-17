---
name: pallastrade-security
description: Use when the user is hardening a PallasTrade app, responding to a security finding, reviewing a PR for security issues, setting up secrets management, configuring CSP/CORS, or asking about PallasTrade-specific security (CanCanCan scopes, encrypted preferences, webhook HMAC, PCI scope). Covers both standard Rails security practices (CSRF, mass assignment, SQL injection, secrets in repo) AND the PallasTrade-specific pieces (publishable vs secret keys, scope enforcement, SSRF on webhooks, CanCanCan abilities). Common phrasings include "PallasTrade security", "CSP", "CORS", "secret key", "leaked key", "SQL injection", "Strong Params", "CanCanCan", "PCI", "webhook signature", "SSRF".
---

# PallasTrade Security

## Payment credential levels & environment（D9, 2026-09-15；PRD-20260915-payments-d9）

- **分级（勿自创字段）**：`:password` 型 preference = `secret`；provider 在 `public_preference_keys` 声明的 = `publishable`；其余 = `internal`。读分级用 `PaymentMethod#credential_level(key)`（webhook 签名密钥不在 preference 体系内，见 provider 的 webhook key 表）。
- **`env:NAME` 引用**：凭证值可写成 `env:STRIPE_SECRET_KEY` —— **库中只存引用**（绝不落明文），读取侧用 `PaymentMethod#resolved_preference(key)` 解析（ENV 缺失 → `nil`，**不得 raise**）。写入/展示路径继续走 `Preferences::Masking`（`••••` + 后 4 位）。
- **reveal（看明文）**：唯一的明文出口，必须同时满足①资源 `update` 权限②默认管理员角色（owner 等价）；成功**必须**写审计 `payment_method_credential_revealed`（只记 `key` + actor，**绝不记值**）；未知 key → 422。
- **环境隔离**：`environment = test` 的 provider 不进前台列表（`Payments::Availability::Resolver` frontend scope），会话/支付打 `test_mode`；切 test 时强制 `storefront_visible = false`。
- **轮换/到期**：元数据在 `private_metadata['credentials'][key] = { rotated_at, expires_on }`；日巡检 `PaymentMethods::CredentialExpiryCheckJob` 在 30/7/1/expired 档告警（同级别幂等，写 `credential_alerts` + 审计）。
- 回归：`harness verify d9-credentials-rspec`。


PallasTrade inherits Rails' security model and adds an e-commerce attack surface (payment data, customer PII, admin credentials, webhook endpoints). This skill covers both.

## The threat model in three sentences

1. The **storefront** is internet-facing — every visitor can hit it. Threats: XSS via product content, IDOR on orders, abuse of cart endpoints.
2. The **admin** is staff-only but credentials get phished — assume someone is going to log in as a regular admin sometimes. Threats: privilege escalation, broad data exfiltration, malicious extension upload.
3. The **payments path** touches money and PCI. Threats: card data leaking into logs/DB, gateway response tampering, refund abuse.

Everything below maps to one of these.

## Standard Rails security (don't skip these)

### Secrets — not in the repo

Production credentials live in `config/credentials.yml.enc` (Rails encrypted credentials) or environment variables. **Never** check raw secrets into git.

```bash
# Read credentials
EDITOR="code --wait" bin/rails credentials:edit --environment production

# Look up
Rails.application.credentials.stripe[:secret_key]
```

If a secret leaks into a commit (even on a private repo): **rotate immediately**, then rewrite history (`git filter-repo`, `bfg`). Rotation order:
1. Rotate the key in the provider (Stripe, AWS, etc.).
2. Update credentials/env.
3. Deploy.
4. Then clean history. The order matters — clean history first and the leaked key keeps working until rotation.

The PallasTrade Agent Skills plugin (installed via `/plugin install pallastrade@pallastrade` in Claude Code) ships a PostToolUse hook that warns when Claude appears to be writing a known-shape secret (Stripe live keys, AWS keys, GitHub PATs, OpenAI/Anthropic keys, plaintext sensitive env names). It's a tripwire, not a substitute for review.

### Strong Parameters

Always whitelist params in controllers; never `params.permit!` or splat user input into mass-assignment:

```ruby
# ✅
def permitted_params
  params.permit(:name, :description, :slug, metadata: {})
end

# ❌ — accepts anything, including admin_id / is_admin / etc.
PallasTrade::Product.create!(params[:product])
```

PallasTrade v3 controllers use flat `params.permit(...)` — no nested wrapping. See `pallastrade-api-v3` and `pallastrade-resource` for the convention.

### SQL injection

Use parameterized queries:

```ruby
# ✅
PallasTrade::Product.where('price > ?', user_value)
PallasTrade::Product.where(price: user_value)

# ❌ — string interpolation
PallasTrade::Product.where("price > #{user_value}")
```

Ransack is safe by default — but only filters on **allowlisted** attributes. Declare per model:

```ruby
self.whitelisted_ransackable_attributes = %w[name slug created_at price]
self.whitelisted_ransackable_associations = %w[variants categories]
self.whitelisted_ransackable_scopes = %w[available in_stock]
```

Filtering on an un-allowlisted attribute is silently ignored — Ransack's default `ignore_unknown_conditions: true` drops the unknown condition (PallasTrade's v3 controllers call `ransack`, not `ransack!`), so the user can't exfiltrate `password_digest` via `q[password_digest_eq]=...`. But there's no error signal either: the response is 200 and that filter simply doesn't apply, while any valid conditions in the same query still do.

### Mass assignment

Same answer as Strong Parameters above — `params.permit` is the mass-assignment defense; nothing extra is needed on the model.

Do **not** reach for `attr_readonly` here: it blocks *all* writes after creation, not just mass assignment. With Rails 7.1+ defaults, assigning a readonly attribute on a persisted record raises `ActiveRecord::ReadonlyAttributeError` (on older defaults the write is silently dropped). Putting it on `encrypted_password` breaks Devise password changes and password resets for every existing user. Reserve `attr_readonly` for genuinely immutable columns:

```ruby
class PallasTrade::Order < PallasTrade.base_class
  attr_readonly :number  # generated once, never changes
end
```

### CSRF

Rails handles CSRF for browser sessions automatically (`protect_from_forgery with: :exception`). API controllers skip CSRF (token auth replaces it). **Don't disable CSRF on form-rendering controllers** — that's how XSS becomes RCE-via-admin.

### CSP (Content Security Policy)

Lock down what scripts/styles/images can load:

```ruby
# config/initializers/content_security_policy.rb
Rails.application.config.content_security_policy do |policy|
  policy.default_src :self
  policy.font_src    :self, :https, :data
  policy.img_src     :self, :https, :data
  policy.script_src  :self, 'https://js.stripe.com'
  policy.style_src   :self, :unsafe_inline   # the Rails admin's inline styles need this; relax over time
  policy.connect_src :self, 'https://api.stripe.com'
end
```

The storefront should have a stricter policy than the admin. If your storefront uses a separate domain (Next.js consuming the Store API), set CSP on that app, not on the Rails app.

### XSS

Rails auto-escapes ERB output. Where you raw-render user content (rich text descriptions, product copy from CSV import), sanitize:

```ruby
ActionController::Base.helpers.sanitize(product.description, tags: %w[p br strong em a ul li], attributes: %w[href])
```

Sanitize before storing OR before rendering, but pick one and be consistent.

### CORS

PallasTrade also ships an admin-manageable CORS allowlist for the Admin API — per-store `PallasTrade::AllowedOrigin` records (validated to be origin-only http(s) URLs), managed in the dashboard under Settings → Allowed origins or via the Admin API (`/api/v3/admin/allowed_origins`). The pallastrade-starter app's `config/initializers/cors.rb` consults it dynamically (cached, exact-match in production) for `/api/v3/admin/*` with `credentials: true` — so admin/dashboard origins belong in that allowlist, not in hand-written `allow` blocks. For your storefront origin on `/api/v3/store/*`, add a static `allow` block as shown below.

If your storefront is a separate origin (typical for Next.js):

```ruby
# config/initializers/cors.rb
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins 'https://my-storefront.com', /https:\/\/.*\.my-storefront\.com/
    resource '/api/v3/store/*',
             headers: :any,
             methods: %i[get post put patch delete options],
             expose: %w[x-pallastrade-api-version]
  end
end
```

**Never `origins '*'` in production** for paths that accept credentials. Allowlist explicit storefront origins.

## PallasTrade-specific security

### Publishable key vs secret key

```
pk_*  — Publishable key.  Safe to ship in client-side code.  Identifies store, permits public Store API endpoints only.
sk_*  — Secret key.       Server-to-server only. Never bundle into mobile apps or browser JS.
```

A leaked `pk_` is annoying but not catastrophic (rate limit, rotate). A leaked `sk_` is a breach — rotate immediately and audit `PallasTrade::WebhookDelivery`/admin audit logs for unauthorized activity.

### Scopes on secret keys

When creating a secret key for an integration (Settings → API keys → Create secret key), grant **only the scopes the integration needs**. Don't hand out `write_all` to every app.

```
Need to sync orders out? → read_orders
Need to update inventory? → write_stock
Need to create refunds? → write_refunds
```

If the integration is later compromised, the blast radius is limited to what its scopes permit. The full scope list is in the `pallastrade-api-v3` skill.

### CanCanCan abilities (admin JWT auth)

Admin users authenticate via JWT and authorize via `PallasTrade::Ability`, which builds permissions from Permission Sets assigned to the user's roles. Customize by defining a permission set and assigning it to a role:

```ruby
# app/models/my_app/permission_sets/wholesale_orders.rb
module MyApp
  module PermissionSets
    class WholesaleOrders < PallasTrade::PermissionSets::Base
      def activate!
        # Wholesale managers can read+update wholesale orders but never destroy
        can [:read, :update], PallasTrade::Order, channel: { code: 'wholesale' }
        cannot :destroy, PallasTrade::Order
      end
    end
  end
end
```

```ruby
# config/initializers/pallastrade.rb
Rails.application.config.after_initialize do
  PallasTrade.permissions.assign(:wholesale_manager, [
    PallasTrade::PermissionSets::DashboardDisplay,
    MyApp::PermissionSets::WholesaleOrders
  ])
end
```

(The role itself must exist: `PallasTrade::Role.find_or_create_by(name: 'wholesale_manager')`.)

Defaults are restrictive — users with no roles get only `PallasTrade::PermissionSets::DefaultCustomer`. Build up explicit grants per role by composing built-in sets (`OrderManagement`, `ProductDisplay`, `StockManagement`, …) with custom ones; don't hand every role `SuperUser`.

### DB-driven role permissions (2026-08-16, admin)

Since the permission-system refactor, **admin roles are authorized from the DB** (`PallasTrade::RolePermission`), not only code permission sets:

- `PallasTrade::Ability#apply_permissions_from_db` reads the user's role permissions; if any exist for the user's roles, DB fully drives (set/function/menu/data). The `admin` role is seeded with `set: SuperUser` via `Role.default_admin_role`. Users with no DB-configured roles fall back to code permission sets (`DefaultCustomer` etc.).
- **function** grants are `resource × action` (read/create/update/destroy/export/manage). `manage` = all actions. Each grant also implies `:admin` on that resource (admin-panel entry gate).
- **data** grants scope reads via CanCanCan conditions so `accessible_by` filters lists (scope: `self` → `user_id = current user`, `store`/`channel` → the configured value, `custom` → admin-supplied simple hash). Resources must be registered in `PallasTrade::PermissionRegistry` (`backend/config/initializers/pallastrade_permission_registry.rb`).
- **menu** grants control sidebar visibility (`ability.menu_permissions`); a DB-driven role's menu tree is decided entirely by menu grants.
- Admin role-permission editing happens in the Roles edit page (three tabs: menu/function/data) — see the `pallastrade-admin` skill. `nav:validate` enforces that permission resources are registered.

**Capability = 资源 × 覆盖模型集合（2026-09-11, PRD-20260911-promo-batch5b）**：注册表的每个资源声明 `models`（覆盖模型），Ability 对该集合内**每个模型**授予同一 action。后台每个控制器按自己的模型类 `authorize!`，所以：

- 一个后台功能若跨越多个模型（如促销：`Promotion` / `PromotionRule` / `PromotionAction`），注册表必须全部列出——否则 DB 角色会被"授权了却打不开页面"（失权而非越权，但同样是权限事实与 UI 不一致）；
- 代码级权限集不再各自硬编码模型：用 `grants_registry_resource :promotions, :coupon_codes` 从注册表派生（`PermissionSets::Base`），保证"矩阵能配的 = 代码集能授的 = 控制器能开门的"；
- 数据范围条件按目标模型派生：模型无该列时经 `belongs_to` 上卷（`{ promotion: { store_id: … } }`），并按列类型转换 `scope_value`（否则字符串永不等值于整数列 → 静默失权）；不能表达时**保持原条件**（查询期显式报错），不回退为无条件放行；
- 变更权限/注册表后必须跑 `bundle exec rake pallastrade:permissions:validate`（`STRICT=1`）+ `pallastrade:admin:nav_validate`，并复核 `spec/models/pallastrade/ability_db_spec.rb`、后台权限 request spec。

Keep `set`-type permissions (SuperUser) out of the rebuild path — the UI never edits them.

### Payment method preferences

Payment methods (Stripe, Adyen, PayPal, etc.) store their gateway credentials as PallasTrade preferences on the `PallasTrade::PaymentMethod` record. These end up in `pallastrade_payment_methods.preferences` as a serialized column.

Two precautions:

- **Gateway preferences are stored UNENCRYPTED** as serialized YAML in `pallastrade_payment_methods.preferences` — treat the database and its backups as containing live secrets. Two pieces of key material do matter elsewhere: keep `secret_key_base` stable, because secret API key authentication HMAC-SHA256s tokens with it (rotating it invalidates every `sk_` key; publishable `pk_` keys are unaffected), and configure `active_record_encryption` credentials consistently, because webhook endpoint secrets are encrypted with ActiveRecord::Encryption when those keys are present.
- **Use the admin UI to enter live keys** (Settings → Payments → edit method), not seed scripts or direct DB writes. Treat preference rows as containing live secrets; back up encrypted.

If a gateway secret leaks (committed to git, exposed in a log, copied to a chat), rotate at the provider first (Stripe dashboard, Adyen back office), then update the admin preference, then audit recent transactions.

### Webhook signature verification (HMAC)

Outbound webhooks are signed with HMAC-SHA256. **Receivers MUST verify** — see the `pallastrade-events-webhooks` skill for the exact algorithm + timing-safe comparison + replay rejection. PallasTrade won't tell you if your receiver is unverified; that's the receiver's responsibility.

### Webhook SSRF protection

Inbound URL validation: in production, webhook endpoint URLs are checked against private IP ranges (RFC 1918, loopback, link-local) via `ssrf_filter`. Admin can't (easily) make PallasTrade POST to `http://internal-erp.localhost:8080` from outside the trusted network.

In development this is disabled so localhost webhooks work. **Never run development settings in production**; this gap is a real SSRF in deployed apps if you copy `Rails.env.development?` checks blindly.

### PCI DSS scope

PallasTrade never stores raw PANs. Payment data flows through tokenization at the gateway:
- **Stripe** (via `pallastrade_stripe`) — card data goes browser→Stripe directly via Stripe Elements / Checkout. PallasTrade only sees a payment-method token.
- **Adyen** (via `pallastrade_adyen`) — same pattern; the drop-in component returns a tokenized reference.
- **`PallasTrade::CreditCard`** stores last4, brand, exp month/year — never the full PAN, never the CVC.

PCI scope reduction relies on this. **Don't add fields to `pallastrade_credit_cards` that hold raw card data.** If you find yourself wanting to, it's a sign you're building the wrong integration pattern — gateway tokenization is the right answer.

If a regulator asks for your PCI SAQ:
- Using only tokenizing gateways with hosted fields: SAQ A-EP or SAQ A.
- Self-collecting card data anywhere: SAQ D (full audit). Don't go here.

### Customer-data isolation

Multi-store stores share a database. **Always scope queries through `current_store`**:

```ruby
# ✅
@orders = current_store.orders.where(user: current_user)

# ❌ — leaks orders from other stores
@orders = PallasTrade::Order.where(user: current_user)
```

The Store API does this automatically via the `PallasTrade::Api::V3::Store::ResourceController` base class. Custom controllers must replicate the pattern.

### IDOR (Insecure Direct Object Reference)

Customer A trying to load `/api/v3/store/orders/or_<customerB_order>`. The Store API's `OrdersController#scope` restricts to the current user's orders (or the guest order token), so the lookup returns 404 — but if you override `scope`/`find_resource` or write a custom controller, you must replicate that scoping.

Prefixed IDs don't help here — they're discoverable (sequential PKs under the hood). **Always authorize, never rely on ID opacity.**

### Rate limiting

PallasTrade's v3 API ships application-level rate limiting out of the box, built on Rails' `rate_limit` and backed by `Rails.cache`:

- **All v3 endpoints**: 300 requests / 60s, keyed by the `X-PallasTrade-Api-Key` header (falling back to client IP when no key is sent).
- **Auth endpoints** (per IP, to stop brute force): login 5/60s, registration 3/60s, token refresh and logout 10/60s, password reset 3/60s. Admin login/refresh and invitation acceptance get the same treatment.

Exceeding a limit returns `429` with error code `rate_limit_exceeded` and `Retry-After` / `X-RateLimit-*` headers. All limits are tunable via `PallasTrade::Api::Config` preferences: `rate_limit_per_key`, `rate_limit_window`, `rate_limit_login`, `rate_limit_register`, `rate_limit_refresh`, `rate_limit_password_reset`. One operational caveat: counters live in `Rails.cache`, so multi-process deployments need a shared cache store (Redis/Memcached) — with an in-process store each worker counts independently.

Still layer defense in depth on top:

- **Rack::Attack** for endpoints the built-in limits don't cover (Rails admin, storefront) and any custom throttling rules — don't duplicate the v3 auth throttles, they're already enforced.
- **CDN / load balancer** (Cloudflare, Fastly, AWS WAF) for the global ceiling and volumetric attacks.

Tune the numbers to your traffic shape — the defaults cap a leaked publishable key at 300 req/min, but a scraper rotating IPs without a key still warrants the CDN layer.

### 下单风控规则（P8, 2026-08-28，flag 灰度）

API 级 rate limit 之上叠加**业务级下单风控**（`PallasTrade::Risk` 规则引擎，见 `pallastrade-checkout` SKILL「前置校验」）：

- `users.blacklisted_at`（P8 新增列）→ `BlacklistRule` 命中 `user_blacklisted`。
- `order_frequency_limit`（同用户 N 分钟内完成订单数上限，默认 nil 关闭）→ `OrderFrequencyRule` 命中 `order_frequency_limit`。
- 自定义规则：`PallasTrade::Risk.rules << MyRule`（`#call(order:, user:, store:)` → `{ code:, message: }`）。
- 错误统一 `{ code:, message: }`（经 `render_service_error`），不泄露内部细节。

### 风控规则引擎：版本化 / 灰度 / 回滚（D15 切片2, 2026-09-17；PRD-20260917-payments-d15b-risk-rules）

P8 的代码注册式规则之上，本切片把**规则内容**搬到数据层 —— 运营可在后台维护、可回滚、可按流量灰度，无需发版：

- **数据**：`pallastrade_risk_rule_sets`（作用域容器：`store_id` 空 = 全局 / 非空 = 本店优先；`active_version_id` / `canary_version_id` / `canary_percent`）
  + `pallastrade_risk_rule_versions`（**不可变版本**：`rules` jsonb、`state` = draft/published/archived、`source_version` + `rolled_back` + `reason`）。
- **条件词汇（白名单，全部满足 = 命中）**：`amount_gte` / `amount_lte`（**仅当订单币种 == 店铺默认币种**才可比，否则 `currency_mismatch` 跳过）、`currency_in`、`country_in`、`email_domain_in`、`email_present`、`ip_present`、`card_brand_in`（归一 `mastercard|maestro → master`、`amex → american_express`）、`customer_orders_gte`、`velocity_count_gte`（+ `velocity_window_minutes`，同邮箱**或**同 IP，含当前订单）。
  ⚠️ **不可得主体不给条件键**：**BIN**（`pallastrade_credit_cards` 无 BIN 列）、**设备指纹**（平台无采集）、IP 地理/网段（无离线库）→ 一律不猜。
- **动作**：`allow` / `review` / `block`（本切片）；**`force_3ds` 属切片3（3DS/SCA 与 provider 下发）**。
- **发布闸门**：`Risk::Rules::Schema` 拒绝未知键 / 类型错 / 非法动作 / 空条件 / 重复规则码 / 超 50 条 / 非整数优先级 —— 校验不过**不落库**。
- **灰度（确定性分桶）**：桶 = `SHA256("<rule_set_id>:<order prefixed_id>") % 100`，`桶 < canary_percent` → 金丝雀版，否则稳定版；**桶只由（规则集, 订单）决定**（跨请求/跨天恒定、可复算）；`0` 恒稳定版、`≥100` 恒金丝雀、**桶 == percent 归稳定版**。
- **金丝雀与稳定版并存（发布语义）**：`set_canary(version:, percent:)` 时，草稿版会以金丝雀身份 `published`（**不动** `active_version_id`、**不归档**旧版）；已归档版拒绍（走回滚/新建）；`publish` 新版本后指向已归档版的**金丝雀自动清空**；`Evaluate` 只认**已发布**的金丝雀版（草稿/归档 → 回落稳定版，不猜）。
- **决策合并（唯一口径）**：白名单命中 → `allow` **短路**；否则「名单动作（`Config[:risk_denylist_action]`，默认 `review`）vs 规则动作」**取最严者**（`allow(0) < review(1) < block(2)`）—— **规则不得把名单判定放宽**。
- **留痕**：`PaymentRiskAssessment.signals['rule_engine']`（规则集/版本/是否金丝雀/桶/规则码/动作/命中条件/skip 原因）+ `metadata['rule_engine']`（jsonb，零迁移）。
- **回滚（验收锚点「规则可回滚」）**：`Risk::Rules::Versioning.rollback` 以历史版本内容**生成新版本**（`rolled_back: true` + `source_version` + `reason` **必填**）并置为生效版；**历史版本内容永不改写**（模型层拒绝改已发布版的 `rules`）；审计 `risk_rule_version_rolled_back` + 同名事件。
- **铁律**：规则求值**只读**（零写库、零 provider、不改订单/支付/资金）；**不改 `Checkout::Preflight` 的启用条件与阻断行为** —— 阻断生效仍由 flag 决定，本切片只保证决策可被消费（命中的 `review`/`block` 走既有 `risk_order_flagged` 审计与人工复核标记）。

### Dependency hygiene

```bash
bundle audit                # CVEs in Ruby gems
npm audit / pnpm audit      # CVEs in JS deps
brakeman                    # Rails static analysis
```

Run these in CI. The PallasTrade Agent Skills plugin doesn't ship an application security CI workflow — you wire these into your own.

### Admin upload safety

Admins can upload images and CSVs (imports). Risks:
- **Polyglot files** (image+JS) — sanitize uploads, set `Content-Type` strictly, serve from a different origin than the app domain (S3 + CloudFront, not `app.example.com/uploads/…`).
- **CSV formula injection** — sanitize fields starting with `=`, `+`, `-`, `@` before writing back to user-downloaded CSV exports.

### Sensitive logs

Rails param filtering is already largely in place: PallasTrade core registers `filter_parameters` for `:password`, `:number`, `:verification_value`, `:client_secret`, `:refresh_token` etc., and the pallastrade-starter app ships partial-match filters (`:passw, :email, :secret, :token, :_key, :crypt, :salt, :cvv, :cvc, …`) — partial matching means `:secret` already catches `secret_key`/`stripe_secret_key` and `:_key` catches `api_key`/`publishable_key`.

Treat this as defense-in-depth, not a solved problem: extend the list for any custom param name your app introduces that the partial matches don't cover, and verify what's actually filtered:

```ruby
# config/initializers/filter_parameter_logging.rb
Rails.application.config.filter_parameters += %i[card_number my_custom_credential]

# Verify in console:
Rails.application.config.filter_parameters
```

A param name that slips through the filters gets written verbatim to production.log by any form POST that carries it.

## A short checklist for a new PallasTrade deployment

- [ ] Production credentials in encrypted credentials or environment, **not** in repo.
- [ ] `secret_key_base` stable and managed via credentials — secret API keys are HMAC-digested with it (rotating it invalidates every `sk_` key) and it is the fallback JWT signing secret. Webhook endpoint secrets use ActiveRecord::Encryption, whose keys (`active_record_encryption.*`) must also live in credentials.
- [ ] CORS allowlist matches your storefront origin(s) only.
- [ ] CSP defined and not `default_src 'unsafe-inline'` everywhere.
- [ ] Brakeman + bundle audit + pnpm audit in CI.
- [ ] Rack::Attack rules for login + checkout endpoints.
- [ ] Webhook receiver verifies HMAC + checks replay timestamp.
- [ ] All staff admin users on real-name accounts with role-appropriate abilities (no shared "admin@" accounts).
- [ ] Secret keys for integrations granted minimum scopes.
- [ ] Filtered parameters configured for logs.
- [ ] Database backups are encrypted, restorable, and not stored next to the database.
- [ ] HTTPS-only (`config.force_ssl = true`).
- [ ] `Secure` + `HttpOnly` + `SameSite=Lax` on auth cookies.

## Where to read further

- **Rails Security Guide:** https://guides.rubyonrails.org/security.html — read it cover to cover at least once.
- **OWASP Top 10:** https://owasp.org/www-project-top-ten/ — annual update; the categories don't change much but the examples do.
- **PallasTrade credentials docs:** PallasTrade developer docs → "Authentication", "Permissions".
- **Webhook HMAC:** `pallastrade-events-webhooks` skill.
- **API scopes:** `pallastrade-api-v3` skill.
- **Payment data flow:** `pallastrade-payments` skill.

## Changelog (P0 Payment, 2026-09-03)

- P0 (2026-09-03): Gateway PaymentMethod.preferences 启用 Active Record Encryption（encrypts :preferences，ENV ACTIVE_RECORD_ENCRYPTION_* 门控 + support_unencrypted_data dual-read；backfill rake pallastrade:payments:encrypt_preferences）；Masking 不变；凭据轮换建议见 docs/payment/security.md。

