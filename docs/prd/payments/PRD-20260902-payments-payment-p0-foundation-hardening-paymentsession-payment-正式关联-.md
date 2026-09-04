# PRD-20260902-payments-payment-p0-foundation-hardening

| 元数据      | 值                                                                      |
| -------- | ---------------------------------------------------------------------- |
| 状态 | approved |
| 创建日期     | 2026-09-02                                                             |
| 分类       | payments                                                               |
| 需求类型     | 优化迭代：支付可靠性 / 安全加固                                                      |
| 关联 Skill | `pallastrade-payments`、`pallastrade-data-model`、`pallastrade-security` |
| 关联 REQ   | 实施阶段分工作包生成                                                             |
| 核心原则     | Stripe-first，保留现有主链，不重写 Payment Domain                                 |

> 权威现状依据：`P0任务.md`、`支付现状分析.md`。本 PRD 将已核实的支付现状收敛为可执行 FR / NFR / AC。

---

## 1. 背景与目标

PallasTrade 已具备成熟的标准支付主链：

`PaymentSession → Gateway → Stripe → Payment → Carts::Complete`

并已完成 Stripe SDK 隔离、Order 锁、active session reuse、`operation_key`、PSP 幂等、API/Webhook/Redirect 三路完成收敛等能力。

当前 P0 不建设新的 Payment Center，而解决以下已确认问题：

1. `Payment ↔ PaymentSession` 依赖 `response_code ↔ external_id` 字符串关联，`cs_ → pi_` 场景已不可靠。
2. Webhook 无事件事实表、数据库级去重、业务异常重试和失败可追踪能力。
3. Express/cart legacy 支付创建的幂等能力弱于 Standard。
4. Express 前端仍参与 PSP amount / line items 重算。
5. Gateway sensitive credentials 以明文形式存储。
6. Provider Contract、错误分类、Trace、Audit、支付文档尚未显式化。
7. Standard / Legacy 支付边界仍需治理。

### P0 目标

在**不重写现有支付系统**的前提下：

* 加固 Stripe 主链可靠性。
* 建立 PaymentSession / Payment 正式关系。
* 建立可靠 Webhook 基础设施。
* 消除 Express 重复扣款和金额双源风险。
* 保护敏感 Gateway Credentials。
* 明确未来 Checkout / OTS / Multi-PSP 的扩展契约。

---

## 2. Scope Lock

### 本期实现

* P0-0 支付回归安全网
* P0-1 PaymentSession ↔ Payment 正式关联
* P0-2 Webhook Event Store / Dedup / Retry / Replay
* P0-3 Express Checkout 幂等加固
* P0-4 Express 服务端金额权威化
* P0-5 Gateway Secret 安全迁移
* P0-6 Contract / Error / Trace / Audit / Docs
* P0-7 Legacy Guardrail

### 本期禁止

* PaymentAttempt 新模型
* Payment Router
* ProviderRegistry
* Adyen 接入
* Payment / PaymentSession 状态机重写
* Order `payment_state` 重写
* decimal → bigint minor-unit 数据库迁移
* Sqids → ULID
* Checkout 全面重写
* OTS / Saga
* Ledger / Reconciliation
* 删除 Legacy Flow
* 与 P0 无关的大规模代码调整

---

# 3. 功能需求

## P0-0 回归安全网

### FR-000

补齐支付核心行为测试，锁定当前生产语义：

* Standard PaymentSession Start
* active session reuse
* `operation_key`
* Stripe idempotency
* 并发 Start
* duplicate complete
* API Complete + Webhook 竞争
* Redirect + Webhook 竞争
* Payment 唯一创建
* `Carts::Complete` 幂等
* amount mismatch
* currency mismatch
* `cs_` / `pi_` 模式
* Express 重复调用

输出：

`P0_BEFORE_REFACTOR_TEST_BASELINE`

---

## P0-1 PaymentSession ↔ Payment 正式关联

### FR-010

`pallastrade_payments` 新增：

`payment_session_id NULL`

建立：

* `Payment belongs_to :payment_session, optional: true`
* `PaymentSession has_one :payment`

### FR-011

所有通过 **Canonical PaymentSession Flow** 创建的 Payment 必须显式关联 originating PaymentSession。

非 PaymentSession 来源的 Payment 可以保持 `NULL`。

### FR-012

`find_or_create_payment!` 及 Stripe 完成链显式使用 PaymentSession 创建 / 定位 Payment。

### FR-013

重新定义字段职责：

* `payment_session_id`：内部实体关联
* `response_code`：PSP transaction/reference

禁止新增 `response_code == external_id` 作为内部关联方式。

Legacy 兼容代码必须标记：

`LEGACY_COMPATIBILITY`

### FR-014

历史数据仅可靠确认时回填：

* `pi_` 且 `response_code == external_id`：允许回填。
* `cs_` 或存在歧义：不得通过金额 / 时间等弱条件强猜，保持 `NULL`。

### FR-015

冻结业务不变量：

> 一个 PaymentSession 最多产生一个 Payment。

API Complete、Webhook、Redirect 重复触发必须复用同一个 Payment。

是否增加 `UNIQUE(payment_session_id)` 必须先完成真实数据审计，不得默认创建。

---

## P0-2 Webhook Event Store + Dedup + Retry

### FR-020

新增：

`pallastrade_payment_webhook_events`

至少包含：

* provider
* payment_method_id
* provider_event_id
* event_type
* provider_created_at
* payload
* status
* attempt_count
* received_at
* processing_at
* processed_at
* last_error_class
* last_error_message
* timestamps

唯一约束：

`UNIQUE(provider, provider_event_id)`

状态：

* received
* processing
* processed
* failed

### FR-021

Webhook 新流程：

```text
Verify Signature
→ Parse Provider Event
→ Persist Raw Verified Event
→ Deduplicate
→ Enqueue
→ HandleWebhook
→ processed / failed
```

`payload` 保存**验签后的原始 Provider Event**，不得只保存归一 action。

### FR-022

已存在相同 `provider_event_id`：

* 始终 ACK 200
* 不创建第二条业务处理链
* FAILED 恢复由 Job Retry / Manual Replay 处理

### FR-023

`attempt_count` 定义为：

> HandleWebhook 实际开始执行次数。

首次执行、Job retry、Manual Replay 均增加。

### FR-024

禁止：

`rescue StandardError → log → swallow`

未知异常 / transient error：

```text
mark failed
→ 保存错误
→ raise
→ Job retry
```

### FR-025

保留现有 30s delay，但定义为：

`contention mitigation`

不是：

`ordering guarantee`

### FR-026

新增：

`Payments::ReplayWebhookEvent`

Replay：

* 使用原 Event Record
* attempt_count + 1
* 走同一 HandleWebhook
* 写 Audit
* 不制造新的虚假 Provider Event

---

## P0-3 Express Checkout 幂等加固

### FR-030

定义：

`EXPRESS_PAYMENT_INTENT_IDENTITY`

至少考虑：

* cart / order reference
* payment method
* authoritative amount / quote version
* attempt number

金额或结算版本变化后，不得错误复用旧支付意图。

### FR-031

Express 创建路径获得稳定 `operation_key`。

优先复用 Standard `PaymentSessions::Start` 的既有幂等能力。

禁止使用每次请求随机生成的 Provider idempotency key。

### FR-032

以下场景只能产生一个有效 PSP payment：

* 连续点击
* 并发请求
* HTTP retry
* Provider timeout 后客户端 retry

---

## P0-4 Express 金额服务端权威化

### FR-040

PSP authoritative amount 只允许来自 Server。

后端响应至少提供：

* amount
* currency
* display_total
* line_items

其中：

* `amount + currency` = 资金权威
* `line_items` = Wallet / UI 展示数据

不得通过 `sum(line_items)` 重新决定真实扣款金额。

### FR-041

前端停止使用：

* `toCents`
* `buildLineItems`

计算 authoritative PSP amount。

允许保留 formatter。

### FR-042

保留现有：

`verify_payment_intent_matches!`

对：

* amount
* currency

进行服务端最终校验。

---

## P0-5 Secret 安全迁移

### FR-050

完成 Sensitive Credential Inventory。

至少覆盖：

* Stripe secret key
* Stripe webhook signing secret
* 其他 Gateway sensitive credential

明确：

`publishable_key` 属于 public configuration，不要求按 secret 等级保护。

### FR-051

先实施：

`ENCRYPTION_COMPATIBILITY_SPIKE`

验证：

* Preference DSL
* YAML serialization
* password preference
* Masking
* Admin apply_preferences
* STI
* Rails encryption
* deployment key management

### FR-052

评估并选择风险最低方案：

A. Active Record Encryption
B. 独立 encrypted credential storage
C. External Secret Manager / `secret_reference`

### FR-053

迁移必须渐进：

```text
add
→ dual read
→ backfill
→ verify
→ encrypted write
→ cutover
→ remove plaintext
```

禁止 destructive migration。

### FR-054

迁移后输出：

`CREDENTIAL_ROTATION_PLAN`

评估是否轮换：

* Stripe API secret
* Webhook signing secret

---

## P0-6 Contract / Error / Trace / Audit / Docs

### FR-060 Provider Contract

新增：

`docs/payment/provider-contract.md`

冻结当前 Gateway 能力：

* create_payment_session
* update_payment_session
* complete_payment_session
* authorize
* capture
* cancel
* refund
* verify_webhook
* parse_webhook_event

当前 Provider：

`Stripe`

未来：

`Adyen`

本期不实现 Registry / Router。

### FR-061 术语

统一文档术语：

* `PallasTrade::PaymentMethod` = Gateway Configuration
* `TenderType` = CARD / APPLE_PAY / GOOGLE_PAY
* `PaymentProvider` = STRIPE / ADYEN

禁止为此重命名现有 Rails Model。

### FR-062 Error Mapping

增加可选 Canonical Failure Mapping：

* DECLINED
* INSUFFICIENT_FUNDS
* EXPIRED_CARD
* INVALID_CARD
* AUTHENTICATION_FAILED
* PROCESSING_ERROR
* PROVIDER_ERROR

本期只新增 Mapping Layer。

不得借此迁移 Payment 状态机或破坏现有 GatewayError / API contract。

### FR-063 Trace

支付结构化日志至少包含：

* request_id
* order_id
* payment_session_id
* payment_id
* payment_method_id
* provider
* provider_reference
* provider_event_id
* operation_key

目标：

```text
Order
→ PaymentSession
→ Payment
→ PSP Reference
→ Webhook Event
```

可关联排障。

### FR-064 Audit

Audit 至少记录：

* actor_type
* actor_id
* action
* resource_type
* resource_id
* request_id
* before
* after
* occurred_at

覆盖：

* Webhook Replay
* Manual Payment Repair
* Refund
* Gateway Credential Change

### FR-065 Docs

新增 / 更新：

* `docs/payment/payment-flow.md`
* `docs/payment/provider-contract.md`
* `docs/payment/webhook.md`
* `docs/payment/payment-identifiers.md`
* `docs/payment/security.md`
* Store/Admin OpenAPI 中的 Webhook / Payment 相关接口

---

## P0-7 Legacy Guardrail

### FR-070

正式声明：

`Order-domain PaymentSession Flow = Canonical Standard Flow`

`Cart-domain Legacy Flow = Compatibility Only`

### FR-071

Legacy：

* 禁止新增支付 Feature
* 增加 deprecated 标记
* 增加 structured usage log / metric

至少记录：

* flow_type
* entry_point
* payment_method
* cart / order reference

### FR-072

P0 完成时输出：

`LEGACY_FLOW_BASELINE`

至少盘点：

* Express Checkout
* legacy one-page
* redirect fallback

的真实代码入口 / 使用情况，为后续迁移提供依据。

---

# 4. 非功能需求

### NFR-001 Compatibility

不得破坏：

* active session reuse
* Order lock
* operation_key
* Stripe idempotency
* `Carts::Complete`
* API/Webhook/Redirect 三路收敛
* `verify_payment_intent_matches!`
* Card Elements 当前兼容路径
* terminal-state idempotency

### NFR-002 No Money-State Regression

如果 PSP 已成功收款，本地异常不得简单将其视为普通失败并创建第二次支付。

P0 修改必须保持未来 Recovery-compatible。

### NFR-003 Migration Safety

* Migration 渐进
* 新列优先 nullable
* 不强猜历史关联
* 不删除 Legacy 数据
* 必须提供 rollback strategy

### NFR-004 Security

Sensitive Credential：

* 不打印日志
* 不进入普通序列化
* Admin 默认 masked
* DB 新写入不保留明文

### NFR-005 Execution Isolation

单个 Coding Task / PR 原则上只实施一个 P0 工作包。

禁止一个 PR 同时修改全部 P0。

---

# 5. 验收标准

### AC-000

P0-0 测试基线全绿，并生成：

`P0_BEFORE_REFACTOR_TEST_BASELINE`

### AC-010

所有 Canonical PaymentSession Flow 新建 Payment 均具有正确 `payment_session_id`。

非 Session 来源 Payment 允许为 NULL。

### AC-012

`cs_` Session 完成产生 `pi_` Payment 时：

`Payment.payment_session_id`

仍准确指向 originating Session。

### AC-015

同一个 PaymentSession：

* API complete
* 5 次重复 Webhook
* Redirect fallback

最终最多存在 1 个关联 Payment。

### AC-020

同一 `provider_event_id` 投递 10 次：

* DB Event = 1
* 业务有效完成 = 1

### AC-021

Persisted payload 可查看原始 verified Provider Event。

### AC-023

Webhook transient failure：

```text
failed
→ retry
→ attempt_count 增加
→ processed
```

### AC-026

Manual Replay：

* 使用原 Event
* attempt_count 增加
* 写 Audit
* 不产生第二条 Event Record

### AC-030

Express：

* 连点 5 次
* 并发 2 请求
* timeout retry

只产生一个有效 PSP payment。

### AC-031

金额 / quote version 变化后不会错误复用旧 Express operation_key。

### AC-040

Backend total = `10549` 时：

Frontend/PSP 使用 authoritative `10549`。

Frontend 篡改金额：

Backend completion validation 拒绝。

### AC-050

使用固定测试 Credential Marker 验证：

新 DB dump 不包含：

* secret key plaintext
* webhook signing secret plaintext
* Inventory 标记的其他 sensitive credential

Admin 仅返回 masked 值，masked 回写不覆盖真实值。

### AC-060

Provider Contract 和术语文档存在。

### AC-062

Canonical failure mapping 可用，同时现有 GatewayError/API 行为保持兼容。

### AC-063

给定 `order_id`，能够关联：

```text
order
→ payment_session
→ payment
→ provider reference
→ webhook event
```

### AC-064

Replay / Credential Change 能记录完整 Actor Audit。

### AC-070

Legacy 入口有 usage metric，并生成 `LEGACY_FLOW_BASELINE`。

---

# 6. Execution Gate

业务主链：

```text
P0-0
↓
P0-1
↓
P0-2
↓
P0-3
↓
P0-4
```

安全工作可在 P0-0 后并行：

```text
P0-0
↓
P0-5
```

治理类工作可在行为稳定后独立执行：

```text
P0-6
P0-7
```

每个工作包必须：

1. Inspect
2. CURRENT_STATE
3. CHANGE_PLAN
4. FILE_CHANGE_LIST
5. MIGRATION_PLAN
6. Tests First
7. Implementation
8. Run Tests
9. RESULT
10. REMAINING_RISK

上一工作包存在高风险未解决时，不得继续修改下一条主链。

---

# 7. 技术影响范围

### Core

* Payment
* PaymentSession
* PaymentSessions::Start
* Payments::HandleWebhook
* Carts::Complete
* Gateway / PaymentMethod
* Audit / Events

### Stripe Gem

* Gateway
* Payment Session completion
* Webhook parse
* Provider error mapping

### API

* Webhook controller
* PaymentSession controller / serializer
* Error handling

### Storefront

* Express Checkout
* payment amount / line item consumption
* Payment result handling

### DB

新增候选：

* `payments.payment_session_id`
* `pallastrade_payment_webhook_events`
* Credential encrypted storage

### Docs

* Payment architecture
* Provider Contract
* Webhook
* Security
* Identifiers
* OpenAPI
* Payment Skill

---

# 8. 最终 Definition of Done

P0 完成必须满足：

* Stripe Standard Flow 无行为回归。
* Canonical PaymentSession 与 Payment 有正式关联。
* 一个 PaymentSession 不会因为重复完成创建多个 Payment。
* Webhook 有事实记录、DB 去重、失败记录、Retry、Replay。
* Express 重复请求不会造成重复有效支付。
* Express PSP amount 由 Server 唯一决定。
* Sensitive Gateway Credential 不再按当前方式明文裸存。
* Order → Session → Payment → PSP → Webhook 可排障关联。
* Standard / Legacy 边界明确且 Legacy 使用可观测。
* Payment / PaymentSession 状态机保持兼容。
* DB Money 模型保持不变。
* 未引入 PaymentAttempt。
* 未实现 Router / ProviderRegistry / Adyen。
* 未实施 OTS / Saga。
* 文档、测试、Migration、Rollback Strategy 完整。

## P0 最终产物

`PAYMENT_P0_COMPLETION_REPORT`

至少包含：

* Architecture Before / After
* DB Migrations
* PaymentSession / Payment Association
* Webhook Reliability
* Express Hardening
* Credential Security
* Trace / Audit
* Standard / Legacy Boundary
* Test Matrix
* Remaining Technical Debt
* Rollback Strategy
* P1 Checkout Readiness
* P2 OTS Readiness
* Future Adyen / Router Readiness

这版可以直接替换 AR 当前生成的 PRD；相比附件主要是补齐了会影响 Coding 正确性的约束，没有扩大 P0 范围。