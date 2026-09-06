# REQ-20260906-cp5-8-operational-hardening

> CORE-P5-8 Operational Hardening（legacy 路径使用计数 + 运营指标埋点）
> Task：`TASK-20260906124447-0c5b8f03`；PRD：`docs/prd/admin/PRD-20260906-admin-core-p5-8-operational-hardening-legacy-路径使用计数-运营指标埋点.md`

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | metrics/counter/legacy/complete | 仅 TS serializer 类型；无宿主业务逻辑 | ✅ 宿主无需改动 |
| Core — models | `pallastrade_core/app/models/` | CommerceTransaction publishes_lifecycle_events、recovery_required/manual_review 事件（:288-296）；payment_session/stock_reservation 事件 | ✅ 事件已发布，计数可订阅，零模型改动 |
| Core — services | `pallastrade_core/app/services/` | checkout/complete.rb（legacy 原语）、orders/complete.rb、carts/complete.rb（legacy 分支 :40 advance_to_complete!）、orders/manual_split.rb:61-82（直写）、payments/combination_member_complete.rb:30-35、transactions/recover_sweeper_job.rb:51-71（既有 JSON gauge） | ✅ 埋点宿主在 core services |
| Core — lib | `pallastrade_core/lib/` | events.rb（总线/subscriber 门面） | ✅ helper 可放 `lib/pallastrade/operational_metrics.rb` |
| API — controllers | `pallastrade_api/app/controllers/` | store/carts/payment_sessions_controller.rb:73-144（`log_legacy_flow_usage` 先例 :120-144） | ✅ 复用 P0-7 模式加 JSON 行 |
| Admin — controllers | `pallastrade_admin/app/controllers/` | payments_controller.rb:39,64（while @order.next） | ✅ 埋点确认 |
| provider gems | stripe/adyen/paypal_checkout | complete_order.rb:40（stripe legacy 分支）、authorisation_event_processor.rb:40、capture_order.rb:32 | ✅ provider legacy 埋点确认 |
| Storefront | `storefront/src/` | 无后端 metrics 通道（仅 GTM/analytics） | ❌ 不涉 |
| Platform | `platform/packages/` | 无 metrics 基建 | ❌ 不涉 |

### 搜索结论

- **能力现状**：core 已有成熟事件总线 + Subscriber 机制（`events.rb`/`subscriber.rb`/engine 注册）；P4 sweeper 已产 gauge 型 JSON 计数行（recover_sweeper `transactions.recover_sweeper`、reconcile_sweeper `reconciliations.sweeper`）；P0-7 已有 `payment.legacy_flow.used` message 风格计数先例。**缺**：legacy 完成/回调入口的 JSON 事件率计数 + recovery/manual_review 事件级计数。
- **需新建**：`OperationalMetrics` helper + 一个 subscriber（纯旁路，不新增外部依赖/DB）。
- **防重复判定**：不复用/修改 `payment.legacy_flow.used`（保留）；不新建事件；不改 sweeper。

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树："React to something happening… → Events subscriber（pallastrade-events-webhooks）"；优先级 Settings→Events→Dependencies→…→Decorators；**旁路副作用用 subscriber，不要 decorate model 加 after_save**。 |
| `ai/skills/pallastrade-events-webhooks/SKILL.md` | ✅ 已读 | "Automatic lifecycle events fire after the transaction commits"；subscriber 写法 `class X < PallasTrade::Subscriber; subscribes_to '...'; def handle(event)…end`；默认 async，可 `async: false` 同步；**未注册的 subscriber 是静默 no-op**，需 `PallasTrade.subscribers << X` 注册。 |
| `ai/skills/pallastrade-payments/SKILL.md` | ✅ 已读（本会话） | PaymentSession 现代流/组合收敛描述；`checkout/complete.rb` 为 legacy 语义（结合 checkout skill RISK-01）；为完成路径术语权威。 |
| `ai/skills/pallastrade-checkout/SKILL.md` | ✅ 已读（本会话） | "ManualSplit：子订单 `update_columns(state:'complete', completed_at:)` 绕过状态机"（P6 内部编号）；"Checkout::Complete legacy / RISK-01（2026-09-04）：legacy primitive 无法完成 standard pending 单"——埋点须区分 standard/legacy。 |
| `ai/skills/pallastrade-testing/SKILL.md` | ✅ 已读 | 测试栈 RSpec+Factory Bot；"Always use factories — never call Model.create directly in tests"；`pallastrade_dev_tools` 提供共享上下文/授权 stub。 |
| `ai/skills/harness-prd/SKILL.md` | ✅ 已读 | PRD 流程：prd new（自动分类+查重）→ 模板扩充 → 用户确认 → gate+REQ → AC↔测试 → 知识同步。 |

**按需 Skill：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-api-v3` | ❌ | — | 无接口变更 |
| `pallastrade-events-webhooks` | ✅ | ✅ 已读 | 见上（subscriber 注册/handle/async 语义） |
| `pallastrade-testing` | ✅ | ✅ 已读 | 见上（RSpec + stub logger 断言模式，先例 `cart_payment_sessions_controller_spec.rb:46-67`） |
| `pallastrade-storefront` | ❌ | — | 无前端变更 |
| `pallastrade-i18n` | ❌ | — | 无 i18n 变更 |

---

## 需求标题

为 PallasTrade Commerce Core 增加运营观测：所有 legacy 完成/回调入口输出结构化 JSON 使用计数（`event: legacy.*`），并对 `commerce_transaction.recovery_required/manual_review` 输出事件级计数——用于 CORE-P5-5 legacy 退休决策（CORE-INV-09 Retirement Gate）与 stuck/recovery 事件率监控。纯旁路，无行为变化。

## 任务类型

功能优化（运营可观测性；无新增商业能力，符合 CORE-P5 §31 边界）

## 需求描述

1. **新增 `PallasTrade::OperationalMetrics`**（core `lib/pallastrade/operational_metrics.rb`）：`count(event:, **fields)` → `Rails.logger.info({ event:, at:, **fields }.to_json)`；`legacy(metric:, **fields)` → `event: "legacy.#{metric}.calls"`。任何 logger 异常内部 rescue，绝不抛出/阻断主流程。
2. **legacy 完成入口埋点**（各一行 `legacy.*.calls`）：
   - `Checkout::Complete#call` 入口 → `legacy.checkout_complete.calls`（组合 legacy 成员 + provider legacy 完成原语总入口）
   - `Carts::Complete` legacy 分支（`!standard_flow?`）→ `legacy.carts_complete.calls`；standard 分支不计数
   - `Orders::Complete#call` 入口 → `legacy.orders_complete.calls`（admin/B2B）
   - Admin `payments_controller` `while @order.next` 完成点 → `legacy.admin_payment_complete.calls`
   - `Orders::ManualSplit#finalize_completed_child!` → `legacy.manual_split_complete.calls`
   - cart 域 `payment_sessions#complete`（compat）→ `legacy.payment_completion.calls`
3. **legacy provider 回调埋点**：Stripe `CompleteOrder` 单订单 legacy 分支 / Adyen `authorisation_event_processor` success→`checkout_complete_service` / PayPal `CaptureOrder` → `legacy.provider_callback.calls`（字段 `provider: stripe|adyen|paypal`）。
4. **事件级计数 subscriber**：`PallasTrade::OperationalMetricsSubscriber`（subscribes_to `commerce_transaction.recovery_required`、`commerce_transaction.manual_review`，`async: false`）→ 各输出 JSON 行（字段 transaction_id/state）；注册进 core engine `subscribers.concat`。
5. **测试**：helper spec + 代表性调用点 logger 断言（stub `Rails.logger.info`，沿用既有模式）。

## 影响范围（harness affected 输出）

- 变更文件（预计 ~12，全在 allow 内）：新增 `operational_metrics.rb`、`operational_metrics_subscriber.rb` + 2 spec；修改 core `carts/complete.rb`、`checkout/complete.rb`、`orders/complete.rb`、`orders/manual_split.rb`、engine.rb（注册）、api `carts/payment_sessions_controller.rb`、admin `payments_controller.rb`、stripe `complete_order.rb`、adyen `authorisation_event_processor.rb`、paypal `capture_order.rb` + 相关 spec。
- 无依赖、无 DB、无路由、无 API 契约变更。

## 技术方案（初步）

- 按 customization 决策树：**事件/旁路副作用 → subscriber**（优先于 decorator）。legacy 原语/service 的调用点埋点用一行 helper 调用（无事件可依赖）；CommerceTransaction 生命周期计数用 subscriber 订阅既有事件。
- 计数输出统一 JSON `{event:, at:, ...}`（与 P4 sweeper 风格一致），字段只含 prefixed_id/provider/state，无 PII。
- subscriber `async: false`（计数廉价、避免 ActiveJob 队列噪声、事件低频）。

## 风险点

- 最高风险：计数成为主流程耦合点 → 以「helper 内 rescue + 单测断言 logger 异常不冒泡（AC-011）」隔离；subscriber 异常由事件总线处理不阻断 publish。
- 回滚难度：低——纯新增旁路；回滚 = 还原插入行/删 subscriber 注册即可。
- 双口径说明：sweeper gauge（周期快照）与事件计数（增量）并存是有意为之，非重复。

## 决策节点

> ⏸️ **请确认以上 PRD/REQ 理解正确。确认后进入实施。**
