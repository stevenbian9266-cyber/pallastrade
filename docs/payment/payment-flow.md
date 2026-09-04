# Payment Flow（支付主链路）

> P0-6「显式化」：冻结当前两条支付流的真实行为。实现语义以代码为准（P0-0 基线测试锁定）。

## 1. 两条流

```text
Canonical（Order 域，P1 2026-08-30+）        Legacy（Cart 域，兼容）
──────────────────────────────             ──────────────────────────
submit cart → Order(or_)                  legacy checkout 持 Order(state=cart)
→ /orders/:id/payment_sessions (Start)    → /carts/:id/payment_sessions (Start, P0-3 起)
→ 支付会话 → 完成/Webhook                 Express(Apple/Google Pay) / 一页式 / redirect 返回
→ Carts::Complete（pay! + finalize!）      → 同一 Carts::Complete 收敛
```

- **Standard（Order 域）**：`PaymentSessions::Start` = order lock + active 会话复用（同金额/同 mode + `REUSE_WINDOW=30.min` 新鲜度）+ 稳定 `operation_key`（含 order/pm/mode/amount/attempt）+ provider idempotency + 二次锁 winner 仲裁。
- **Legacy（Cart 域）**：P0-3 起同一 `PaymentSessions::Start` 委托（`Carts::PaymentSessionsController#create`），消除「每次随机 key / 无复用」的重复扣款风险。

## 2. 幂等机制（NFR-001）

| 层 | 机制 |
|---|---|
| 业务意图 | `operation_key` = `pallastrade-order-{id}-method-{pm}-{mode}-amount-{x}-attempt-{n}`（金额/quote 变化 → 新 key；timeout 重试同 key） |
| Provider | Stripe idempotency（`external_data['idempotency_key']`） |
| 本地 | active 会话复用 + 订单锁 + terminal-state 幂等（session completed? 短路） |
| 完成 | `Carts::Complete` 幂等；webhook 与 API complete 竞争由「webhook 30s 延迟 + completed? 短路」收敛 |

## 3. 完成路径三路收敛

```text
API complete（前端 confirm 后）   Webhook（checkout.session.completed…）   Redirect（离站返回）
        └──────────────┬──────────────────────────────┘
                       ▼
        complete_payment_session → Payment 唯一创建 → Carts::Complete（幂等）
```

- 金额权威：会话创建金额 = 服务端 `order.amount_due`（Express 展示金额 = `Cart#express_payment`，P0-4）。
- 完成前最终强校验：`verify_payment_intent_matches!`（amount/currency）——不得绕过。

## 4. Trace 字段（FR-063）

结构化支付日志应含以下键，使「输入 order_id → session → payment → PSP → webhook」可串联排障：

| 字段 | 来源 |
|---|---|
| `request_id` | 请求级（控制器中间件注入 `Thread.current`；尚未覆盖处见 §6 开放项） |
| `order_id` | Order（`or_`/整数） |
| `payment_session_id` | PaymentSession（`ps_`） |
| `payment_id` | Payment（`pm_`） |
| `payment_method_id` | Gateway 配置（`pm_`） |
| `provider` | stripe/adyen/…（webhook event `provider` 列） |
| `provider_reference` | Stripe PI/Charge id（`pi_`/`ch_`）；Payment#response_code |
| `provider_event_id` | Webhook 事件 id（`evt_…`） |
| `operation_key` | PaymentSession.external_data['operation_key'] |

已落地的结构化日志点：`Payments::HandleWebhookJob`（event 生命周期）、`Payments::ReplayWebhookEvent`（`payment.webhook.replay`）、`Audit`（P0-6 审计表，含 request_id 列）。

## 5. 关联测试基线

- 行为锁定：`docs/payment/P0_BEFORE_REFACTOR_TEST_BASELINE.md`（P0-0）。
- 幂等：`PaymentSessions::Start` spec、cart/order payment sessions request specs。
- Webhook：见 [webhook.md](./webhook.md)。

## 6. 官方声明（P0-7，FR-070/FR-071）

```text
Order-domain PaymentSession Flow  =  Canonical Standard Flow
Cart-domain Legacy Flow            =  Compatibility Only
```

- **不删除 Legacy**；存量只做兼容。
- Legacy 入口（`carts/payment_sessions` create 等）已打 deprecated 注释 + structured usage log：
  - key：`payment.legacy_flow.used`
  - 字段：`flow_type`（legacy_cart_session_create）、`entry_point`（express_checkout / legacy_one_page / unknown）、`payment_method_id`、`order_id`
- 统计口径：按日志 `message=payment.legacy_flow.used` 计数即可回答「Legacy 还有多少真实流量」（见 [LEGACY_FLOW_BASELINE.md](./LEGACY_FLOW_BASELINE.md)）。

> ⛔ **DO NOT ADD NEW PAYMENT FEATURES TO LEGACY FLOW** —— 新支付能力一律走 Order 域 Start / Canonical 链。
