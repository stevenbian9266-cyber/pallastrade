# PRD-20260915-checkout-checkout-收尾收敛-b5-legacy-端点治理-usage-metric-收口与零新增调用守护

| 元数据 | 值 |
|---|---|
| 状态 | approved |
| 创建日期 | 2026-09-15 |
| 来源 | 需求：Checkout 收尾收敛 B5 —— legacy 端点治理、usage metric 收口与零新增调用守护 |
| 分类 | checkout（自动判定，见 `harness/policies/prd-categories.json`） |
| 关联 Skill | `pallastrade-api-v3`（主）、`pallastrade-payments`（P0-7 legacy 语义）、`pallastrade-storefront`（消费者守护） |
| 关联 REQ | REQ-20260915-checkout-b5-legacy-governance.md（实施时回填） |
| 关联 PRD | 同系列 B1–B4（节奏表见 `PRD-20260914-checkout-…-b1-…` §1.1；本批 = 节奏表第 B5 行） |
| 需求类型 | 治理 / 观测收敛（**不删除** legacy 端点，见 §1 非目标） |

---

## 1. 背景与目标

### 1.1 背景

方案文档 §45 定义的 P0-7 Legacy Migration Matrix 有 **六类 legacy 嵌套路由**，其应有的形态是三件套：

```text
继续服务 Legacy  +  deprecated  +  usage metric
```

B1–B4 已把 storefront 侧的全部 canonical 消费者接线完成（结账页投影、购物车抵扣、库存错误四态、Express 钱包 canonicalize）。本批（B5）解决**剩下的第三件套缺口**：

| 现状 | 缺口 |
|---|---|
| usage metric：`LegacyFlowObservable`（`cart.legacy_flow.used`）已覆盖 4 个控制器；`carts/payment_sessions_controller` 仍是**自己手写**的 `payment.legacy_flow.used` | 字段契约不统一（缺 `requested_cart_id` / `action` / `deprecated`），无法一条查询统计六行 |
| deprecated：**完全缺失**——路由、OpenAPI 文档、响应头都没有任何机器可读信号 | 集成方无法知道自己正在使用将退役的能力；§45 的 `deprecated` 一栏未落地 |
| 零新增调用：B4 清除了 `carts.paymentSessions`，但没有**机器守护**六行全体 | 下一个人加回 legacy 调用不会被任何检查拦住 |
| 退役阈值：§46 明确「等流量降到退役阈值之后，再独立删除 Legacy consumer」 | 阈值、观测口径、决策流程无文档 → 退役没有可执行的判据 |

### 1.2 目标

1. 六类 legacy 路由具备**机器可读的弃用信号**（响应头 + OpenAPI + 可观测字段），且**不误伤** `cart_` canonical 流量。
2. usage metric **字段契约统一**到一处（`LegacyFlowObservable`），历史 key `payment.legacy_flow.used` 保留（日志管道可能已在消费）。
3. storefront 侧「零 legacy 调用」从人工事实升级为**测试守护**（六行全覆盖，可 CI 执行）。
4. 退役阈值与观测口径**文档化**，让「何时删 legacy」有可执行判据。

### 1.3 成功指标

- 一条日志查询即可输出六类 legacy 路由各自的真实流量（按 `flow_type` + `legacy_identity` 分组）。
- 新增任何 legacy 消费者 → storefront 守护测试 / 后端规格失败。
- `harness generated:check`、`storefront` 三绿（test/check/typecheck）、`p1-order-flow-rspec` 全绿。

### 1.4 非目标（明确不做）

- **不删除**任何 legacy 端点/控制器/路由（§46：流量到退役阈值后独立立项）。
- 不给 legacy 端点增加任何 **`cart_` 之外的新能力**（§45 禁令）。
- 不改 PaymentSession / Transaction 的既有服务语义（本批只动**观测与声明**层）。
- 不改 SDK 方法签名（如加 `@deprecated` JSDoc，属**可选**项在 §3 FR-007 标注，实施前确认）。

---

## 2. 用户故事与场景

| # | 角色 | 场景 | 期望 |
|---|---|---|---|
| U1 | 平台维护者 | 想知道六类 legacy 路由各自还有多少真实流量 | 一条日志查询按 `flow_type` 分组即得（字段齐备、口径一致） |
| U2 | 外部集成方（存量） | 仍在调用 `/carts/:id/payment_sessions` | 响应带 `Deprecation: true` 头 + 文档标注 + 迁移指引（canonical 端点） |
| U3 | 前端开发者 | 想给某页面接一个 legacy 能力 | 守护测试立即失败并指出 canonical 替代（避免回退） |
| U4 | 未来的清理任务 | 决定能否删除 legacy 消费者 | 文档给出阈值判据与观测方法，而不是「凭感觉」 |

**边界/异常场景**

- S1：`cart_` canonical 购物车调用 `/carts/:id/gift_cards`（B2 既有决策）→ **不得**出现 Deprecation 头、**不得**计入 legacy 流量（否则 canonical 流量被误报为待退役流量）。
- S2：legacy Order-表购物车（`or_` 前缀）调用同一路由 → 出现 Deprecation 头 + legacy 计数 + `legacy_identity: 'order_table_cart'`。
- S3：请求带 `X-PallasTrade-Token`/无 token、游客或登录 → 观测字段不因鉴权差异而缺失（`payment_method` 可能为 nil，需 compact）。
- S4：组合支付 legacy 会话 complete（cart 域）→ 观测字段带 `entry_point: 'cart_domain_complete'`，与既有 `OperationalMetrics.legacy('payment_completion')` 不冲突（两者并存）。

---

## 3. 功能需求（FR）

- **FR-001 legacy 身份判定收敛**：`LegacyFlowObservable` 增加 `legacy_identity` 概念（`canonical_cart`(cart_ 前缀) / `order_table_cart`(其余) / `unknown`），六类 legacy 控制器统一使用；`canonical_cart_request?` 判定与既有 `log_legacy_usage_once` 语义保持一致（`cart_` 永不计数）。
- **FR-002 统一 usage metric 契约**：`log_legacy_flow_usage` 统一输出字段集 `{ message, flow_type, entry_point, requested_cart_id, legacy_identity, action, deprecated: true, user_agent }`（nil 一律 compact）；`legacy_flow_log` 支持 `message:` 覆盖（供 payment_sessions 控制器保留历史 key `payment.legacy_flow.used`）。
- **FR-003 payment_sessions 控制器纳入 concern**：`carts/payment_sessions_controller` 移除手写日志方法，改为 `include LegacyFlowObservable` + 显式 `message: 'payment.legacy_flow.used'`（**key 不变**、字段补齐）；`entry_point` 推断逻辑（return_url / stripe_payment_method_id → legacy_one_page / express_checkout）保留。
- **FR-004 机器可读弃用响应头**：在 `log_legacy_usage_once` 的触发点（即 legacy 身份请求）向响应追加三件套（`response.set_header` 幂等）：
  - `Deprecation: true`
  - `Warning: 299 - "This endpoint is legacy-only; migrate to <canonical>"`（canonical 端点由各控制器声明）
  - `Link: </api/v3/store/...canonical...>; rel="successor-version"`
  **`cart_` canonical 请求不带头**（S1）。
- **FR-005 OpenAPI 弃用标注**：`backend/public/api-docs/store.yaml` 六类 legacy 操作（`/carts/{cart_id}/{discount_codes,gift_cards,fulfillments,payments,payment_sessions,store_credits}*`）标注 `deprecated: true` + `description` 增补「Legacy / 兼容：仅 Order-表购物车（`or_`）；canonical 替代 = …；`cart_` 新流程请使用 …」；同步 `platform/docs/api-reference/store.yaml` 副本。paths 属手写区（`api_docs.rake` 只重生成 `components.schemas`）→ 改动不与 `generated:check` 冲突。
- **FR-006 storefront 零新增调用守护（六行全覆盖）**：扩展 `storefront/src/lib/data/__tests__/legacy-payment-sessions-guard.test.ts`：
  1. 源码（注释行豁免）**零** `carts.paymentSessions.` / `carts.payments.` / `carts.complete(` 调用；
  2. `carts.{fulfillments,giftCards,storeCredits,discountCodes}` 只允许出现在**白名单文件**（`lib/data/shopping-cart.ts`、`lib/data/checkout.ts`、`lib/data/express-checkout-flow.ts`、`app/api/checkout/coupon/route.ts`）中，且这些文件必须经由 `requireCartId()`/`getCartOptions()` 解析 `cart_` 身份 → 任何**新增文件**使用 legacy 路由即失败（守护「零新增调用」）。
- **FR-007（可选，实施前确认）SDK 弃用标注**：`platform/packages/sdk/src/store-client.ts` 给 `carts.{payments,paymentSessions,fulfillments,discountCodes,giftCards,storeCredits}` 加 `@deprecated` JSDoc（仅注释，不签名变更），并在 `pallastrade-typescript-sdk` Skill 记录边界。**默认纳入**（成本低、对集成方收益直接）；如用户选择不含，则本 FR 标记「不做」并写入 §10。
- **FR-008 后端规格（回归安全网）**：新增/扩展 request spec：
  - legacy 身份（Order-表购物车 `or_`）打六类路由 → 200/4xx 且：`Deprecation: true` 头存在、`cart.legacy_flow.used` 日志字段齐备（`flow_type` / `legacy_identity=order_table_cart` / `requested_cart_id`）；
  - `cart_` 身份打 `/carts/:id/gift_cards`（既有 canonical 路径）→ **无** Deprecation 头、**无** legacy 日志计数。
- **FR-009 退役阈值与流程文档化**：`ai/skills/pallastrade-api-v3/SKILL.md` 增「Legacy 路由治理与退役」小节：三件套要求、观测查询口径、阈值判据（连续 30 天 legacy 流量为 0 → 可立项删除；删除属独立 PRD）、新增能力禁令；`pallastrade-payments` Skill 同步 P0-7 边界指针。

---

## 4. 非功能需求（NFR）

- **零行为变更**：除新增响应头与日志字段外，六类端点的**状态码/响应体/副作用完全不变**（存量消费者无感）。
- **幂等**：同一请求只写一条 legacy 日志、只设一次头（`@legacy_flow_logged` 守卫沿用）。
- **性能**：仅在 legacy 身份请求上增加一次 header set + 一次 logger.info（无 DB 查询、无额外序列化）。
- **可测性**：观测与头部的判定逻辑收敛在 concern，spec 可只测 concern + 一条端到端路由。
- **可回滚**：改动为纯加法（concern/头/文档/测试）；回滚 = 还原 concern 与文档，无数据迁移。

---

## 5. 验收标准（AC，与测试一一映射）

- **AC-001 ← FR-001**：`LegacyFlowObservable` 的 `legacy_identity` 对 `cart_…` = `canonical_cart`、对 `or_…` = `order_table_cart`（单元级断言）。
- **AC-002 ← FR-002**：legacy 身份请求产生的日志**同时**含 `flow_type` / `entry_point` / `requested_cart_id` / `legacy_identity` / `action` / `deprecated: true`（spec 捕获 `Rails.logger` 断言字段集合）。
- **AC-003 ← FR-002/FR-003**：`carts/payment_sessions` 控制器 legacy 创建的日志 `message` 仍为 `payment.legacy_flow.used`（历史 key 不变），且 `flow_type=legacy_cart_session_create`、`entry_point` 推断（return_url→legacy_one_page / stripe_payment_method_id→express_checkout）保持。
- **AC-004 ← FR-004**：legacy 身份请求响应头含 `Deprecation: true` + `Warning` + `Link`（spec 断言三头）。
- **AC-005 ← FR-004/S1**：`cart_` 身份请求（如 `POST /carts/:id/gift_cards` 成功路径）响应**不含** `Deprecation`；且不产生 legacy 日志。
- **AC-006 ← FR-005**：`store.yaml` 六类 legacy 操作均含 `deprecated: true`；`platform/docs/api-reference/store.yaml` 同步一致（脚本/断言比对）。
- **AC-007 ← FR-006**：storefront 守护测试断言：① 三类调用零出现；② 四个 legacy 路由调用只出现在白名单文件；并包含一个**反向用例**（临时构造的违规字符串会失败——以断言函数本身表达）。
- **AC-008 ← FR-008**：后端 spec 覆盖 legacy 身份（`or_`）打六类路由的观测与头部（至少 2 类端到端 + concern 单元覆盖全量 `flow_type` 取值集合）。
- **AC-009 ← FR-007**：SDK 六个 legacy 方法带 `@deprecated` JSDoc（若纳入）；`pnpm -C platform --filter @pallastrade/sdk build` + storefront typecheck 不回归。
- **AC-010 ← FR-009**：`pallastrade-api-v3` Skill 含「Legacy 路由治理与退役」小节（三件套 + 阈值 + 禁令）；场景库新增 GS-124 且 `harness eval-ai --scenarios` 全绿。

---

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | `payment_sessions` / `legacy` / `carts/` | 仅 `app/javascript/types/serializers/*CustomField.ts` 的 `@deprecated type`（无关） | ✅ 无 legacy 支付调用（零改动） |
| Core | `pallastrade_gems/pallastrade_core/app/` | `Carts::Complete` / `OperationalMetrics` / `OrderCheckout::` | `services/pallastrade/carts/complete.rb`（**canonical** 完成服务，被 webhook/Order 域调用）、`lib/pallastrade/operational_metrics.rb#legacy`、`order_checkout/{select_shipping,refresh,recalculate,view}.rb` | ✅ canonical 服务齐备；本批只加观测，不改服务 |
| API | `pallastrade_gems/pallastrade_api/app/` + `config/routes.rb` | `legacy_flow` / `carts/:id/payment_sessions` | `concerns/.../legacy_flow_observable.rb`（`cart.legacy_flow.used`）、`store/carts/{payment_sessions,payments,fulfillments,discount_codes,gift_cards,store_credits}_controller.rb`、routes L45–59（六类嵌套路由）、`store/orders/{checkout,payment_sessions,transactions}`（canonical） | **否 → 本批实现**（三件套缺 deprecated + 契约不统一） |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | `payment_sessions` / `legacy_flow` | `admin/transactions/show.html.erb`（只读展示 `trace[:payment_sessions]`） | ✅ 零改动 |
| Storefront | `storefront/src/` | `carts.paymentSessions` / `carts.fulfillments` / `carts.giftCards` … | `lib/data/shopping-cart.ts`（`discountCodes`/`giftCards`/`storeCredits`，`cart_` 身份）、`lib/data/checkout.ts#selectDeliveryRate`（`carts.fulfillments.update`）、`lib/data/express-checkout-flow.ts`（钱包费率）、`app/api/checkout/coupon/route.ts`（BFF 折扣/礼卡） | ✅ **零 legacy 调用**（B4 已清 paymentSessions；`cart_` 路径属 canonical 决策）→ 本批补守护 |
| Platform | `platform/packages/` | `paymentSessions` / `fulfillments` | `sdk/src/store-client.ts`（`carts.*` legacy 方法与 `orders.paymentSessions` canonical 并存） | ⚠️ 需加 `@deprecated` 标注（FR-007） |

**结论**：本批为 **后端观测/声明层治理 + 前端守护 + 文档**，不新增端点、不改路由、不改服务语义；`/carts/:id/payment_sessions` 的 storefront 消费者已在 B4 清零，本批把它变成**机器守护**并补齐 §45 三件套中缺失的 `deprecated`。防重复判定：无既有 PRD 覆盖「legacy 三件套治理」；B1–B4 分别覆盖投影/抵扣/库存/钱包，均未触及观测与弃用信号。

---

## 7. 技术影响

- **backend（gem）**：`pallastrade_api/app/controllers/concerns/pallastrade/api/v3/legacy_flow_observable.rb`（`legacy_identity` + 统一字段 + 头部注入 + message 覆盖）、`store/carts/payment_sessions_controller.rb`（纳入 concern、保留历史 key）、`store/carts/{payments,fulfillments,discount_codes,gift_cards,store_credits}_controller.rb`（声明 canonical 替代端点用于 `Link` 头）。
- **backend（spec）**：新增 `spec/requests/api/v3/store/legacy_flow_governance_spec.rb`（或扩展既有 `cart_payment_sessions_controller_spec.rb` + `carts/gift_cards_spec.rb`）→ FR-008。
- **api-docs**：`backend/public/api-docs/store.yaml`（paths 手写区加 `deprecated: true` + 描述）、`platform/docs/api-reference/store.yaml` 副本同步。
- **platform**：`packages/sdk/src/store-client.ts` JSDoc（可选 FR-007）。
- **storefront**：守护测试扩展（无运行时代码改动）。
- **不涉及**：DB 迁移、状态机、支付服务、admin UI、`.env`。

---

## 8. 测试计划

- **新增（后端）**：`backend/spec/requests/api/v3/store/legacy_flow_governance_spec.rb` → AC-001/002/004/005/008（legacy vs canonical 身份 × 头部与日志）
- **扩展（后端）**：`backend/spec/requests/api/v3/store/cart_payment_sessions_controller_spec.rb` → AC-003（历史 key 与 entry_point 推断不变）
- **扩展（storefront）**：`storefront/src/lib/data/__tests__/legacy-payment-sessions-guard.test.ts` → AC-007（六行全覆盖 + 白名单）
- **新增（契约）**：`scripts/ci/` 或 spec 级断言 `store.yaml` 与 `platform/docs/api-reference/store.yaml` 的弃用标注一致 → AC-006
- **回归**：`npx harness generated:check`、`pnpm -C storefront test|check|typecheck`、`npx harness verify p1-order-flow-rspec --task <id>`（如新 spec 需注册 verifier，则加进 `p1-order-flow-rspec` 命令或新建 `legacy-governance-rspec`）
- **AC ↔ 测试映射**：测试文件内同行写 `# PRD-<本PRD-ID> AC-xxx` 供 `prd verify` 校验

---

## 9. 文档同步清单（知识同步门）

- [x] Skill：`pallastrade-api-v3`（新增「Legacy route deprecation & retirement」小节 + 更新六行条目 + changelog）
- [x] Skill：`pallastrade-payments`（P0-7 边界指针：弃用头 + 统一字段 + 退役阈值，服务语义零变更）
- [x] Skill：`pallastrade-storefront`（零 legacy 调用守护扩到六行 + 白名单）
- [x] Skill：`pallastrade-typescript-sdk`（cart 域方法 `@deprecated` 口径与迁移目标）
- [x] 场景库：`harness/scenarios/scenarios.json` 新增 **GS-124**，`harness eval-ai --scenarios` → **125/125 valid**
- [x] API 文档：`backend/public/api-docs/store.yaml`（deprecated + `x-cart-domain-legacy` + `x-canonical-successor`）→ `scripts/ci/contracts.sh` 同步 `platform/docs/api-reference/store.yaml`
- [x] `platform/packages/README.md`（SDK 弃用方法与迁移目标）
- [ ] 本 PRD 状态（done）+ `docs/prd/README.md` 索引（`prd-status-sync --fix/--check`）
- [x] 已评估项：`AGENTS.md` / `copilot-instructions.md`（无机制变更）、`pallastrade-data-model`（无 DB 变更）、`pallastrade-admin`（零改动）

---

## 9.1 用户决策（2026-09-15，gate 前确认）

| 决策点 | 选择 |
|---|---|
| 是否实施 | ✅ 确认实施（FR-001..009 全量） |
| 弃用信号形式 | ✅ 响应头 + OpenAPI + SDK JSDoc（三件套） |
| 退役阀值 | ✅ 连续 30 天 `legacy_identity = order_table_cart` 计数为 0 → 可独立立项删除 |
| 端点删除 | ✅ 本批**不删**（§46），仅治理与观测 |

## 9.2 实施约定（对 FR-005 的精确化）

六行路由中 **`discount_codes` / `gift_cards` / `fulfillments` / `store_credits` 是双用途**的：`cart_` canonical 购物车（B2 决策）与 Order-表旧购物车共用同一路由形状。因此：

- `deprecated: true` **只打在无 canonical 角色的四个操作**上：`carts/{cart_id}/payments`、`carts/{cart_id}/payment_sessions`、`.../{id}`、`.../{id}/complete`；
- 全部 legacy 操作都打 `x-cart-domain-legacy: true` + `x-canonical-successor: <路径>`（机器可读、与响应头 `Link` 一致）；
- `cart_` canonical 流量既不收弃用头、也不计 legacy 度量（AC-005）——否则会把新流程误报为待退役流量。

## 9.3 sync-check 逐项结论（2026-09-15）

| 触发组 | 需评估资产 | 结论 |
|---|---|---|
| API 端点变更 | `backend/public/api-docs/{store,admin}.yaml` | ✅ `store.yaml` 已加 `deprecated` / `x-cart-domain-legacy` / `x-canonical-successor`，`contracts.sh` 同步 platform 副本；`admin.yaml` 无变更 → 无需更新 |
| API 端点变更 | `pallastrade-api-v3` Skill | ✅ 新增「Legacy route deprecation & retirement」小节 + 更新六行条目 + changelog |
| API 端点变更 | SDK 类型（`generated:check`） | ✅ 无契约/类型变更（未改 `permitted_params`、序列化器、路由）；`generated:check` 无漂移 |
| API 端点变更 | 场景库 | ✅ GS-124（`eval-ai --scenarios` 125/125） |
| UI 组件 / 页面 | `pallastrade-storefront` Skill / 组件测试 / 场景库 | ✅ 守护测试扩到六行（`legacy-payment-sessions-guard.test.ts`）；Skill B4 小节补「零 legacy 调用（B5 扩展）」；GS-124 覆盖 |
| 包 / SDK 能力 | `pallastrade-typescript-sdk` Skill / `platform/packages/README.md` / 根 README | ✅ 两者均已更新；根 README 无 SDK 方法级清单 → 无需更新 |
| Skill / PRD 机制 | `pallastrade-prd` Skill / `AGENTS.md` / `copilot-instructions.md` | ✅ 已评估，无需更新（流程与强制命令未变）；`scenarios.json` 已更新（GS-124） |

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-15 | 0.1 | 初稿：B5 范围（legacy 三件套补齐）+ FR-001..009 / AC-001..010 / 6 层搜索 / 测试与同步计划；`prd new` 分类命中 checkout | AI |
| 2026-09-15 | 0.2 | 用户决策（§9.1：全量实施 / 三件套 / 30 天阀值 / 不删端点）；实施期细化（§9.2：`deprecated: true` 仅四个无 canonical 角色的操作，双用途路由用 `x-cart-domain-legacy` + `x-canonical-successor`）；补充：`carts/payment_sessions` 纳入 concern 后 `cart_` 身份不再计 legacy 度量（原本无条件计）——属预期口径修正，写入 AC-003/AC-005 | AI |
