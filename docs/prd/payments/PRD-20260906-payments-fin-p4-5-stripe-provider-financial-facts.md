# FIN-P4-5：Stripe Provider Financial Facts —— fetch_financial_details + PI/Charge/BalanceTransaction/Refund 归一快照（P4 拆包第 5 包）

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-06 |
| 来源 | 用户任务：「自主决定」→ 先提交 P4-1~4（2319aed）后继续 FIN-P4-5——P4 V2 拆包第 5 包（Stripe Provider Financial Facts）；前序 FIN-P4-1~4 均 done |
| 分类 | payments |
| 关联 Skill | `ai/skills/pallastrade-payments/SKILL.md`、`ai/skills/pallastrade-events-webhooks/SKILL.md`、`ai/skills/pallastrade-testing/SKILL.md` |
| 关联 REQ | REQ-20260906-fin-p4-5.md |
| 关联 PRD | 上游：`豆包梳理业务需求/P4 — Transaction Financial Ledger & PSP Reconciliation Foundation.md`（V2；§61 FIN-P4-5 + §30-35/§40-41/§66 AC-4003/4018）；前序 FIN-P4-1~4 |
| 需求类型 | 新功能（core provider 契约 + pallastrade_stripe 只读实现 + Bogus 测试替身 + capability 翻转；**无 migration/API/UI**——快照 VO 暂不落表，持久化归 FIN-P4-6） |

> V2 顺序：FIN-P4-1 ✅ → FIN-P4-2 ✅ → FIN-P4-3 ✅ → FIN-P4-4 ✅ → **FIN-P4-5 Stripe Provider Financial Facts（本包）** → FIN-P4-6 Source Reconciliation。
> 复用：`fetch_payment_status` 只读 provider 契约模式（TXN-P2-3/P4 §30）+ `PaymentSessions::Stripe`（PI/Charge 解析）+ FIN-P4-1 FinancialFact 语义层。

---

## 1. 背景与目标

- **一句话需求原文**：实现 Stripe 只读 `fetch_financial_details`，输出 PaymentIntent / Charge / BalanceTransaction / Refund 的归一化 financial snapshot（gross/fee/net/refund/settlement/references），为 FIN-P4-6 Source Reconciliation 提供权威 provider 事实。
- **背景**：
  - P2/P3 已有**只读状态契约** `fetch_payment_status(payment_session:)`（status/amount/currency/reference；Stripe cs_/pi_ 双模式 + Bogus 确定性替身）——回答「这笔钱到底 paid 没有」。
  - 但 reconciliation 需要**财务明细**：fee/net（BalanceTransaction）、refund 汇总、charge 引用（ch_）。目前 `private_metadata.stripe_charge_id` 仅部分路径有；`Refund.transaction_id`=re_；无 BT 引用（RISK-FIN-06：Charge/BalanceTransaction 引用不完整）。
  - P4 §30/31/33：新增 `fetch_financial_details`（只读，职责 ≠ fetch_payment_status）；Stripe V1 = PaymentIntent → latest Charge → BalanceTransaction → Refunds，输出 gross/refund_total/fee/net/settlement_status/observed_at + 规范化 references（pi_/ch_/txn_/re_）。§34：ProviderFinancialSnapshot 可作为 reconciliation 内部 JSON snapshot，第一版不一定独立表。§35：fee/net 是 **Reconciliation Fact，不进 Journal**（不发明半套会计）。
- **目标**：
  - core 定义只读财务明细契约（VO 快照 + 门禁），Stripe 实现、Bogus 确定性替身（测试）；Adyen/PayPal legacy → 不实现（UNSUPPORTED 语义），StoreCredit/Check → NOT_APPLICABLE（无 PSP）。
  - **补齐 Charge 引用全路径**（PI.latest_charge → ch_；§33）与 BalanceTransaction 引用（txn_）解析能力。
  - `CaptureEvidencePolicy.provider_reconciliation_capability`：Stripe/Bogus → `PROVIDER_RECONCILIATION_SUPPORTED`；其余维持（P4-1 的 UNSUPPORTED/NOT_APPLICABLE 语义保留）。
  - 快照作为 transient `ProviderFinancialDetails` VO（含 raw evidence reference）；**不落表、不进 Journal**（P4-6 reconciliation 消费/持久化）。
  - **不改** Payment/Refund/Journal/任何 state machine；无 migration。
- **成功指标**：AC-4P5-* 全绿；新增 spec + 全量 backend-rspec 0 failures；无 migration/API/UI。

## 2. 用户故事 / 场景

| # | 场景 | 类型 | 描述 |
|---|---|---|---|
| S1 | Stripe cs_（Checkout Session） | 正常 | cs_ session → PI → latest_charge(ch_) → BT(txn_) → refunds → 归一 snapshot（gross=amount、fee/net 从 BT、refund_total） |
| S2 | Stripe pi_（PaymentIntent 模式） | 正常 | pi_ 直存 session → 同上（无 Checkout Session 层） |
| S3 | 未捕获 / 未成功 | 边界 | PI 非 succeeded（requires_capture/processing…）→ settlement_status 如实（无 charge/BT → fee/net nil，不猜） |
| S4 | 有退款 | 边界 | charge 有 N refunds → refund_total = Σ（金额归一） |
| S5 | Bogus 替身 | 正常 | Bogus session → 确定性 snapshot（本地状态派生，测试用） |
| S6 | 非 PSP | 正常 | StoreCredit/Check → NOT_APPLICABLE（无 PSP 查询） |
| S7 | Legacy PSP | 异常 | Adyen/PayPal → 不实现 fetch_financial_details → UNSUPPORTED（不误报 MISMATCH，§41） |
| S8 | Provider 网络失败 | 异常 | Stripe 异常 → raise（GatewayError/StripeError）→ 调用方（P4-6）决定，无本地副作用 |
| S9 | 只读边界 | 异常 | 查询零写库、零 state 变更、零 Payment 创建/transition |

## 3. 功能需求（FR）

- FR-4P5-01：core `PaymentMethod#fetch_financial_details(payment_session:)` 基础契约（镜像 fetch_payment_status）：默认 `raise NotImplementedError`；只读；返回归一 Hash；gateway 未实现 → 由 capability 门禁在消费侧表达 UNSUPPORTED（不裸调）。
- FR-4P5-02：core 新增 `PallasTrade::FinancialFacts::ProviderFinancialDetails`（transient 只读 VO，构造后 freeze）：字段 `provider / provider_payment_reference / provider_charge_reference / provider_balance_transaction_reference / provider_refund_references[] / gross_amount / gross_currency / refund_total / refund_currency / fee_amount / fee_currency / net_amount / net_currency / settlement_status / observed_at / raw_reference`（P4 §31 字段对齐；`from_hash` 白名单规范化构造，未知键拒绝）。fee/net/refund 可空（未捕获/无 BT 不猜）。
- FR-4P5-03：core `Gateway::Bogus#fetch_financial_details(payment_session:)` 确定性替身：completed → gross=session amount、fee=0、net=gross、settlement_status=:settled、refs 用 session.external_id + 派生 ch_/txn_（bogus 确定性，供 P4-6 spec）；pending/processing 等 → settlement_status=:pending、fee/net nil（不猜）。
- FR-4P5-04：`PallasTradeStripe::Gateway#fetch_financial_details(payment_session:)` 只读实现（cs_/pi_ 双模式，复用 PaymentSessions::Stripe 解析）：
  - PI 非 succeeded → settlement_status 如实（:requires_capture/:processing/:requires_action/:unpaid/:canceled），无 charge/BT → gross=PI.amount、fee/net nil。
  - PI succeeded → 解析 `latest_charge`（支持 string id 或已展开对象）→ `retrieve_charge` → charge 关联 BT（charge.balance_transaction id 或展开）→ `retrieve_balance_transaction` → 归一：gross=PI/charge amount、fee/net 从 BT（amount- net vs fee）、refund_total = Σ charge.refunds（或 PI charges refunds）金额。
  - references 规范化：provider_payment_reference=pi_（cs_ 模式经 session→PI）、charge_reference=ch_、balance_transaction_reference=txn_、refund_references=re_[]（Stripe Refund id）。零写库/零 state 变更（§31/§33/§38/AC-4003）。
- FR-4P5-05：`PallasTradeStripe::Gateway` 新增只读 retrieval：`retrieve_balance_transaction(id)`（expand 或独立 retrieve）；charge 检索支持从 PI.latest_charge（string/object）取 id。复用 `send_request`/`api_options` 错误封装；**不改** capture/refund/complete 等既有写路径。
- FR-4P5-06：`CaptureEvidencePolicy.provider_reconciliation_capability`：Stripe（type=Gateway type 或 respond_to fetch_financial_details 判定）与 Bogus → `PROVIDER_RECONCILIATION_SUPPORTED`；Adyen/PayPal/未知真实 PSP → 维持 UNSUPPORTED；StoreCredit/Check → NOT_APPLICABLE。**capability 与实现存在性一致**（消费侧据此路由，禁止仅靠 rescue NotImplementedError 表达）。
- FR-4P5-07：范围外——不做 reconciliation verdict（P4-6）；fee/net 不进 Journal（P4 §35；RESERVED PSP_FEE/PSP_NET_SETTLEMENT 不变）；不做 ProviderFinancialSnapshot 落表/持久化（§34：第一版 reconciliation JSON snapshot，P4-6 消费时决定）；无 API/UI；无 migration。

## 4. 非功能需求（NFR）

- 只读：provider 网络调用零本地写、零 state 迁移、零 Payment/Refund 创建（P4 §30/§66 AC-2288 只读精神）。
- 失败语义：provider/网络异常 raise（`Stripe::StripeError`/`GatewayError`），不 rescue 吞掉——由 P4-6 消费层决定（与 fetch_payment_status 一致）。
- 确定性：Bogus 替身纯本地派生（spec/P4-6 确定性）。
- 性能：单 session 2-4 次 Stripe 调用（PI + charge + BT，refunds 内嵌 charge）；无 N+1；无缓存要求（reconciliation 频率低）。
- 兼容：无 schema/API 变更；P0-P4-4 行为不变；fetch_payment_status 路径零改动（回归强证）。

## 5. 验收标准（AC，与测试一一映射）

> 对齐 P4 §31/§32/§33/§34/§40/§41/§66 + FIN-INV-09/10。

- AC-4P5-01 ← FR-4P5-04 / P4 §31：Stripe cs_ 模式 succeeded → 归一 snapshot 全字段（pi_/ch_/txn_ refs + gross + fee/net + refund_total + settlement_status=:settled + observed_at）。
- AC-4P5-02 ← FR-4P5-04 / S2：Stripe pi_（PaymentIntent 直存）模式 → 同上（无 Checkout Session 层）。
- AC-4P5-03 ← FR-4P5-04 / P4 §33：Charge 引用全路径补齐——PI.latest_charge 解析出 ch_（string id 与已展开对象两种形态）。
- AC-4P5-04 ← FR-4P5-04 / S3：PI 非 succeeded（requires_capture/processing/canceled…）→ settlement_status 如实、fee/net nil（不猜，无部分数据）。
- AC-4P5-05 ← FR-4P5-04 / S4：有退款 → refund_total = Σ charge refunds（金额/币种归一）。
- AC-4P5-06 ← FR-4P5-03 / S5：Bogus 确定性 snapshot（completed → settled/gross/fee0/net；pending → pending/nil fee）。
- AC-4P5-07 ← FR-4P5-02：`ProviderFinancialDetails` VO 白名单构造 + freeze + from_hash 拒绝未知键；字段与 P4 §31 对齐。
- AC-4P5-08 ← FR-4P5-06 / P4 §40/§41：capability——Stripe/Bogus → SUPPORTED；Adyen/PayPal → UNSUPPORTED；StoreCredit/Check → NOT_APPLICABLE（不误报）。
- AC-4P5-09 ← FR-4P5-04 / S8/S9：只读边界——查询零写库、零 Payment/Refund/session state 变更；provider 失败 raise（无本地副作用）。
- AC-4P5-10 ← FR-4P5-07 / P4 §35：fee/net 不进 Journal（无 PSP_FEE/PSP_NET_SETTLEMENT entry；RESERVED 不变）；无 migration/API。
- AC-4P5-11 ← FR-4P5-01/07：回归零破坏——transactions（PaymentFactResolver/Recover/Finalize）+ financial_facts/financial_ledger + payments specs + P4-1~4 全绿。

## 6. 跨层搜索记录（6 层，gate 强制）

关键词：`fetch_financial_details / ProviderFinancialDetails / balance_transaction / latest_charge / provider_financial_snapshot / provider_reconciliation_capability`。

| 层 | 路径 | 关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | financial_details/snapshot | 无 | 否 |
| Core models/services | `pallastrade_core/app/` | fetch_financial_details / ProviderFinancialDetails / balance_transaction | 无实现；`PaymentMethod#fetch_payment_status`（只读状态契约 base，default raise NotImplementedError）；`Gateway::Bogus#fetch_payment_status`（确定性替身）；`CaptureEvidencePolicy.provider_reconciliation_capability`（当前真实 PSP 全 UNSUPPORTED——P4-1 注释「P4-5 才做」）；`Transactions::PaymentFactResolver#fetch_provider_status`（fetch_payment_status 消费者） | 部分：只读状态契约模式/消费点就绪；缺财务明细契约/VO/capability 翻转 |
| Stripe gem | `pallastrade_stripe/app/` | latest_charge / balance_transaction / retrieve_charge | `PallasTradeStripe::Gateway#fetch_payment_status`（只读状态）；`PaymentSessions::Stripe#stripe_payment_intent/stripe_charge`（PI→latest_charge→retrieve_charge 已有）；`Gateway#retrieve_charge`；**无 balance_transaction retrieval**、无 fetch_financial_details | 部分：Charge 解析能力半就绪；缺 BT/财务明细 |
| Core DB | schema/migrate | provider snapshot 表 | 无（无快照表） | 本包无 migration（VO 不落表） |
| API/Admin/Storefront/Platform | 各层 | financial_details/snapshot | 无 | 否（无 API/UI） |

**结论**：`fetch_payment_status` 只读 provider 契约与消费模式（P2/P3）是 FIN-P4-5 的模板；Stripe Charge 解析（PI.latest_charge→retrieve_charge）已存在。缺口 = `fetch_financial_details` 契约 + `ProviderFinancialDetails` VO + Stripe 实现（含 BT retrieval/refunds 汇总）+ Bogus 替身 + capability 翻转。无重复能力、无 migration。

## 7. 技术影响

- **修改（core gem）**：
  - `app/models/pallastrade/payment_method.rb`：+`fetch_financial_details` base 契约（default raise NotImplementedError，doc 注释 §30/§31）。
  - `app/models/pallastrade/gateway/bogus.rb`：+确定性 `fetch_financial_details`。
  - `app/services/pallastrade/financial_facts/capture_evidence_policy.rb`：capability 翻转（Stripe/Bogus → SUPPORTED，判定基于 provider type/respond_to；Adyen/PayPal 保持 UNSUPPORTED）。
- **修改（pallastrade_stripe gem）**：
  - `app/models/pallastrade_stripe/gateway.rb`：+`retrieve_balance_transaction(id)`；charge 从 PI.latest_charge 取 id 的 helper（string/object 双形态）。
  - `app/models/pallastrade_stripe/gateway/payment_sessions.rb`（或新 module）：+`fetch_financial_details(payment_session:)` 只读归一实现（cs_/pi_ 双模式）。
- **新建（core gem）**：
  - `app/services/pallastrade/financial_facts/provider_financial_details.rb`（transient 只读 VO：ATTRIBUTES + from_hash 白名单 + freeze + 可空 fee/net/refund 语义）。
- **不修改**：Payment/Refund/PaymentSession state machine、Journal（Post/Reverse/PostPayment/PostRefund/PostAllocation）、Transactions::{PaymentFactResolver,Recover,Finalize}、fetch_payment_status 路径；无 migration/schema；无 API/UI/storefront/platform。
- **关键设计决策（实施冻结）**：
  - snapshot 落点：transient VO（不落表）——P4 §34「不一定第一版独立表」；P4-6 reconciliation 决定持久化形态。
  - fee/net 语义：Reconciliation Fact（§35）——不进 Journal；PSP_FEE/PSP_NET_SETTLEMENT RESERVED 不变。
  - settlement_status 枚举：`:settled | :pending | :requires_capture | :processing | :requires_action | :unpaid | :canceled | :failed | :expired`（与 fetch_payment_status 归一枚举对齐，:settled 新增表示 fee/net 可算）。
  - Stripe 金额单位：Stripe 返回 cents → VO 以 decimal（元）归一（divide 100），币种随附（§31 gross_amount 金额语义冻结于本包）。

## 8. 测试计划

- 新增（backend/spec，跨 core + stripe gem spec）：
  - `spec/services/pallastrade/financial_facts/provider_financial_details_spec.rb`（core）—— AC-4P5-07
  - `spec/models/pallastrade/gateway/bogus_spec.rb`（或扩展）—— AC-4P5-06
  - `spec/services/pallastrade/financial_facts/capture_evidence_policy_spec.rb`（更新 capability 断言）—— AC-4P5-08
  - `backend/pallastrade_gems/pallastrade_stripe/spec/.../fetch_financial_details_spec.rb`（stub Stripe 对象：Struct/instance_double 模式同既有 stripe_spec）—— AC-4P5-01/02/03/04/05/09
- 真实路径：Stripe spec 用 stub `Stripe::PaymentIntent/Charge/BalanceTransaction/Refund`（既有 gateway_spec/stripe_spec Struct 模式），断言归一输出与只读（不发 create/update/confirm 调用）。
- 回归：transactions（PaymentFactResolver/Recover/Finalize/OnPaymentSuccess）+ financial_facts + financial_ledger + payments + P4-1~4 specs → 0 failures；全量 backend-rspec（coverage-gate 依据）。
- AC 映射：AC-4P5-01~11 → 上述 spec + 回归（spec 内 `AC-4P5-xx` 标注）。

## 9. 文档同步清单（知识同步门）

- [ ] `ai/skills/pallastrade-payments/SKILL.md`：补 Stripe Provider Financial Facts 章节（fetch_financial_details 契约 + ProviderFinancialDetails VO + capability 语义 + fee/net=reconciliation fact）。
- [ ] `ai/skills/pallastrade-events-webhooks/SKILL.md`：评估（provider 只读契约非事件，预计 no-change）。
- [ ] `harness/scenarios/scenarios.json`：新增 GS-054（provider financial details 场景）。
- [ ] 本 PRD 状态 + `docs/prd/README.md` 索引。
- [ ] API/schema：不涉及。

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-06 | 0.1 | 初稿：FIN-P4-5 Stripe Provider Financial Facts 拆包 PRD（P4 §30-35/§40-41/§61 + fetch_payment_status 契约复用 + PaymentSessions::Stripe Charge 解析基础；fetch_financial_details 契约 + ProviderFinancialDetails VO + Stripe 实现（BT retrieval/refunds）+ Bogus 替身 + capability 翻转；无 migration，快照 VO 不落表归 P4-6） | AI |
| 2026-09-06 | 0.2 | approved（用户「自主决定」授权实施）→ 实施完成：`ProviderFinancialDetails` VO + `PaymentMethod#fetch_financial_details` base 契约 + Stripe cs_/pi_ 双模式实现（PI→charge→BT→refunds 归一，+retrieve_balance_transaction）+ Bogus 确定性替身 + capability 翻转（method-owner 判定）；新增 29 examples 0 failures；回归 core 206 + stripe gem 56（顺手修复既有 stripe_spec.rb:113 broken 断言 test-only）全绿 | AI |
