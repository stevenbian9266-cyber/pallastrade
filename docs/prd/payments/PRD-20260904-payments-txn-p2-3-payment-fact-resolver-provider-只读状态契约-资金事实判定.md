# PRD-20260904-payments-txn-p2-3-payment-fact-resolver-provider-只读状态契约-资金事实判定

| 元数据 | 值 |
|---|---|
| 状态 | approved |
| 创建日期 | 2026-09-04 |
| 来源 | P2 源文档 §19/§20/§54（TXN-P2-3 Payment Fact Resolver） |
| 分类 | payments（自动判定） |
| 关联 Skill | pallastrade-payments / pallastrade-checkout / pallastrade-data-model |
| 关联 REQ | REQ-20260904-txn-p2-3.md（实施时回填） |
| 关联 PRD | N/A（全新工作包） |
| 需求类型 | 新功能（P2 内部服务，无 API 面） |

## 1. 背景与目标

- **一句话需求原文**：继续 P2 → TXN-P2-3 Payment Fact Resolver（provider 只读状态契约 + 资金事实判定），先 Stripe。
- **背景**：P2（Commerce Transaction Orchestration & Recovery）已完成 TXN-P2-1（CommerceTransaction/TransactionOrder 数据层）与 TXN-P2-2（Transactions::Start/Resume + session 归属）。支付存在多完成入口（API complete / Webhook / Redirect / CombinationSettleJob / 前端 active confirm），**本地 DB 可能与真实资金不一致**（webhook 丢失、complete 前崩溃、session completed 但 Payment 未建、金额核对失败等）。后续 TXN-P2-4（Recovery）与 TXN-P2-5（Unified Finalization）**必须先判定真实资金事实**才能行动（绝不盲目 rescue→retry complete，见源文档 §26）。
- **目标**：
  1. Provider **只读**状态契约 `fetch_payment_status(payment_session:)`：基类（PaymentMethod）默认 `NotImplementedError`；Stripe 先行实现（PaymentIntent retrieve → status/amount/currency/provider reference）；bogus 测试实现供确定性 spec。**零副作用（不写库、不改状态）。**
  2. `Transactions::PaymentFactResolver#call(transaction:)`：综合本地证据（Payment completed / PaymentSession 状态 / PaymentWebhookEvent）+ 可选 provider 查询，输出 `paid / unpaid / ambiguous` 判定与原因。
  3. 无迁移、无 API 端点、无 SDK/契约变更（内部服务；消费方 TXN-P2-4/5）。
- **成功指标**：
  - 判定矩阵全覆盖 spec（本地 PAID short-circuit / 本地不一致→provider 权威 / 全失败→UNPAID / provider 不可达→AMBIGUOUS 不误判）。
  - local session completed 但 Payment 缺失场景（RISK 复现）可解析为 paid（provider succeeded）。
  - 全部新 spec 绿 + p0-payment-rspec 注册回归绿 + rubocop 0。

## 2. 用户故事 / 场景

- 作为 Recovery 引擎（P2-4），我希望在订单/交易本地状态可疑时先询问真实资金事实，以便安全决定重试 finalize 还是转 manual_review。
- 场景 A（本地已确认）：Payment completed 落库且金额匹配 → 直接 `paid`，无需外呼 provider。
- 场景 B（本地不一致）：session completed 但 Payment 缺失（如 webhook 丢失）→ provider 权威查询判定（succeeded → paid）。
- 场景 C（明确失败）：全部 attempt failed/canceled/expired 且无 completed payment → `unpaid`。
- 场景 D（未发起）：无任何 session → `unpaid`。
- 场景 E（进行中/存疑）：attempt 仍 pending/processing，provider 返回 processing/requires_capture → `ambiguous`。
- 场景 F（不可达）：provider 网络/API 异常 → 不猜，`ambiguous`（转 manual_review，不自动重复扣款）。
- 场景 G（部分入账）：completed payment 金额 < 交易金额 → 不构成足额 paid（`ambiguous`，交人工/恢复）。

## 3. 功能需求（FR）与验收标准（AC）

### FR-301：判定语义
Resolver 只回答"该 Transaction 当前真实资金事实"，输出三值之一并附原因：
- `paid`：已足额收到资金（本地 completed Payment 且金额匹配，或 provider 权威 succeeded/paid）。
- `unpaid`：无任何入账迹象，且所有支付尝试均已终态失败 / 尚不存在。
- `ambiguous`：无法确定（进行中 / 待捕获 / 部分入账 / provider 不可达 / 本地证据冲突）。
- AC-301（FR-301/302）：存在金额匹配的 completed Payment → `paid`，且**不触发 provider 查询**。
- AC-310（FR-301）：completed Payment 金额 < 交易金额 → 不判定 paid（`ambiguous` + reason `short_payment`）。

### FR-302：本地证据优先
判定以交易下 payment_sessions → payment 关联为主证据；PaymentWebhookEvent（processed + action captured）仅作佐证（reasons 记录），不作独立 PAID 依据（Payment 记录是 P0 的权威本地落点）。
- AC-302（FR-302）：session completed 但 payment 缺失 + provider 返回 succeeded（stub）→ `paid`（本地不一致经 provider 修复语义）。
- AC-303（FR-302）：全部 session failed/canceled/expired → `unpaid`。
- AC-304（FR-302）：transaction 无任何 session → `unpaid`。

### FR-303：Provider 只读状态契约
`PaymentMethod#fetch_payment_status(payment_session:)`：
- 入参：PaymentSession（含 external_id / amount / currency）。
- 返回规范化 Hash：`{ status: <symbol>, amount_cents: Integer, currency: String, provider_reference: String }`。
- 基类默认 `raise NotImplementedError`（与 create/complete_payment_session 同风格，见 `pallastrade_core/app/models/pallastrade/payment_method.rb`）。
- **只读**：不得创建/更新任何本地记录、不得推进任何状态机。
- AC-308（FR-303）：bogus gateway 实现 `fetch_payment_status` 返回规范化 hash（status 由 session.status 确定性映射），供 core spec 使用。

### FR-304：Stripe 实现
`pallastrade_stripe Gateway::PaymentSessions` 增 `fetch_payment_status(payment_session:)`，复用既有只读 helpers（`retrieve_checkout_session` / `retrieve_payment_intent` / `PaymentSessions::Stripe#stripe_payment_intent` 等），**不调用任何 complete/create 逻辑**：
- 状态映射：PaymentIntent `succeeded` / Checkout `payment_status == paid` → `:paid`；`canceled` / `requires_payment_method` / `unpaid` → `:unpaid`；`processing` / `requires_capture` / `requires_action` → `:ambiguous`（本契约不 resolve 3DS/捕获，交由调用方）。
- amount/currency 取自 provider 返回（cents 口径），provider_reference 取 PI id / session id。
- 网络/Stripe API 异常向上抛出（调用方 resolver 捕获 → ambiguous）。
- AC-309（FR-304）：Stripe `fetch_payment_status` 单测（stub retrieve）：pi_ succeeded → paid；cs_ paid → paid；canceled → unpaid；processing → ambiguous；异常 propagate。

### FR-305：Resolver 决策矩阵（transaction 维度）
`Transactions::PaymentFactResolver#call(transaction:, provider_query: true)`：
1. transaction nil → failure。
2. 本地扫描 sessions：任一 `session.payment`（completed 且 `amount >= transaction.amount`，同 currency）→ `paid`（short-circuit）。
3. 无 paid：若存在金额 < 交易额的 completed payment → `ambiguous`（short_payment）。
4. 全部 attempt 终态失败 或 无 session → `unpaid`。
5. 存在 pending/processing attempt（external_id present）且 `provider_query`：
   - 调 `payment_method.fetch_payment_status`（contract 缺失 NotImplementedError → 跳过 provider，转 6）。
   - `:paid` → `paid`；`:unpaid` → `unpaid`；`:ambiguous` → `ambiguous`。
   - 异常 → `ambiguous`（reason `provider_unavailable`）。
6. 无 provider 可查且仍有非终态 attempt → `ambiguous`。
- 返回 `success(value: { verdict:, reasons: [...], provider_results: [...] })`（reasons 为 Symbol 数组便于审计/测试）。
- AC-305（FR-305）：pending session + provider `processing` → `ambiguous`。
- AC-306（FR-305）：provider 抛网络异常 → `ambiguous` + reason `provider_unavailable`。
- AC-307（FR-305）：provider 返回 `canceled` → `unpaid`。
- AC-306b（FR-305）：provider_query: false 且有 pending attempt → 不外呼，`ambiguous`。

### FR-306：范围边界
- 本包**不**消费判定结果（不推进状态机、不触发 recovery/finalize）——只产出能力；TXN-P2-4 Recovery 与 TXN-P2-5 Finalize 接线。
- 无迁移；无 routes/serializers/API/SDK 变更。

## 4. 跨层搜索记录（Step 0，6 层独立搜索）

| 层 | 搜索路径 | 关键词命中结论 |
|---|---|---|
| App | `backend/app/` | 无 PaymentFactResolver / fetch_payment_status / payment-fact 相关（空） |
| Core | `pallastrade_core/app/` | PaymentMethod 基类有 create/update/complete_payment_session + webhook 契约（无状态查询契约）；`Gateway::Bogus` 有 create/complete；Payment state 集合（INVALID_STATES/completed/pending…）；PaymentSession（ps_，belongs_to payment/payment_combination/commerce_transaction）；PaymentWebhookEvent（P0-2：status received/processing/processed/failed + action captured）；CommerceTransaction.has_many :payment_sessions（P2-2）——**无既有 resolver/状态查询** |
| API | `pallastrade_api/app/` | 无 resolver/recovery 端点（仅 P2-2 transactions create/show；admin resolve_* 为 id 解析，无关） |
| Admin | `pallastrade_admin/app/` | 无相关 |
| Storefront | `storefront/src/` | 无相关（P2-3 纯后端内部） |
| Platform | `platform/packages/` | 无相关 |

## 5. 技术影响与设计要点

- **Core**：
  - `pallastrade_core/app/models/pallastrade/payment_method.rb`：增 `fetch_payment_status(payment_session:)` 文档化默认（`raise NotImplementedError`）。
  - `pallastrade_core/app/models/pallastrade/gateway/bogus.rb`：实现确定性 `fetch_payment_status`（status 映射：completed→paid 供测试；failed/canceled→unpaid；pending/processing→processing 等）。
  - 新建 `pallastrade_core/app/services/pallastrade/transactions/payment_fact_resolver.rb`（ServiceModule::Base，返回 Result；reasons Symbol）。
- **Stripe**：`pallastrade_stripe/app/models/pallastrade_stripe/gateway/payment_sessions.rb` 增 `fetch_payment_status`（只读；复用 retrieve_checkout_session / retrieve_payment_intent；不触碰 complete/create/find_or_create_payment!）。
- 消费方：暂无（P2-4/5）；State machine / Quote / Snapshot 不动。
- 反模式检查：无裸 fetch（服务内 provider SDK 调用符合 Gateway 封装）、无内联样式、无跨 store 泄漏（transaction 已 scope）、无回调副作用（resolver 纯读）。PaymentMethod 基类加方法属框架产品源码直接修改（AGENTS §1 允许，`# PALLAS-CUSTOM` 注释）。

## 6. 测试计划

- 新增 core resolver：`backend/spec/services/pallastrade/transactions/payment_fact_resolver_spec.rb`（AC-301/302/303/304/305/306/306b/307/310；bogus provider，本地证据 + stub fetch 路径）。
- 新增/扩展 core bogus contract：resolver spec 内断言 bogus `fetch_payment_status` 规范化输出（AC-308）。
- 新增 stripe：`pallastrade_stripe/spec/models/.../gateway/payment_sessions_spec.rb` 或 gateway_spec 增 `fetch_payment_status` 用例（AC-309，stub Stripe::Checkout::Session.retrieve / PaymentIntent.retrieve）。
- 回归：`p0-payment-rspec`（Payment/PaymentSession/webhook/complete 全套）注册 verifier。
- 每条 spec 头标注 `# PRD-20260904-payments-txn-p2-3 AC-xxx`。

## 7. 文档同步清单（知识同步门）

- [x] `ai/skills/pallastrade-payments/SKILL.md` changelog（Payment Fact Resolver + provider 只读状态契约）
- [x] `ai/skills/pallastrade-checkout/SKILL.md` changelog 评估：无需更新（本包无 checkout 语义变更，transactions 域已入 payments changelog）
- [x] `docs/prd/README.md` 索引 + 本 PRD 状态
- [ ] store.yaml / SDK / api-v3：N/A（无 API 面）
- [ ] RESEARCH-20260904-txn-p2-0 审计附录（P2-3 交付记录，可选）

## 8. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-04 | 0.1 | 初稿（draft） | AI |
| 2026-09-04 | 0.2 | approved（用户"实施"）；实施完成：PaymentMethod 基类契约 + Bogus 确定性实现 + Stripe 只读 fetch_payment_status（pi_/cs_ 映射）+ Transactions::PaymentFactResolver（paid/unpaid/ambiguous）+ resolver matrix 与 Stripe contract specs（18 examples 0 failures）；新增文件 rubocop 0 | AI |
