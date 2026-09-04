# Webhook 链路（Stripe → PallasTrade）

> P0-2/P0-6「显式化」：验签 → Event Store/Dedup → Job 处理 → Retry/Replay。

## 1. 入口与验签

- Store API：`POST /api/v3/webhooks/payments/:payment_method_id`（api gem `Webhooks::PaymentsController`）。
- **同步验签**：`payment_method.parse_webhook_event(raw_body, headers)`；失败 → `401`（`WebhookSignatureError`）。
- 验签后**同步落库**（P0-2），避免处理阶段事件丢失。

## 2. 事件 → 归一 action（Stripe）

`WEBHOOK_EVENT_ACTIONS`（stripe gateway）映射 8 类事件：

| Stripe 事件 | action |
|---|---|
| `checkout.session.completed` | captured |
| `checkout.session.async_payment_succeeded` | captured |
| `payment_intent.succeeded` / `payment_intent.captured` 等 | captured/authorized |
| `payment_intent.payment_failed` / `checkout.session.async_payment_failed` | failed |
| `checkout.session.expired` 等 | canceled |

## 3. 可靠性外壳（P0-2，Event Store）

```text
controller（验签→record）→ PaymentWebhookEvent（received）
   → HandleWebhookJob（30s 延迟；mark_processing attempt+1）
   → Payments::HandleWebhook（业务幂等不变）→ processed
   异常 → mark_failed + raise（Deadlocked/Connection 类自动重试）
   业务 failure → mark_failed（不无限重试，交 Manual Replay）
```

- **Dedup**：`UNIQUE(provider, provider_event_id)` + `create_unique` → 重复投递 ACK 200 不重复入队。
- **30s 延迟 = contention mitigation**（让 storefront 自己的 complete 先落地），不是顺序保证。
- **不再 swallow**（P0-2）：未知/基础设施异常 controller 返回 500，交 provider 按 Retry-After 重投。
- legacy 通道（`use_legacy_webhook_handlers`，10s 延迟）保留但非主路径。

## 4. Manual Replay（FR-026）

- `PallasTrade::Payments::ReplayWebhookEvent`：复用原 Event Record → 同一 HandleWebhookJob（attempt+1）→ **写 Audit**（P0-6 `webhook_replay`）→ 不制造假 provider 事件。
- `processing` 中拒绝重放。

## 5. 开放项

- Webhook 端点尚缺 rswag spec → 不在权威 OpenAPI（store.yaml）中；补 spec 后随 `swaggerize` 再生成（见 P0-4 同一待办）。
