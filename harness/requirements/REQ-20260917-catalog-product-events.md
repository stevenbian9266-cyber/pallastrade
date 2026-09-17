# REQ-20260917-catalog-product-events

| 元数据 | 值 |
|---|---|
| 关联 PRD | `docs/prd/catalog/PRD-20260917-catalog-product-events.md`（approved） |
| 关联 Task | `TASK-20260917125206-f4010353` |
| Gate | `GATE-2026-09-17T12-55-01` |
| 任务类型 | 新功能 |
| 分支 | dev |

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | analytics / tracking / event_log / telemetry | 无 | ❌ ABSENT |
| App — views/decorators | `backend/app/` | 同上 | 无 | ❌ ABSENT |
| Core Gem — models | `pallastrade_gems/pallastrade_core/app/models/` | event / analytics / track / metric | `base_analytics_event_handler.rb`（**外发**框架基类，`client`/`handle_event` 抽象，非落库）、`event.rb`、`store_credit_event.rb`、`payment_capture_event.rb`、`payment_webhook_event.rb` | ⚠️ 部分：有外发框架，**无商品行为落库** |
| Core Gem — services | `pallastrade_gems/pallastrade_core/app/services/` | catalog / events | 无商品事件服务 | ❌ ABSENT |
| API Gem — controllers | `pallastrade_gems/pallastrade_api/app/controllers/` | events / catalog_events | 无；**但找到公开 POST 写端点先例** `store/back_in_stock_subscriptions_controller.rb`（`allow_guest_storefront_access!` + 自带 `rate_limit`） | ⚠️ 需新建，模式可复用 |
| Admin Gem — controllers | `pallastrade_gems/pallastrade_admin/app/controllers/` | analytics / events 页面 | 无 | ❌ 需新建（本 PRD 明确不做） |
| Admin Gem — views | `pallastrade_gems/pallastrade_admin/app/views/` | analytics / events | 无 | ❌ 本 PRD 不做 |
| Storefront | `storefront/src/` | trackSelectItem / trackViewItemList / analytics | `lib/analytics/gtm.ts`（GA4 helper 全集）、`products/[slug]/ProductDetails.tsx`、`components/products/ListingAnalytics.tsx`、`components/products/ProductCard.tsx`、`components/search/SearchBar.tsx` | ⚠️ 埋点**已有**，但**只进 GTM dataLayer**，无回落 |
| Platform | `platform/packages/` | events / analytics | 无 | ❌ 需新建 SDK 方法 |

### 搜索结论

**已有**：① 前台 GA4 埋点与 4 个调用点；② 后台**外发**事件框架 `PallasTrade::Analytics`（词表已含 `product_viewed` / `product_list_viewed` / `product_added` / `product_searched`、handler 扩展点默认 `[]`）；③ 公开 POST 写端点的**现成模式**（`BackInStockSubscriptionsController`）。

**需新建**：事件表（自有库）+ Store API 采集端点 + 前台回落后半段 + SDK 方法。

**防重复判定**：不新建前台埋点（复用既有调用点），不新建后台外发框架（复用 `Analytics` 词表），**只补「表 + 端点 + 回落后半段」**。

---

## ⚠️ 本任务最大的发现：限流现状（更正初版 PRD 的错误结论）

### 初版 PRD 的错误

PRD v0.1 写「全仓**没有任何限流机制**」——**错误**。原因：只检索了 `Rack::Attack|rack_attack|throttle`，漏掉了 Rails 内置路径。

### 真实情况（已逐行读源码确认）

| # | 事实 | 证据 |
|---|---|---|
| 1 | 限流**存在**：Rails 8.1 内置 `rate_limit` | `actionpack-8.1.3.1/lib/action_controller/metal/rate_limiting.rb` |
| 2 | **全局声明在 `PallasTrade::Api::V3::BaseController`** | `backend/pallastrade_gems/pallastrade_api/app/controllers/pallastrade/api/v3/base_controller.rb:35` |
| 3 | 配额 `to: PallasTrade::Api::Config[:rate_limit_per_key]` = **300 / 60s** | 同上 |
| 4 | **计数键 = API key**（`by: -> { request.headers['X-PallasTrade-Api-Key'] … }`） | 同上 |
| 5 | **scope 默认 = `controller_path`** → **每个 controller 一个独立桶** | `rate_limiting` 内 `scope \|\| controller_path`；`RateLimitHeaders` 用同一 `['rate-limit', controller_path, by]` 印证 |
| 6 | **回调是匿名 lambda** → `skip_before_action` **无效**，子类**无法**摆脱父类限流 | `before_action -> { rate_limiting(...) }, **options` |
| 7 | 超限返回 **429 + `Retry-After`**，body `{error:{code:'rate_limit_exceeded',…}}` | `RATE_LIMIT_RESPONSE` |

### 由此得出的两条硬约束

- ✅ **好消息**：因 scope = `controller_path`，事件端点有**自己的桶**，**不会**挤占商品 / 购物车 / 结账的配额。
- ⚠️ **硬约束**：事件端点的桶按 **API key** 计数，而 storefront 全店**共用一个 publishable key** ⇒ 事件端点上限 = **300 请求 / 60s / 整店**。
- 🚫 **无法绕过**：该全局限流是匿名 lambda 回调，子类 `skip_before_action` 无效；唯一"绕过"是改 `PallasTrade::Api::Config[:rate_limit_per_key]`，那是**影响全 API 的全局变更**，不在本任务范围。

### 应对设计（已并入 PRD）

1. **重度批量**：客户端内存聚合，**每次页面浏览最多 flush 1 次**（`visibilitychange` / `pagehide` + `keepalive`）⇒ 天花板 = 300 页面浏览 / 60s / 店（可接受，且已文档化）。
2. **单请求承载体量大**：服务端单请求上限 **100 条**（客户端 flush 上限 100）。
3. **追加更严的 per-IP 限流**：新 controller 内再声明 `rate_limit by: -> { request.remote_ip }`（如 60/60s），使**单个滥用者**无法独占整店预算（两条限流同时生效，取更严者）。
4. **端点零外部调用**：常数代价，不发 GA4 / 不发 webhook / 不入队。

---

## Step 1：Skill 文件咨询（新功能 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（真实结论） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树优先级「**Settings → Configuration → Events → Dependencies → Admin/Ransack API → Generators → Decorators → Extensions**」；本需求 = 「Add a brand-new model + API endpoint」→ 走 **`pallastrade:api_resource` 生成器**（第 6 级），**不是** Decorator；并明确「Decorators are reserved for *structural* changes … for behavioral changes (callbacks, side effects, sync), use Events」 |
| `ai/skills/pallastrade-api-v3/SKILL.md` | ✅ 已读 | ① Store API **默认只读**（`index`/`show`），`create` 必须**显式 opt-in**；② 错误信封 `{error:{code,message,details}}`；③ **限流章节**：`rate_limit_per_key` 300/60s per API key，超限 `429` + `Retry-After`；④ 前缀 ID（`variant_…`）不可裸露整数 PK |
| `ai/skills/pallastrade-security/SKILL.md` | ✅ 已读 | ① Strong Parameters：**永远白名单**，`params.permit`，v3 用**扁平**参数、禁用 `wrap_parameters`，禁止 `params.permit!` / splat；② 「A leaked `pk_` is annoying but not catastrophic (**rate limit**, rotate)」——限流被定义为 publishable key 泄露的**第一道防线**；③ 密钥不进仓库 |

**按需 Skill（本次涉及）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-storefront` | ✅ 是 | ✅ 已读 | ① **「Client-component SDK calls go through server actions」** —— `PALLASTRADE_API_URL` / `PALLASTRADE_PUBLISHABLE_KEY` 是 **server-only env**（无 `NEXT_PUBLIC_` 前缀），`getClient()` 在浏览器**会抛错**；客户端组件必须调用 `src/lib/data/**` 的 `"use server"` action；② `"use server"` 模块**只能导出 async 函数**（导出常量会炸 `next build`，`pnpm typecheck`/`vitest` 抓不到）；③ `"use client"` 组件**不得**从 `@/lib/pallastrade` barrel 导入（会拉入 `next/headers` 使 build 失败）；④ CI 强制 `pnpm check`（Biome） |
| `pallastrade-data-model` | ✅ 是 | ✅ 已读 | 新表惯例：`store_id` + **唯一键作幂等键**（先例 `BackInStockSubscription` unique `[product_id,email]`；`RiskRuleVersion (rule_set_id,version)`）；沿用「**只新增表**、不回填、**零资金列**、不写 `funds_*`」范式 |
| `pallastrade-testing` | ✅ 是 | ✅ 已读 | ① 栈 = RSpec + Factory Bot（**非** Minitest/fixtures），测试放 `backend/spec/{models,requests,services}/`；② API 测试需 `require 'pallastrade/api/testing_support/v3/base'` + `include_context 'API v3 Store'`；③ **绝不用 `Model.create`，一律 factory**；④ 优先 `build` 而非 `create` |
| `pallastrade-prd` | ✅ 是 | ✅ 已读 | 阶段 2 第 5 步要求 `harness supervise plan` 固化 Change Plan；**AC 必须有测试覆盖，无测试的 AC 不允许标 done**；接口变更必须同步 `store.yaml` + `platform/docs/api-reference/` |
| `pallastrade-events-webhooks` | ⬜ 否 | — | 本 PRD **不做** outbound/webhook；走 Store API 请求内同步写，不订阅事件总线 |

---

## 需求标题

商品事件回流：把 PDP 曝光 / 点击 / 加购 / 搜索落到自有库，支撑 `Related Product CTR` 指标与后续推荐数据积累。

## 任务类型

新功能（新增表 + 新增 Store API 端点 + 前台回落 + SDK 方法）。

## 需求描述

目前商品行为数据**只进第三方 GTM**，店主无法在自有库查询、无历史、无法与自有商品关联。方案 §16 把 `PDP | Related Product CTR` 列为上线指标，但该指标所需的**分母（推荐位曝光）与分子（推荐位点击）都不存在**；方案 §14 亦明确「只有形成真实曝光/点击/加购/购买数据以后，才值得进入推荐算法阶段」。

本需求交付：**自有库商品事件表 + 采集端点 + 前台回落后半段**，使 CTR 可由自有数据计算。

**明确不做**：推荐算法、用户画像/个体追踪、后台消费页面、任何业务判定读取该表。

## 影响范围

- **DB**：新增 `pallastrade_catalog_events`（迁移**必须落 host app** `backend/db/migrate/` —— gem `db/migrate` 已停更，B1 教训）
- **Core gem**：`app/models/pallastrade/catalog_event.rb`、`app/services/pallastrade/catalog_events/**`
- **API gem**：`app/controllers/pallastrade/api/v3/store/catalog_events_controller.rb` + routes + serializer
- **Storefront**：`src/lib/analytics/catalog-events.ts`（纯函数）+ `src/lib/data/catalog-events.ts`（`"use server"`）+ 4 个既有调用点接入
- **Platform**：`@pallastrade/sdk` 新方法 + 契约再生成（`store.yaml` + `platform/docs/api-reference/`）
- **影响面**：`harness affected --base origin/dev`

## 技术方案（初步）

按决策树第 6 级（生成器新增资源）实现：

1. **表**：`store_id` / `event_id`（客户端 UUID，**唯一键=幂等键**）/ `event_name` / `product_id` / `variant_id` / `list_id` / `list_name` / `position` / `session_hash` / `occurred_at` / `metadata` / `created_at`；索引 `(store_id, occurred_at)`、`(store_id, list_id)`。追加写，**只 INSERT**。
2. **端点**：`POST /api/v3/store/catalog_events`（Store API，publishable key，`current_store`）
   - `allow_guest_storefront_access!`（先例：`BackInStockSubscriptionsController`）
   - 自带 `rate_limit by: -> { request.remote_ip }`（见上文硬约束 3）
   - `event_name` **严格白名单**：`impression | click | product_added | product_searched`
   - 单请求 ≤ **100** 条；超限 422
   - `event_id` 幂等：`insert_all ... unique_by: :event_id`（重复不计数）
   - **零 PII**：不收 IP/UA/邮箱/客户 ID；`session_hash` = 服务端 `HMAC-SHA256(visitor_id, store salt)` 截断，**不存原值**
3. **前台**：客户端组件内存聚合 → **每页最多 1 次 flush** → `"use server"` action（`src/lib/data/catalog-events.ts`）→ SDK。失败静默、不重试、不阻断 UI。GA4 链路**完全不动**。
4. **可查询**：只读 scope / 类方法按 `list_id` 聚合曝光/点击/CTR；分母 0 → `nil`。
5. **保留**：保留常量（默认 90 天）+ 幂等清理作业。

## 风险点

| # | 级别 | 风险 | 缓解 | 回滚 |
|---|---|---|---|---|
| R-1 | **中**（初版误判为"高"） | 事件端点桶按 API key 计数、全店共用 ⇒ 上限 300 请求/60s/店；且**无法**被子类跳过 | 重度批量（1 请求/页）+ 单请求 100 条 + 追加 per-IP 限流；天花板已文档化 | 关端点即停（表可 truncate，全旁路） |
| R-2 | 中 | 事件表膨胀 | 保留 90 天 + 清理作业 + 2 条索引 | `DROP TABLE` |
| R-3 | 中 | 隐私 | 零 PII + 服务端 HMAC + 不接收自由 JSON（白名单属性） | 无需回滚（从未存 PII） |
| R-4 | 低 | 双写口径漂移（GA4 vs 自有） | 同点接入 + 词表对齐 + 前端测断言 | 移除回落调用 |

**回滚难度**：低——表为**纯旁路**，无任何业务路径读取；清理作业可停；端点可下线；前台回落可摘除。**零资金副作用**，不写 `funds_*`。

## 决策节点

- 用户已于 2026-09-17 明确回复「实施」⇒ PRD 置 `approved`，进入实施。
- 实施前须**更正 PRD** 中「全仓无限流」的错误结论（见上文「最大的发现」）→ PRD §1 / §4 NFR-002 / §7 R-1。
