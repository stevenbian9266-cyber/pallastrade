# REQ-20260915-checkout-b5-legacy-governance — Checkout 收尾收敛 B5（legacy 端点治理 / usage metric 收口 / 零新增调用守护）

> 关联 PRD：`docs/prd/checkout/PRD-20260915-checkout-checkout-收尾收敛-b5-legacy-端点治理-usage-metric-收口与零新增调用守护.md`
> Harness 任务：`TASK-20260915015752-be86cf31` ｜ Gate：`GATE-2026-09-15T01-58-03`

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | `payment_sessions` / `legacy` / `carts/` | 仅 `app/javascript/types/serializers/*CustomField.ts` 的 `@deprecated type` 注释 | ✅ 无关；零改动 |
| App — views/decorators | `backend/app/` | `payment_session` / `legacy_flow` | 无 | ✅ 零改动 |
| Core Gem — models | `backend/pallastrade_gems/pallastrade_core/app/models/` | `payment_session` / `legacy_payment_session` | `payment.rb#legacy_payment_session`（读模型关联，非端点）、`commerce_transaction.rb`、`order.rb` | ✅ 与本批（端点治理）解耦 |
| Core Gem — services | `backend/pallastrade_gems/pallastrade_core/app/services/` | `Carts::Complete` / `OperationalMetrics` / `OrderCheckout::` | `carts/complete.rb`（**canonical** 完成服务）、`carts/{apply_gift_card,apply_store_credit,submit}.rb`、`order_checkout/{select_shipping,refresh,recalculate,view}.rb`、`lib/pallastrade/operational_metrics.rb#legacy` | ✅ canonical 能力齐备；本批只补观测与声明 |
| API Gem — controllers | `backend/pallastrade_gems/pallastrade_api/app/controllers/` | `legacy_flow` / `carts/*` | `concerns/.../legacy_flow_observable.rb`、`store/carts/{payment_sessions,payments,fulfillments,discount_codes,gift_cards,store_credits}_controller.rb`、routes L45–59 | **否 → 本批实现**（缺 `deprecated` 三件套 + 字段契约不统一） |
| Admin Gem — controllers | `backend/pallastrade_gems/pallastrade_admin/app/controllers/` | `payment_sessions` / `legacy` | `admin/payments_controller.rb`（`OperationalMetrics.legacy('admin_payment_complete')`，管理员动作，非 legacy 路由） | ✅ 零改动 |
| Admin Gem — views | `backend/pallastrade_gems/pallastrade_admin/app/views/` | `payment_sessions` | `admin/transactions/show.html.erb`（只读 trace 计数） | ✅ 零改动 |
| Storefront | `storefront/src/` | `carts.paymentSessions` / `carts.fulfillments` / `carts.giftCards` | `lib/data/shopping-cart.ts`（三抵扣，`cart_`）、`lib/data/checkout.ts#selectDeliveryRate`、`lib/data/express-checkout-flow.ts`、`app/api/checkout/coupon/route.ts`；`lib/data/__tests__/legacy-payment-sessions-guard.test.ts`（B4 守护） | ✅ 零 legacy 调用 → 本批把守护扩到**六行** |
| Platform | `platform/packages/` | `paymentSessions` / `fulfillments` / `payments:` | `sdk/src/store-client.ts`（`carts.*` 与 `orders.paymentSessions` 并存） | ⚠️ 需加 `@deprecated` JSDoc（FR-007） |

### 搜索结论

- **能力层（后端）**：canonical 链（`orders.transactions` / `orders.payment_sessions` / `OrderCheckout::SelectShipping` / `Carts::{ApplyGiftCard,ApplyStoreCredit}` / `Carts::Submit`）**已齐备**；legacy 六类路由保留服务存量（§45 允许）。
- **缺口集中在观测与声明层**：`LegacyFlowObservable` 缺 `legacy_identity`/`action`/`deprecated` 字段且未覆盖 `carts/payment_sessions`（后者手写 `payment.legacy_flow.used`）；**没有任何机器可读的弃用信号**（响应头 / OpenAPI / JSDoc）；storefront 守护只覆盖 paymentSessions 一行。
- **零行新代码不可能**：本批新增 1 个后端 spec + concern 扩展 + 文档标注 + 守护测试扩展（消费者侧零运行时代码改动）。

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树优先级：Settings → Configuration → Events → Dependencies → Admin/Ransack → Generators → **Decorators** → Extensions；「Decorators 保留给结构性变更」。本批改动目标是**框架自有 gem 源码**（`pallastrade_api` 属本仓库产品化 gem，AGENTS §1 明确「Modify gem files directly；升级即 merge」）→ 属最低风险的直接修改，无需 decorator/Host App 覆盖 |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已评估（不涉及） | 本批零 admin 改动（仅 `transactions/show` 只读展示已存在字段）；无需面包屑/导航三要素检查 |
| `ai/skills/pallastrade-catalog/SKILL.md` | ✅ 已评估（不涉及） | 无商品/目录模型或端点改动 |

**按需 Skill：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-api-v3` | ✅ 主 | ✅ 已读 | 「Legacy order-domain cart endpoints carry the same usage metric so remaining legacy traffic is measurable before migrating (research §9.3 P2, P0-7): `carts/payments`, `carts/fulfillments`, `carts/gift_cards`, `carts/store_credits` and `carts/discount_codes` all log `cart.legacy_flow.used` (one `flow_type` per endpoint) on non-`cart_` ids only; `carts/payment_sessions` **keeps its historical `payment.legacy_flow.used` key**. Counting that message is how we decide whether a legacy endpoint ever gets a canonical implementation.」→ 本批把该口径**代码化 + 文档化**（弃用头 + 字段齐备 + 退役阈值） |
| `pallastrade-payments` | ✅ | ✅ 已读 | 「Legacy=Compatibility Only(payment.legacy_flow.used)」（P0 2026-09-03 条目）；组合/成员完成分流器 `CombinationMemberComplete` 已在 standard/legacy 之间分流 → 本批**不改服务语义**，只加观测 |
| `pallastrade-storefront` | ✅ | ✅ 已读 | B4 小节固定了钱包 canonical 五步与「禁止 `carts.paymentSessions.*`」；本批把该禁令扩展到六行并在测试中机器化 |
| `pallastrade-testing` | ✅ | ✅ 已读 | Scaffolding 新 API 资源生成 `spec/controllers/pallastrade/api/v3/{store,admin}/` + factory；本批为 request spec（`spec/requests/api/v3/store/`），沿用既有 `cart_payment_sessions_controller_spec.rb` 的 `legacy_cart_order` 夹具范式 |
| `pallastrade-decorators` | ⬜ 不涉及 | — | 不改动现有类结构（仅扩展 concern 与新 spec） |
| `pallastrade-dependencies` | ⬜ 不涉及 | — | 不替换服务实现 |
| `pallastrade-events-webhooks` | ⬜ 不涉及 | — | 无事件/订阅者改动 |
| `pallastrade-i18n` | ⬜ 不涉及 | — | 无用户可见文案 |

---

## 需求标题

补齐 P0-7 六类 legacy 路由的第三件套：**deprecated 信号 + 统一 usage metric 契约 + 零新增调用守护 + 退役阈值文档**（不删除端点）。

## 任务类型

功能优化（治理 / 可观测性收敛）——**纯加法**：新增响应头、日志字段、OpenAPI 标注、测试与文档；不改路由、不改响应体、不改服务语义。

## 需求描述

B1–B4 已经把收银前端的全部 canonical 消费者接线完成。按方案 §45/§46，legacy 路由应长期保持「**继续服务 + deprecated + usage metric**」三件套，等流量降到退役阈值后再**独立立项**删除。目前：

1. **deprecated 缺失**——路由、OpenAPI、响应头都没有信号，集成方不知道自己用的是待退役能力；
2. **metric 不统一**——`payment_sessions` 控制器是手写日志（缺 `requested_cart_id`/`action`/身份字段），其余五个走 concern，无法一条查询统计六行；
3. **零新增调用无守护**——B4 只是人工清零，没有测试拦住回归；
4. **退役阈值无判据**——「什么时候能删」没有可执行标准。

本批把这四件事补上，**并明确不删除任何 legacy 端点**。

## 影响范围（harness affected 输出）

```json
{
  "filesChanged": 84,
  "affectedComponents": ["ai", "backend", "harness", "platform", "storefront"],
  "errors": [],
  "estimatedTests": 252
}
```

（含 B1–B4 已提交内容；本批预计再改动 backend concern/控制器/spec + store.yaml 双份 + sdk JSDoc + storefront 守护测试 + Skill/场景库/PRD。）

## 技术方案（初步）

1. **观测统一**：扩展 `PallasTrade::Api::V3::LegacyFlowObservable`——新增 `legacy_identity`（`canonical_cart` / `order_table_cart` / `unknown`）、`action`、`deprecated: true` 字段；`log_legacy_flow_usage(message:)` 支持 key 覆盖。`carts/payment_sessions_controller` 删除手写方法、改用 concern 且 **key 保持 `payment.legacy_flow.used`**（日志管道兼容）。
2. **弃用信号**：在 legacy 身份判定命中的同一处注入 `Deprecation: true` / `Warning: 299 …` / `Link: <canonical>; rel="successor-version"`（`cart_` 请求不注入）；各控制器声明 `legacy_canonical_successor`（如 payments → `/orders/:id/payment_sessions`）。
3. **文档标注**：`store.yaml` paths 手写区为六类 legacy 操作加 `deprecated: true` + 迁移说明；同步 `platform/docs/api-reference/store.yaml`。`api_docs.rake` 只重生成 `components.schemas`，不冲突 `generated:check`。
4. **守护**：storefront `legacy-payment-sessions-guard.test.ts` 扩为六行矩阵（三类零出现 + 四个白名单文件 + 反向断言）。
5. **后端规格**：新增 `spec/requests/api/v3/store/legacy_flow_governance_spec.rb`（legacy vs `cart_` 身份 × 头 + 日志），并把文件加进注册 verifier `p1-order-flow-rspec`（或新建专用 verifier）。
6. **退役阈值文档**：`pallastrade-api-v3` Skill 增小节（阈值判据：连续 30 天 flow 计数为 0 → 独立立项删除；三件套要求；新增能力禁令）。

## 风险点

| 风险 | 等级 | 缓解 |
|---|---|---|
| 弃用头误伤 `cart_` canonical 流量（前端/BFF 依赖 `/carts/:id/gift_cards` 等） | **中** | 只在 legacy 身份命中时注入；AC-005 专项断言 `cart_` 无头、无计数 |
| 历史日志 key 被改坏（日志管道已在消费 `payment.legacy_flow.used`） | **中** | concern 支持 `message:` 覆盖；AC-003 断言 key 与 `entry_point` 推断不变 |
| OpenAPI 手写区改动与 `generated:check` 漂移 | 低 | 只动 paths（非 schemas 区）；实施后跑 `generated:check` |
| 新增 spec 未注册 verifier → verify-test 无法关闭 | 低 | 复用 `p1-order-flow-rspec` 命令追加该 spec 文件（B2/B3 已验证的惯例） |
| 范围蔓延到「删 legacy」 | 低 | PRD §1.4 明确非目标；删除须独立 PRD（§46） |

**回滚难度**：低——纯加法；回滚 = revert 本批提交（无迁移、无数据变更）。

## 决策节点（需用户确认）

1. **弃用信号形式**：响应头三件套 + OpenAPI `deprecated` + SDK `@deprecated` JSDoc（推荐，机器可读）／仅文档标注（最小改动）。
2. **FR-007（SDK JSDoc）**：纳入（会同步 `pallastrade-typescript-sdk` Skill）／不纳入。
3. **端点删除**：确认**本批不删**（§46：阈值未达，删除须独立立项）。
4. **退役阈值取值**：默认「连续 30 天 flow 计数为 0 可立项」——是否采用该默认值。

> ⏸️ **请确认以上理解与决策。确认后 AI 进入实施（gate preparation 其余项清除 → 编码 → 验证 → 证据 → 提交）。**
