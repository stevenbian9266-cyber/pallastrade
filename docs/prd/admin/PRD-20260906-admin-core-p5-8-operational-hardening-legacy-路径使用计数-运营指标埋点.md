# PRD-20260906-admin-core-p5-8-operational-hardening-legacy-路径使用计数-运营指标埋点

| 元数据 | 值 |
|---|---|
| 状态 | approved |
| 创建日期 | 2026-09-06 |
| 来源 | 需求：CORE-P5-8 Operational Hardening（legacy 路径使用计数 + 运营指标埋点） |
| 分类 | admin（自动判定） |

| 关联 Skill | pallastrade-payments / pallastrade-checkout / pallastrade-events-webhooks / pallastrade-customization / pallastrade-testing |
| 关联 REQ | REQ-20260906-cp5-8-operational-hardening.md（实施时回填） |
| 关联 PRD | N/A（全新） |
| 需求类型 | 优化迭代（运营可观测性，无新增商业能力） |

> 来源：`豆包梳理业务需求/P5 — Commerce Core Consolidation & Legacy Convergence.md` §27/§28（CORE-P5-8 Operational Hardening）+ `docs/research/RESEARCH-20260906-p5-0-commerce-core-convergence-audit.md` §5.7/§10（FROZEN-2 依据：legacy 完成面无 runtime 使用计数，无法证明"真没人用"）。

## 1. 背景与目标

- **一句话需求原文**：需求：CORE-P5-8 Operational Hardening（legacy 路径使用计数 + 运营指标埋点）
- **背景**：CORE-P5-0 审计结论（§10.2 Retirement Gate）要求每条 legacy 删除前必须有 runtime 观测；当前除 `PaymentWebhookEvent` 与 ledger 外，**legacy 完成面全部无 runtime 使用计数**——只能证明"代码没引用"，无法证明"生产真没人用"。现有 gauge 型周期计数（`RecoverSweeperJob`/`ReconcileSweeperJob` JSON 日志）已覆盖 stuck/recovery/mismatch 快照，但缺 **legacy 路径事件率**与 **recovery/manual_review 事件增量**。仓库**零外部 metrics 依赖**（无 Prometheus/Yabeda/statsd，仅 lograge+sentry）。
- **目标**：
  1. 所有 legacy 完成/回调入口产生**结构化 JSON 计数行**（`event: legacy.*`），供日志管道聚合判断真实使用；
  2. `commerce_transaction.recovery_required/manual_review` 事件化计数（与 sweeper gauge 互补为事件率）；
  3. **零新增外部依赖、零 DB/表变更、零行为变化**（纯观测旁路，可摘除）。
- **成功指标**：CORE-P5-0 表 5.7 中标记 `❌ 无计数` 的 legacy 面全部可观测；`grep -c "event.*legacy" <日志>` 可回答"某 legacy 入口 N 天调用次数"。

## 2. 用户故事 / 场景

- 作为平台运维/架构负责人，我希望在 CORE-P5-5 删除任何 legacy 前，能看到该入口的真实生产调用计数（而非 grep 代码），以便满足 Retirement Gate（CORE-INV-09）。
- 场景列表：
  - 正常：legacy 完成路径（Checkout::Complete / Orders::Complete / Carts::Complete legacy 分支 / cart 域 session complete / 组合 legacy 成员 / Admin while-@order.next / ManualSplit 直写）各打一行 `legacy.*` JSON；
  - 正常：legacy provider 回调（Stripe legacy handlers / Adyen legacy processor / PayPal legacy CaptureOrder）各打一行 `legacy.provider_callback.calls`；
  - 正常：`commerce_transaction.recovery_required` / `manual_review` 事件产生事件级计数行；
  - 边界：canonical 标准流（pending 单经 `Transactions::Finalize`/`Carts::Complete` standard 分支）**不产生 legacy 计数**（无噪声）；
  - 异常：采集端不可用/日志丢弃 → 不影响业务（计数为纯旁路，绝不 raise、绝不阻塞主流程）；
  - 幂等：同一事件重复（webhook 幂等重放）→ 每行独立计数（事件率口径），不落库不幂等。

## 3. 功能需求（FR）

- FR-001：新增 `PallasTrade::OperationalMetrics`（`backend/pallastrade_gems/pallastrade_core/lib/pallastrade/operational_metrics.rb`）——`count(event:, **fields)` 输出 `Rails.logger.info({event:.., at:..}.merge(fields).to_json)`（与 sweeper JSON 风格一致）；提供 `legacy(metric:, **fields)` 便捷方法输出 `legacy.<metric>.calls`。纯旁路，任何异常不抛出。
- FR-002：`Checkout::Complete#call` 入口打 `legacy.checkout_complete.calls`（order_id）——覆盖组合 legacy 成员与 Stripe/Adyen/PayPal legacy 完成原语总入口。
- FR-003：`Carts::Complete` **legacy 分支**（`!cart.standard_flow?` → `advance_to_complete!` 路径）打 `legacy.carts_complete.calls`；standard 分支**不打**（canonical 无噪声）。
- FR-004：`Orders::Complete#call` 入口打 `legacy.orders_complete.calls`（admin/B2B）。
- FR-005：Admin `payments_controller` create/capture 的 `while @order.next` 完成点打 `legacy.admin_payment_complete.calls`。
- FR-006：`Orders::ManualSplit#finalize_completed_child!` 直写完成打 `legacy.manual_split_complete.calls`（绕过状态机/事件，只能原位打点）。
- FR-007：cart 域 `payment_sessions#complete`（compat）入口打 `legacy.payment_completion.calls`（沿用 `payment.legacy_flow.used` 已有 message 风格，新增 JSON 计数行）。
- FR-008：legacy provider 回调计数：Stripe `CompleteOrder` 单订单 legacy 分支、Adyen `authorisation_event_processor` success→`checkout_complete_service` 处、PayPal legacy `CaptureOrder`——各打 `legacy.provider_callback.calls`（字段 provider: stripe/adyen/paypal）。
- FR-009：新增 `PallasTrade::OperationalMetricsSubscriber`（core subscriber）订阅 `commerce_transaction.recovery_required` / `commerce_transaction.manual_review`，各输出一行 JSON 计数（`event: commerce_transaction.<state>`，字段 transaction_id/order_ids）；注册进 core engine `subscribers.concat`。**零模型改动**（状态机已 publish 事件）。
- FR-010：新增 spec：helper 单测 + 2-3 个代表性调用点 logger 断言（复用 `cart_payment_sessions_controller_spec.rb:46-67` stub-Rails.logger 模式）。

## 4. 非功能需求（NFR）

- 性能：每点一次 `Rails.logger.info`（info 级，producer 同步开销可忽略；不新增 IO/网络）。
- 安全：不记录 PII/密钥；只记 prefixed_id / provider / state。
- 兼容：不改任何状态机/服务返回值/路由；计数失败静默（`rescue nil` 或仅 info 日志，绝不 raise）。
- 可维护性：单一 helper + 固定 `event:` 命名；与 P4 sweeper JSON 风格一致；不改既有 `payment.legacy_flow.used`。

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：helper `count`/`legacy` 输出含 `event:` 的 JSON 行且不抛异常（helper spec）。
- AC-002 ← FR-002：legacy 单（非 standard）经 `Checkout::Complete` 完成 → 日志含 `event: legacy.checkout_complete.calls`（request/service spec）。
- AC-003 ← FR-003：standard 单经 `Carts::Complete` 完成 → **不出现** `legacy.carts_complete.calls`；legacy 分支出现（spec 断言 absent/present）。
- AC-004 ← FR-004：admin `Orders::Complete` 调用 → `legacy.orders_complete.calls`。
- AC-005 ← FR-005：Admin payments create/capture 推进 legacy 单 → `legacy.admin_payment_complete.calls`。
- AC-006 ← FR-006：admin 拆单源单 completed → 子单直写完成 → `legacy.manual_split_complete.calls`（service spec）。
- AC-007 ← FR-007：cart 域 session complete → `legacy.payment_completion.calls`（controller spec）。
- AC-008 ← FR-008：Stripe legacy `CompleteOrder` 单订单分支 / Adyen authorisation / PayPal CaptureOrder → `legacy.provider_callback.calls` 含对应 provider（各 gem spec 或 service spec）。
- AC-009 ← FR-009：`commerce_transaction.manual_review` 事件 → subscriber 输出 JSON 计数行（subscriber/service spec）。
- AC-010 ← FR-010：新增/更新 spec 全绿（backend rspec 子集），且不影响既有行为（无 legacy 计数 spec 断言可回归）。
- AC-011（NFR）←：计数异常不影响主流程（helper 内 rescue；spec 注入 logger raise 断言不冒泡）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | 无 metrics/legacy 完成逻辑（仅 TS 类型） | — | ✅ 宿主无埋点需求 |
| Core | `pallastrade_gems/pallastrade_core/app/` | `checkout/complete.rb`、`orders/complete.rb`、`carts/complete.rb`（legacy 分支 :40）、`orders/manual_split.rb:61-82`、`combination_member_complete.rb:30-35`、`commerce_transaction.rb:288-296`（recovery_required/manual_review 事件）、`subscribers/`、`recover_sweeper_job.rb:51-71`、`lib/pallastrade/events.rb` | ✅ 埋点宿主在 core；事件已发布，subscriber 零模型改动 |
| API | `pallastrade_gems/pallastrade_api/app/` | `store/carts/payment_sessions_controller.rb:73-144`（`log_legacy_flow_usage` 先例） | ✅ 复用 P0-7 模式 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | `payments_controller.rb:39,64`（while @order.next） | ✅ 埋点点确认 |
| Storefront | `storefront/src/` | 无后端 metrics 通道（仅 GTM/analytics） | ❌ 本需求不涉 |
| Platform | `platform/packages/` | 无 metrics 基建 | ❌ 本需求不涉 |
| provider gems | `pallastrade_stripe/adyen/paypal_checkout` | `complete_order.rb:40`、`authorisation_event_processor.rb:40`、`capture_order.rb:32` | ✅ provider legacy 埋点点确认 |

**结论**：core 是唯一实现层；埋点全部落 legacy 分支/legacy 原语/legacy provider 回调 + 一个 subscriber；无重复能力（唯一"计数"先例 `payment.legacy_flow.used` 保留不动，P5-8 补 JSON 事件率行）。

## 7. 技术影响

- 涉及文件（预计 ~12）：
  - 新增：`pallastrade_core/lib/pallastrade/operational_metrics.rb`、`pallastrade_core/app/subscribers/pallastrade/operational_metrics_subscriber.rb`
  - 修改：`carts/complete.rb`、`checkout/complete.rb`、`orders/complete.rb`、`orders/manual_split.rb`、`pallastrade_api/.../carts/payment_sessions_controller.rb`、`pallastrade_admin/.../payments_controller.rb`、`pallastrade_stripe/.../complete_order.rb`、`pallastrade_adyen/.../authorisation_event_processor.rb`、`pallastrade_paypal_checkout/.../capture_order.rb`、core engine.rb（注册 subscriber）
  - 测试：新增 `backend/spec/lib/pallastrade/operational_metrics_spec.rb` + 相关 request/service spec（沿用 stub logger 断言）
- 依赖：无新增 gem；无 DB/表/migration；无路由变更。
- 影响面：日志量少量增加（每 legacy 调用 1 行 info）；无商业行为变化。

## 8. 测试计划

- 新增测试文件：
  - `backend/spec/lib/pallastrade/operational_metrics_spec.rb`（FR-001/AC-001/AC-011）
  - `backend/spec/subscribers/pallastrade/operational_metrics_subscriber_spec.rb`（FR-009/AC-009）——若项目 subscriber spec 无先例则并入 service spec
- 更新测试文件：
  - `backend/spec/services/pallastrade/carts/complete_spec.rb`（FR-003/AC-003：standard 无噪声 + legacy 有行）
  - `backend/spec/services/pallastrade/checkout/complete_spec.rb`（FR-002/AC-002）
  - `backend/spec/requests/api/v3/store/cart_payment_sessions_controller_spec.rb`（FR-007/AC-007，复用既有 stub logger 模式）
  - `backend/spec/services/pallastrade/orders/manual_split_spec.rb`（FR-006/AC-006）
  - provider 相关（FR-008/AC-008）视 spec 现状以 service/request 断言
- AC 映射：AC-001..AC-011 → 上表对应 spec。

## 9. 文档同步清单（知识同步门）

- [ ] API 文档：不涉及接口变更（N/A）
- [x] 审计文档已产出：`docs/research/RESEARCH-20260906-p5-0-...`（§5.7 可观测性缺口 → 本 PRD 回填口径）
- [ ] Skill 文档：`pallastrade-events-webhooks`（若 subscriber 模式新增约定）——以 sync-check 判定
- [ ] 本 PRD 状态更新 + `docs/prd/README.md` 索引
- [ ] 场景库 `harness/scenarios/scenarios.json`：如新增 subscriber/helper 属行为模式，按 sync-check 判定是否加 GS 场景

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-06 | 0.1 | 初稿（依据 CORE-P5-0 审计 + CORE-P5 §27/28） | AI |
