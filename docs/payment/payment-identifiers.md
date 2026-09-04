# Payment Identifiers（标识符体系）

> P0-6（FR-063）：从 `order_id` 到 PSP / Webhook 的可关联标识链，供排障与审计使用。

## 1. 前缀速查（has_prefix_id / Sqids）

| 前缀 | 实体 | 说明 |
|---|---|---|
| `or_` | Order（含 legacy 购物车行） | 订单/购物车 |
| `cart_` | `PallasTrade::Cart`（新购物车实体） | 标准流程提交前 |
| `ps_` | PaymentSession | 支付会话（STI：bogus/stripe/adyen/paypal） |
| `pm_` | Payment / PaymentMethod | **两个实体共用 pm_ 前缀**——按上下文区分 |
| `pcom_` | PaymentCombination | 组合支付载体 |
| `cs_` | Stripe Checkout Session id | `PaymentSession.external_id`（迁移后默认形态） |
| `pi_` | Stripe PaymentIntent id | `Payment#response_code`（即 transaction_id） |
| `evt_` | Stripe Event id | `PaymentWebhookEvent.provider_event_id` |
| `whsec_` | Stripe Webhook signing secret | 加密存储（P0-5） |
| `re_`/… | Refund 等 | 其余资源 |

## 2. 关联链（Trace 目标）

```text
order(or_) ── has_many ──▶ payment_sessions(ps_, external_id=cs_/pi_)
   │                            │ payment_session_id（P0-1 正式 FK）
   ▼                            ▼
payments(pm_, response_code=pi_) ◀── payment_id
   │
   ▼
Stripe PaymentIntent(pi_) ── Stripe Event(evt_) ──▶ PaymentWebhookEvent
   （provider_reference）          （provider_event_id）
```

- **Order → Session**：`order.payment_sessions`（active 复用按 amount+mode）。
- **Session → Payment**：`Payment.payment_session_id`（P0-1 正式外键；旧 `external_id==response_code` 拼接已废弃）。
- **Payment → PSP**：`Payment#response_code`（Stripe = `pi_`）。
- **Webhook**：`PaymentWebhookEvent.payment_session_id` + `provider_event_id` + `action`。
- **业务键**：`operation_key`（`external_data['operation_key']`）贯穿多次尝试。

## 3. 使用纪律

- API 响应**只暴露前缀 id**，绝不返回裸整型主键（AGENTS.md §4）。
- 排障输入任一 id（`or_/ps_/pm_/pi_/evt_`）应能沿上表双向定位；缺链即 bug（P0-1 修正是关键）。
- `pm_` 双义（Payment vs PaymentMethod）：日志/审计请同时带 `resource_type` 消歧。
