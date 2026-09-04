# Gateway Provider Contract（冻结）

> P0-6（FR-060/061）：冻结当前 Gateway 抽象与语义。**只显式化，不重写**。
> 本期不实现 ProviderRegistry / Router；Provider 标识仅用于文档与日志。

## 1. 抽象合同

`PallasTrade::Gateway`（`< PaymentMethod`）是全部 PSP 适配的基类；Provider gem 提供 `…::Gateway < PallasTrade::Gateway`。核心合同方法：

| 方法 | 语义 | 落点 |
|---|---|---|
| `create_payment_session(order:, amount:, external_data:)` | 创建 PSP 支付会话（收款意图）；external_data 携带 `idempotency_key`/`mode` | core `PaymentMethod#create_payment_session` 契约 → Stripe Checkout Session / PaymentIntent |
| `update_payment_session(payment_session:, amount:, external_data:)` | 金额变化重建/绑新 PSP 会话；否则仅合并 external_data | Stripe Checkout Session immutable → recreate |
| `complete_payment_session(payment_session:, params:)` | 校验 PSP 状态 → Payment 唯一创建 → 会话终态；**不完成订单**（交给 Carts::Complete） | Stripe `verify_payment_intent_matches!` 强校验 |
| `authorize / purchase / capture / void / credit` | 传统 Payment::Processing 操作（legacy 通道保留） | core Payment 链 |
| `refund` | 退款 | 由 Refund 流程/网关 credit 承接 |
| `cancel` | 会话/授权取消 | — |
| `verify_webhook` / `parse_webhook_event` | 同步验签 + 归一 `{action:, payment_session:, metadata: {<provider>_event: …}}` | Stripe 8 类事件映射（见 webhook.md） |

辅助合同：
- `payment_session_class`（STI 会话类）、`session_required?`、`auto_capture?`、`available_for_order?`。
- 会话创建 amount 由服务端权威（`order.amount_due` / `total_minus_store_credits`）。

## 2. Provider 现状与演进

| Provider | 状态 | Gateway 类 | 事件 |
|---|---|---|---|
| Stripe | **当前唯一活跃** | `PallasTradeStripe::Gateway` | Checkout Session / PaymentIntent（`cs_`/`pi_` 双模式） |
| Adyen / PayPal Checkout | 未来（session 类已占位：`PallasTrade::PaymentSessions::Adyen/PayPalCheckout`，非本期接入） | `PallasTradeAdyen::Gateway` 等 | — |

新 Provider 接入时**必须**实现上表全部合同方法并补齐 `parse_webhook_event` → Event Store（P0-2 可靠性外壳对 provider 无耦合）。

## 3. 禁止

- 引入 ProviderRegistry / Payment Router / 本期 PaymentAttempt。
- 以「TenderType/PaymentProvider」重命名现有 Rails Model。
- 绕过 `verify_payment_intent_matches!` / 幂等链新增 PSP 直写。
