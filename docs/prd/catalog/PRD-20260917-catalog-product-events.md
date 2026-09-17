# PRD-20260917-catalog-product-events

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-17 |
| 来源 | 一句话需求「A3 Step 1 事件回流」（继续 `豆包梳理业务需求/商品升级方案.md` §14 / §16） |
| 分类 | catalog |
| 关联 Skill | pallastrade-api-v3、pallastrade-storefront、pallastrade-security、pallastrade-data-model、pallastrade-testing |
| 关联 REQ | REQ-20260917-catalog-product-events.md |
| 关联 PRD | N/A（全新需求；与 C1 规则推荐互补：C1 产出推荐位，本 PRD 产出该位的效果数据） |
| 需求类型 | 新功能 |

## 1. 背景与目标

- **一句话需求原文**：「实施 A3 Step 1 事件回流」
- **方案依据**：
  - §14 行 388：「只有形成真实曝光 / 点击 / 加购 / 购买数据以后，才值得进入推荐算法阶段」
  - §16 上线指标：`PDP | Related Product CTR` —— 该指标需要 **分母=推荐位曝光**、**分子=推荐位点击**，两者目前**都不存在**。
- **现状**（详见 §6 跨层搜索）：
  1. 前台**已有** GA4 埋点 helper 与调用点（`storefront/src/lib/analytics/gtm.ts` + PDP / `ListingAnalytics` / `ProductCard` / `SearchBar`），但**只推给 GTM dataLayer**：数据落在第三方，后台查不到、无历史、无法与自有商品关联。
  2. 后台**已有**事件框架 `PallasTrade::Analytics`（词表已含 `product_viewed` / `product_list_viewed` / `product_added` / `product_searched`）＋**空** handler 扩展点（`analytics_event_handlers = []`），但它是**外发**通道，**不落库**。
  3. 后台唯一的「事件落地」是 `PallasTrade::EventLogSubscriber`，**只写 Rails logger**，无可查询表。
  4. **限流已存在，但形状很关键**（v0.2 更正）：Rails 8.1 内置 `rate_limit` 在 `PallasTrade::Api::V3::BaseController` **全局声明**（`to: rate_limit_per_key` = **300/60s**，`by:` = **API key**，`scope` 默认 = `controller_path`）。
     ⇒ 事件端点会有**自己的桶**（**不挤占**商品 / 购物车 / 结账配额），但 storefront 全店**共用一个 publishable key** ⇒ 端点上限 = **300 请求 / 60s / 整店**。
     ⇒ 该回调是**匿名 lambda**（`before_action -> { rate_limiting(...) }`），子类 `skip_before_action` **无效**，**无法**在端点内绕过。
- **目标**：把商品域的**曝光 / 点击 / 加购 / 搜索**事件落到**自有库**，使 `Related Product CTR` 可从自有数据计算，并为后续推荐算法积累训练数据。
- **非目标（明确不做）**：
  - **不做推荐算法**（方案 §14 行 370：「第一版不建议做推荐算法」）；
  - 不做用户画像 / 个体行为追踪（见 FR-008 零 PII）；
  - 不改变任何业务判定（见 NFR-003）；
  - 不做后台消费页面（见 FR-016）。
- **成功指标**：
  1. 给定时间窗与店铺，SQL 可直接算出每个推荐位（`list_id`）的 **曝光数 / 点击数 / CTR**；
  2. 事件表**不参与**任何业务读写路径——可随时 truncate 而订单 / 库存 / 价格完全不受影响；
  3. 单请求（≤20 条）p95 < 50ms；前台埋点失败**不影响**用户任何操作。

## 2. 用户故事 / 场景

- 作为**运营**，我想知道 PDP 上「相关商品」位的曝光与点击比，以便决定是否把它上移。
- 作为**店主**，我想让这些数据留在自己的数据库里（第三方分析平台随时可能改变条款 / 收费 / 停服）。
- 作为**未来的推荐算法**，我需要真实行为数据，而不是靠人工规则猜。

场景：

- **正常流**：用户进 PDP → 相关商品位渲染 → 上报 N 条 `impression`（含 `list_id` / `position` / `product_id`）→ 用户点第 2 个 → 上报 1 条 `click` → CTR = 1/N。
- **边界（重复曝光）**：同一商品在同一位被重复出现 → 按 `event_id` 幂等，重复上报只留一条；**不跨请求去重**（滚动回看算两次曝光，与 GA4 口径一致）。
- **边界（批量）**：一页 N 条曝光 → 单请求批量上报（上限 20 条）。
- **异常（端点故障）**：5xx / 超时 → 前台**静默丢弃**，绝不重试、绝不阻断导航。
- **异常（匿名访客）**：未登录仍可上报，使用匿名 `session_hash`，无需身份。
- **异常（跨店）**：上报必须落在 `current_store`，不得写错店。

## 3. 功能需求（FR）

### F1 事件表（自有库）

- **FR-001**：新增表 `pallastrade_catalog_events`（模型在 core gem，**迁移文件落在 `backend/db/migrate/`**），字段：
  `store_id`、`event_id`（客户端 UUID）、`event_name`、`product_id`、`variant_id`（可空）、`list_id`（可空）、`list_name`（可空）、`position`（可空）、`session_hash`、`occurred_at`、`metadata`（可空）、`created_at`。
- **FR-002 幂等**：`event_id` 建唯一索引；重复上报走 `INSERT ... ON CONFLICT DO NOTHING`，**不产生重复计数**（重试 / 双发安全）。
- **FR-003 追加写**：表**只允许 INSERT**，不提供 update / delete 业务路径（清理作业除外）。
- **FR-004 保留有界**：保留策略为集中常量（默认 90 天）+ 清理作业；行数有界；清理作业幂等、可重复运行。

### F2 采集端点

- **FR-005**：新增 `POST /api/v3/store/catalog_events`（Store API，publishable key 鉴权，`current_store` 作用域）。
- **FR-006 严格白名单**：`event_name` 只接受 `impression | click | product_added | product_searched`（与方案既有词表对齐）；未知名称 → 422，**不写库**。
- **FR-007 批量与上限**：请求体 `{ events: [...] }`，**单请求 ≤ 100 条**（上限须显著大于「单次页面浏览产生的事件数」，以减少 flush 次数、适配 per-key 限流天花板）；超限 422 且**整批不落库**；白名单之外的属性一律丢弃（**不透传任意 JSON**）。
- **FR-008 零 PII**：**不接收** IP / User-Agent / 邮箱 / 客户 ID；`visitor_id` 在请求中出现但**绝不落库**（仅用于服务端派生摘要）——`session_hash` = `HMAC-SHA256(visitor_id, "catalog_events:<store_id>:<secret_key_base>")` 截断为 32 位十六进制，不可逆且**跨店不可关联**；白名单之外的属性（含自由 `metadata`）一律丢弃。
- **FR-009 跨店隔离**：所有写入强制 `current_store`；请求体中的 `store_id`（若出现）忽略。
- **FR-010 端点不得成为放大器**：单请求最大工作量为固定常数（≤100 行 INSERT + 1 次 HMAC），无 N+1、**无外部调用**（不发 GA4、不发 webhook、不入队）。
- **FR-017 追加 per-IP 限流**：端点内**再声明**一条 `rate_limit by: -> { request.remote_ip }`（默认 60/60s），使**单个滥用者**无法独占整店预算；两条限流同时生效（取更严者）。
- **FR-018 重度批量（前台）**：客户端内存聚合，**每次页面浏览最多 flush 1 次**（`visibilitychange` / `pagehide` + `keepalive`），使请求数上限 = 页面浏览数，而非事件数。

### F3 前台回落

- **FR-011**：新增 `storefront/src/lib/analytics/catalog-events.ts`，与既有 `gtm.ts` **并行**调用（GA4 链路保持不变），经 SDK 走 Store API（遵守 AP-002，**禁止裸 fetch**）。
- **FR-012 静默失败**：上报为 fire-and-forget，失败**不重试、不抛错、不阻断 UI**；使用 `keepalive` 以便导航卸载时仍能发出。
- **FR-013 覆盖调用点**：在既有 GA4 调用点（PDP / `ListingAnalytics` / `ProductCard` / `SearchBar`）**同名点位**接入，保证两套数据口径可比。

### F4 可查询

- **FR-014**：提供只读查询口径（scope / 类方法）：按 `list_id` 聚合曝光 / 点击 / CTR；按 `product_id` 聚合加购 / 曝光。
- **FR-015**：CTR 分母为 0 时返回 `nil`，**不返回 0、不返回 1**（沿用 catalog health「不编造比率」铁律）。
- **FR-016**：本 PRD **不做**后台消费页面（避免「采了没人看」与「看了没数」同时发生）；若确认需要，另开 PRD。

## 4. 非功能需求（NFR）

- **NFR-001 性能**：批量 ≤20 条单请求 p95 < 50ms；查询走 `(store_id, occurred_at)` 与 `(store_id, list_id)` 索引；查询数不随事件行数增长（聚合下推 SQL）。
- **NFR-002 安全（v0.2 已按真实限流形状重写）**：
  - **限流已存在且会自动覆盖本端点**：`V3::BaseController` 的全局 `rate_limit`（300/60s，按 API key）对**所有** v3 端点生效，新端点**天然受保护**，无需自建 Rack::Attack；
  - **但 quota 形状是硬约束**：桶按 **API key** 计数，全店共用一个 publishable key ⇒ 端点上限 **300 请求/60s/整店**，且**无法**被子类跳过（匿名 lambda 回调）。
  - **应对**：重度批量（FR-018，1 请求/页）+ 单请求 100 条（FR-007）+ 追加 per-IP 限流（FR-017）+ 常数代价（FR-010）。
  - 零 PII（FR-008）、跨店隔离（FR-009）、不接收任意 JSON（FR-007）。
  - **遗留风险（不在本 PRD 范围）**：业务量增长到「页面浏览 > 300/60s」时，需要更高配额 ⇒ 只能下调**全局** `rate_limit_per_key`（影响全 API）或改造端点脱离 `V3::BaseController`。届时另开 PRD。
- **NFR-003 只读语义**：事件表是**旁路**，任何业务路径（库存 / 价格 / 订单 / 结账）**不得读取**它做判定。
- **NFR-004 兼容**：GA4 / GTM 链路完全不变（前台新增并列上报，不改 `gtm.ts` 既有行为）。
- **NFR-005 可维护**：事件词表集中一处常量；端点与表同源于 core gem；若改 gem 既有文件，加 `# PALLAS-CUSTOM:` 标注。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001 ← FR-001/002**：同 `event_id` 重复上报两次 → 表内**只有 1 行**，计数为 1。
- **AC-002 ← FR-006**：未知 `event_name` → 422 且表内 0 行。
- **AC-003 ← FR-007**：101 条批量 → 422 且表内 0 行；100 条 → 200 且 100 行；白名单外属性不落库。
- **AC-011 ← FR-017**：同一 IP 超过 per-IP 配额 → 429（带 `Retry-After`），且**不落库**；不同 IP 互不影响。
- **AC-012 ← FR-018**：同一次页面浏览产生 N 条事件 → 只发起 **1** 次上报请求（前端单测断言 flush 次数）。
- **AC-004 ← FR-008**：库内任意列**不含** IP / UA / 邮箱 / 客户 ID；`session_hash` 对同一 `visitor_id` 稳定、对不同 `visitor_id` 不同、且 ≠ 原值。
- **AC-005 ← FR-009**：用 A 店 publishable key 上报 → 全部行 `store_id == A`；B 店查不到。
- **AC-006 ← FR-004**：清理作业删除早于保留期的行、保留期内不动；重复运行结果一致。
- **AC-007 ← FR-012**：上报失败（端点 500）时前台**不抛错、不重试**，页面交互不受影响（前端单测断言）。
- **AC-008 ← FR-014/015**：给定构造数据，`list_id` 聚合的曝光 / 点击与手工计数一致；分母 0 → CTR 为 `nil`。
- **AC-009 ← NFR-003**：删除全部事件行后，商品 / 购物车 / 订单相关既有 spec 全绿（证明旁路）。
- **AC-010 ← FR-011/013**：既有 GA4 调用点行为不变（`gtm.ts` 相关测试不回归），且新增了同名点的回落调用。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | analytics / tracking / event_log / telemetry | 无 | ❌ ABSENT |
| Core | `pallastrade_gems/pallastrade_core/app/` | event / analytics / tracking | `base_analytics_event_handler.rb`（**外发**框架基类）、`lib/pallastrade/analytics.rb`、`lib/pallastrade/core.rb`（AnalyticsConfig）、`app/subscribers/pallastrade/event_log_subscriber.rb`（**仅 logger**） | ⚠️ 部分：有框架与词表，**无落库** |
| API | `pallastrade_gems/pallastrade_api/app/` | events / catalog_events | 无（无任何事件端点） | ❌ 需新建 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | analytics / events 页面 | 无 | ❌ 需新建（本 PRD 不做） |
| Storefront | `storefront/src/` | trackSelectItem / trackViewItemList / analytics | `lib/analytics/gtm.ts`（GA4 helper 全集）、`products/[slug]/ProductDetails.tsx`、`components/products/ListingAnalytics.tsx`、`components/products/ProductCard.tsx`、`components/search/SearchBar.tsx` | ⚠️ 埋点**已有**，但**只进 GTM**，无回落 |
| Platform | `platform/packages/` | events / analytics | 无 | ❌ 需新建 SDK 方法 |

**另查明**：

- **限流（v0.2 更正）**：全仓**无限流**的初版结论**错误**——只检索了 `Rack::Attack|rack_attack|throttle`。真实情况：Rails 8.1 内置 `rate_limit`，在 `V3::BaseController:35` 全局声明；实现文件 `actionpack-8.1.3.1/lib/action_controller/metal/rate_limiting.rb`；公开 POST 写端点先例 `store/back_in_stock_subscriptions_controller.rb`（`allow_guest_storefront_access!` + 自带 `rate_limit`）。
- **商品页形态**：PDP 为静态页，Rails 看不到页面浏览 ⇒ **客户端是唯一入口**。
- **无既有事件表**：`backend/db/schema.rb` 无 `pallastrade_event*` 表。

**结论**：能力分布 = 前台埋点 ✅ / 后台框架与词表 ✅ / 落库 ❌ / 端点 ❌ / 限流 ❌。
**防重复判定**：不新建前台埋点（复用既有调用点），不新建后台外发框架（复用 `Analytics`），**只补「表 + 端点 + 回落后半段」**。

## 7. 技术影响

- **数据库**：`backend/db/migrate/2026xxxxxx_add_pallastrade_catalog_events.rb`（**必须落在 host app** —— gem `db/migrate` 已停更，见 B1 教训）
- **Core**：`app/models/pallastrade/catalog_event.rb`、`app/services/pallastrade/catalog_events/record.rb`、保留策略常量 + 清理作业
- **API**：`app/controllers/pallastrade/api/v3/catalog_events_controller.rb` + routes + 参数白名单
- **Storefront**：`lib/analytics/catalog-events.ts` + 4 个既有调用点接入
- **SDK**：`platform/packages/sdk` 新增方法 + 契约再生成
- **影响面**：`harness affected --base origin/dev`

**风险**：

| # | 级别 | 风险 | 缓解 |
|---|---|---|---|
| R-1 | **中**（v0.2 由「高」下调） | 端点桶按 API key 计数、全店共用 ⇒ 上限 300 请求/60s/店；且**无法**被子类跳过 | 重度批量（1 请求/页）+ 100 条/请求 + 追加 per-IP 限流 + 常数代价；天花板已显式文档化 |
| R-2 | 中 | 事件表膨胀 | 保留 90 天 + 清理作业 + 两条索引 |
| R-3 | 中 | 隐私 | 零 PII + 服务端 HMAC + 不接收自由 JSON |
| R-4 | 低 | 双写口径漂移（GA4 vs 自有） | 同点接入 + 词表对齐 + AC-010 |

## 8. 测试计划

- **新增**：
  - `backend/spec/models/pallastrade/catalog_event_spec.rb`（唯一索引 / 幂等 / 聚合口径 / CTR `nil`）
  - `backend/spec/requests/pallastrade/api/v3/catalog_events_spec.rb`（AC-001…AC-005）
  - `backend/spec/services/pallastrade/catalog_events/prune_spec.rb`（AC-006）
  - `storefront/src/lib/analytics/__tests__/catalog-events.test.ts`（AC-007）
- **更新**：`storefront/src/lib/analytics/__tests__/gtm.test.ts`（AC-010 不回归）
- **AC 映射**：AC-001…005 → 请求 spec；AC-006 → prune spec；AC-007 → 前端单测；AC-008 → model spec + 请求 spec 端到端；AC-009 → 既有全量回归；AC-010 → 前端单测。
- **证据**：新增 `harness verify` verifier + `harness generated:check` + `harness check --profile quick`。

## 9. 文档同步清单（知识同步门）

- [x] API 文档：`backend/public/api-docs/store.yaml` + `platform/docs/api-reference/store.yaml`（新端点 + 新 schema，**paths 手写**，无 Typelizer 序列化器）
- [x] Skill：`pallastrade-api-v3`（新端点 + 限流实现真相）、`pallastrade-storefront`（§Catalog events 批量契约）、`pallastrade-data-model`（新表）
- [x] `AGENTS.md` §6（新增 `catalog-events-rspec` verifier 行）
- [x] 场景库 `harness/scenarios/scenarios.json`（**GS-175** —— 原拟 GS-174，但并行会话已占用该编号，故顺延）
- [x] `harness.config.mjs`（`catalog-events-rspec`）
- [x] `platform/packages/README.md`（SDK 新方法 + 配额形状警告）
- [x] 本 PRD 状态更新 + `docs/prd/README.md` 索引

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-17 | 0.1 | 初稿：recon 结论 + 设计 + 限流前置风险 R-1 | AI |
| 2026-09-17 | 0.2 | **更正限流事实**（初版「全仓无限流」错误）：限流存在且自动覆盖本端点；quota 按 API key、全店共用、子类不可跳过 ⇒ 改为重度批量设计（FR-017/018、上限 20→100、R-1 高→中）。用户已确认实施。 | AI |
| 2026-09-17 | 1.0 | 实施完成：表 + 端点 + 服务 + 保留作业 + 前台回落 + SDK；43 个后端 spec 全绿、storefront 484 测试无回归、`next build` 通过；运行时实证幂等/零 PII/CTR/限流头（`x-ratelimit-limit: 300`）。FR-008 措辞修正为「`visitor_id` 接收但不落库」。 | AI |
