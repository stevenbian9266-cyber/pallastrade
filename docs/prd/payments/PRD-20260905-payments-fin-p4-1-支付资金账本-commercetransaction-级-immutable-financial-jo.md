# FIN-P4-1：支付资金事实解析 —— Payment / Capture / Refund Financial Fact Resolution（P4 拆包第 1 包）

| 元数据      | 值                                                                                                                                                                              |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 状态       | done                                                                                                                                                                       |
| 创建日期     | 2026-09-06                                                                                                                                                                     |
| 来源       | 用户任务：「结合 P0-P3 实际实现与 FIN-P4-0 审计，实施 P4 — Transaction Financial Journal & PSP Reconciliation Foundation V2；严格按 PRD 拆包推进」；本 PRD = FIN-P4-1（Financial Fact Resolution）            |
| 分类       | payments（资金事实解析属于 Payment/CommerceTransaction 交界，但核心 authority 来源为支付域）                                                                                                         |
| 关联 Skill | `ai/skills/pallastrade-payments/SKILL.md`、`ai/skills/pallastrade-data-model/SKILL.md`、`ai/skills/pallastrade-testing/SKILL.md`                                                 |
| 关联 REQ   | REQ-20260906-fin-p4-1.md（实施时回填）                                                                                                                                                |
| 关联 PRD   | 上游需求：`P4 — Transaction Financial Journal & PSP Reconciliation Foundation V2`；上游审计：FIN-P4-0 Money Flow Semantic Audit；原 `FIN-P4-1 Immutable Financial Journal` PRD 顺延为 FIN-P4-2 |
| 需求类型     | 新功能（资金事实语义标准化，不新增资金副作用）                                                                                                                                                        |

> 本 PRD 是新版 P4 拆包后的第一个实施包。
>
> 原计划中 FIN-P4-1 直接建立 Financial Journal，但 FIN-P4-0 审计确认：`Payment.completed` 在不同支付路径下并不具有统一“现金已捕获”语义，因此必须先建立 **Financial Fact Resolution**。
>
> 后续顺序调整为：
>
> `FIN-P4-1 Financial Fact Resolution → FIN-P4-2 Immutable Financial Journal → FIN-P4-3 Payment/Refund Posting → FIN-P4-4 Allocation Integrity → FIN-P4-5~8 PSP Reconciliation / Operations`。
>
> 本包**无 migration、无 Journal 表、无 API/UI 变化、无 Payment/Refund 副作用改造**。

---

## 1. 背景与目标

* **一句话需求原文**：在建立 Financial Journal 前，先统一 Payment / Capture / Refund 的真实金融事实语义，避免把 Payment 状态直接错误解释为现金流。
* **背景**：

  * P0-P3 已落地：PaymentSession/Payment、Order-centric Checkout、CommerceTransaction/Recovery、Inventory Reservation/Finalize 均已有真实代码基础。
  * FIN-P4-0 审计确认当前资金事实不是一个统一概念：

    1. Stripe auto-capture：Payment `completed` 通常等价于 captured。
    2. Stripe manual-capture：授权后 Payment 可保持 `pending`，Order/Transaction 业务流程仍可能继续；只有后续 capture 才是真正现金捕获。
    3. PaymentCombination：组合 Settlement 会创建/完成组合 Payment，并通过 PaymentSplit 向多个 Order 分配 captured amount。
    4. StoreCredit / Check / offline payment 不属于 PSP cash capture，但仍然是有效价值收款事实。
    5. 一个 CommerceTransaction 设计上可拥有多个 PaymentSession attempt，且 short-payment/retry 使多个 successful financial payment facts 成为真实可达情况，不能按 1 Transaction = 1 captured Payment 建模。
    6. `PaymentSplit` 同时承担 allocation source 与 Order payment_total 聚合来源，但不能作为第二笔 cash movement。
    7. Refund 支持 partial/multiple refund，但本身无完整状态机；其 CommerceTransaction 归属需要经 Payment/Combination 推导。
    8. Stripe PaymentIntent/refund reference 已有一定持久化，但 Charge reference 不完整；BalanceTransaction、fee、net 尚未形成结构化 financial contract。
  * 因此直接在 Payment `completed` 时写 `PAYMENT_CAPTURED` Ledger，会把 authorization、cash capture、store credit、offline value 等不同事实混为一谈。
* **目标**：

  * 建立统一 `FinancialFactResolver`；
  * 建立 `FinancialInstrumentClassifier`；
  * 冻结每种支付路径的 Capture Evidence Policy；
  * 标准化 Payment/Refund 产生的金融事实类型；
  * 明确 CommerceTransaction ownership 的可靠推导规则；
  * 原生支持一个 CommerceTransaction 下多个 successful payment facts；
  * 对无法证明的金融事实输出 `AMBIGUOUS`，不猜测；
  * 为 FIN-P4-2 Journal 提供唯一合法的 posting input contract。
* **成功指标**：

  * 本包 AC-4P1-* 全绿；
  * Stripe auto/manual capture 语义测试明确分离；
  * StoreCredit/Check 不被解析为 PSP cash；
  * Combination Payment 不重复计算 cash；
  * Short Payment / N successful payment facts 可确定性表达；
  * Refund ownership 能可靠解析或明确 unresolved；
  * Resolver 全程只读，不创建 Payment/Refund、不中断 P0-P3 transaction flow；
  * P0/P1/P2/P3 baseline 零回归。

---

## 2. 用户故事 / 场景

* 作为 **支付工程师**，我希望系统明确区分 authorization、capture、store credit、offline payment，以免未来 Financial Journal 记错账。
* 作为 **财务/运营**，我希望看到的是“已确认资金事实”，而不是直接依赖 Payment.state 推断现金是否到账。
* 作为 **Recovery/Reconciliation 系统**，我希望无法证明的资金状态明确返回 AMBIGUOUS，而不是猜 PAID/CAPTURED。
* 作为 **后续 FIN-P4-2 Journal**，我希望所有 posting 输入都来自标准 FinancialFact，而不是 Payment/Refund 各自分散判断。

场景：

| #   | 场景                         | 类型 | 描述                                                                                                       |
| --- | -------------------------- | -- | -------------------------------------------------------------------------------------------------------- |
| S1  | Stripe auto capture        | 正常 | Payment/PaymentCaptureEvent 足以证明 capture → `CASH_CAPTURED`                                               |
| S2  | Stripe manual authorize    | 边界 | PI requires_capture / Payment pending → `AUTHORIZED_ONLY`，不得输出 CASH_CAPTURED                             |
| S3  | Stripe manual capture      | 正常 | capture 成功证据成立 → `CASH_CAPTURED`                                                                         |
| S4  | Store Credit               | 正常 | Payment success → `STORE_CREDIT_APPLIED`，provider reconciliation = NOT_APPLICABLE                        |
| S5  | Check / Offline            | 正常 | 已确认人工/线下支付 → `OFFLINE_PAYMENT_RECORDED`                                                                  |
| S6  | Combination Payment        | 正常 | 1 Payment 对 N PaymentSplit；Resolver 只生成 1 个 cash fact，split 是 allocation                                 |
| S7  | Short payment              | 边界 | Transaction 100，captured Payment 40 → confirmed cash fact 40；Transaction financial summary 后续显示 short 60 |
| S8  | Multiple captured payments | 边界 | 同 Transaction 捕获 40 + 60 → 两个独立 confirmed financial facts                                                |
| S9  | Refund success             | 正常 | Refund 成功并具有可证明 provider/local evidence → `REFUND_SUCCEEDED`                                             |
| S10 | Refund ownership ambiguous | 异常 | 无法可靠定位 CommerceTransaction → fact 可存在，但 ownership unresolved，不猜 transaction                              |
| S11 | Legacy provider            | 边界 | capture predicate 未冻结/证据不足 → `AMBIGUOUS` 或 provider capability UNSUPPORTED                               |
| S12 | Evidence conflict          | 异常 | local state 与 capture evidence 冲突 → `AMBIGUOUS`                                                          |
| S13 | Retry payment safety       | 异常 | 存在 provider reference 但本地判 UNPAID → 新支付前必须经过 provider authoritative verification policy                  |

---

## 3. 功能需求（FR）

### Financial Fact 核心

* FR-4P1-01：新增只读 `PallasTrade::FinancialFact` Value Object / Result Object，不落 DB。字段至少包含：

  * `fact_type`
  * `status`
  * `amount`
  * `currency`
  * `instrument_class`
  * `commerce_transaction_id`
  * `order_id`
  * `payment_id`
  * `refund_id`
  * `payment_session_id`
  * `payment_combination_id`
  * `provider`
  * `provider_payment_reference`
  * `provider_refund_reference`
  * `effective_at`
  * `evidence`
  * `reason_code`
* FR-4P1-02：`status` 最小集合：

  * `CONFIRMED`
  * `AUTHORIZED_ONLY`
  * `UNPAID`
  * `AMBIGUOUS`
  * `NOT_APPLICABLE`
  * `UNSUPPORTED`
* FR-4P1-03：`fact_type` 最小集合：

  * `CASH_CAPTURED`
  * `STORE_CREDIT_APPLIED`
  * `OFFLINE_PAYMENT_RECORDED`
  * `REFUND_SUCCEEDED`
  * `NONE`
* FR-4P1-04：本包不把 `ORDER_ALLOCATION` 作为 Payment FinancialFact；allocation 属于 FIN-P4-4，由 PaymentSplit 单独解析，避免把 allocation 当 cash movement。

### Financial Instrument Classification

* FR-4P1-05：新增 `FinancialInstrumentClassifier`，根据 PaymentMethod/Gateway/Payment 数据返回标准分类：

  * `PSP_CASH`
  * `STORE_CREDIT`
  * `OFFLINE`
  * `UNKNOWN`
* FR-4P1-06：Stripe/Bogus 等 PSP gateway 映射 `PSP_CASH`；StoreCredit 映射 `STORE_CREDIT`；Check/线下付款映射 `OFFLINE`。
* FR-4P1-07：未知或 legacy PaymentMethod 不允许默认归类 PSP_CASH；应返回 UNKNOWN，由 Resolver 决定 AMBIGUOUS/UNSUPPORTED。

### Capture Evidence Policy

* FR-4P1-08：新增 `CaptureEvidencePolicy` 或等价内部 policy/service；禁止直接使用：

  ```ruby
  payment.completed?
  ```

  作为所有 provider 的统一 CASH_CAPTURED 判定。
* FR-4P1-09：Stripe auto-capture 的 confirmed capture 至少需要符合冻结后的可靠本地 evidence；优先组合：

  * Payment 已进入 captured 对应状态；
  * `PaymentCaptureEvent` 或等价 capture evidence 存在；
  * provider reference 可识别。
* FR-4P1-10：Stripe manual-capture：

  * authorization / `requires_capture` → `AUTHORIZED_ONLY`
  * 不得生成 CASH_CAPTURED；
  * 真正 `capture!` 成功并形成 capture evidence 后才 → `CASH_CAPTURED`。
* FR-4P1-11：PaymentCombination：

  * 组合 Settlement 完成并形成唯一有效 Payment 时，可解析为一笔 CASH_CAPTURED；
  * PaymentSplit 不生成额外 cash facts；
  * split captured total 与 Payment amount 的 invariant 在 FIN-P4-4 建立。
* FR-4P1-12：StoreCredit/Check 不要求 PaymentCaptureEvent，不调用 PSP，按各自 domain success evidence 返回非 PSP fact。
* FR-4P1-13：Adyen/PayPal legacy：

  * 只有当当前 adapter/domain 已有明确、可证明 captured predicate 时才允许 CONFIRMED；
  * 否则返回 AMBIGUOUS/UNSUPPORTED；
  * 本包不新增其 financial provider query contract。
* FR-4P1-14：任何本地 evidence 互相冲突时返回 AMBIGUOUS，不选择“最方便”的状态。

### Payment Financial Fact Resolver

* FR-4P1-15：新增：

  ```text
  PallasTrade::FinancialFacts::ResolvePayment
  ```

  或项目 convention 下等价服务。
* FR-4P1-16：输入 `Payment`，可选显式 `CommerceTransaction` context；Resolver 不修改任何模型。
* FR-4P1-17：解析顺序：

  1. Classify instrument；
  2. Resolve CommerceTransaction ownership；
  3. Resolve amount/currency；
  4. Evaluate capture evidence；
  5. Produce FinancialFact。
* FR-4P1-18：Payment currency 当前无独立列，解析必须使用可靠关联来源（PaymentSession / CommerceTransaction / PaymentCombination / Order）；来源冲突 → AMBIGUOUS。
* FR-4P1-19：PSP_CASH payment 的 `CASH_CAPTURED` 金额使用已确认 captured fact，不得直接用 CommerceTransaction commercial amount 替代。
* FR-4P1-20：支持同一 CommerceTransaction 解析出 N 个 confirmed payment facts；禁止 resolver/service 层做“只取第一个 successful Payment”的假设。
* FR-4P1-21：short payment 合法表达：

  ```text
  commercial amount = 100
  confirmed captured fact = 40
  ```

  Resolver 本身不把它判断为 Ledger error；Transaction-level short/over reconciliation 留后续 FIN-P4-7。

### CommerceTransaction Ownership

* FR-4P1-22：Payment ownership 按可靠性顺序解析：

  1. `Payment → PaymentSession → CommerceTransaction`
  2. `Payment → PaymentCombination → CommerceTransaction`
  3. 显式 transaction context
  4. 无可靠路径 → `commerce_transaction_id = nil`
* FR-4P1-23：禁止根据：

  * `Payment#transaction_id`
  * `response_code`
  * `pi_`
  * `cs_`
    等 PSP reference 推断 CommerceTransaction。
* FR-4P1-24：新代码统一使用 `commerce_transaction_id` 指代 `txn_` 领域对象。
* FR-4P1-25：manual/offline/legacy Payment 无 CommerceTransaction 时允许生成 ownership unresolved 的 FinancialFact；后续 Journal 是否允许 posting 由 FIN-P4-2 policy 决定。

### Refund Financial Fact Resolver

* FR-4P1-26：新增：

  ```text
  PallasTrade::FinancialFacts::ResolveRefund
  ```

* FR-4P1-27：Refund success 的事实必须基于当前 `Refund#perform!` 成功结果及持久化 provider refund reference / local evidence；失败执行不得产生 `REFUND_SUCCEEDED`。

* FR-4P1-28：Refund amount 为独立事实；multiple/partial Refund 每个 Refund 分别解析，不聚合成一行。

* FR-4P1-29：Refund ownership 优先：

  1. Refund → Payment → PaymentSession → CommerceTransaction
  2. Refund → Payment → PaymentCombination → CommerceTransaction
  3. 可可靠推导的 Order
  4. 无法证明 → transaction nil

* FR-4P1-30：组合退款的 Order target 允许使用现有 reimbursement/PaymentSplit 关系作为 evidence，但不得据此复制一笔 Refund 到多个 Order。

* FR-4P1-31：Refund provider reference 字段当前叫 `transaction_id`，FinancialFact 输出必须标准化为 `provider_refund_reference`。

### Provider Capability

* FR-4P1-32：本包定义 provider capability projection：

  * `LOCAL_CAPTURE_RESOLUTION_SUPPORTED`
  * `PROVIDER_RECONCILIATION_SUPPORTED`
  * `PROVIDER_RECONCILIATION_UNSUPPORTED`
* FR-4P1-33：Stripe local fact resolution = supported；完整 financial reconciliation 仍由 FIN-P4-5 实现。
* FR-4P1-34：StoreCredit / Offline = provider reconciliation NOT_APPLICABLE。
* FR-4P1-35：Adyen / PayPal 第一版不得假装具备 FIN-P4-5 financial reconciliation。

### Retry Payment Safety Policy

* FR-4P1-36：产出并固化 `RETRY_PAYMENT_FINANCIAL_SAFETY_POLICY`：

  * 如果旧 PaymentSession/provider reference 仍存在可权威确认空间，新 PaymentSession/charge 前不得仅凭“本地未完成”直接判定安全重试。
* FR-4P1-37：本包主要输出 policy + resolver capability，不重写 P2 Recovery；

  * 若现有 P2 已具备等价 authoritative provider verification，则建立 regression test；
  * 若确认存在真实 double-charge 窗口，记录为 release blocker 并单独最小修复，不借本包扩大 Transaction 状态机。

### Side-effect Boundary

* FR-4P1-38：FinancialFactResolver 必须严格只读：

  * 不创建 PaymentSession；
  * 不创建 Payment；
  * 不 capture；
  * 不 refund；
  * 不更新 Payment；
  * 不更新 Refund；
  * 不修改 CommerceTransaction。
* FR-4P1-39：本包不创建 `financial_journal_entries` 表，不提供 `FinancialJournal::Post`。
* FR-4P1-40：FIN-P4-2 及以后只能消费本包 FinancialFact contract，禁止重新在各 posting service 中复制 `payment.completed?` / provider-specific capture 判定。

---

## 4. 非功能需求（NFR）

* **确定性**：

  * 相同 DB facts 输入必须返回相同 FinancialFact；
  * 不得依赖 wall-clock 随机改变 capture 结论。
* **只读性**：

  * Resolver 只读 DB；
  * 本包默认不发 provider financial API 请求；
  * 证据不足直接 AMBIGUOUS。
* **性能**：

  * Payment → Session / Combination / CaptureEvent / Order 关系允许 preload；
  * 禁止按 Transaction payments 逐条制造 N+1；
  * 单 Transaction 多 Payment facts 可批量 resolve。
* **金额精度**：

  * 沿用当前 Money/decimal major-unit convention；
  * 不在 P4-1 做 decimal→minor-unit schema 迁移；
  * 不用 Float 比较金额。
* **币种**：

  * FinancialFact currency 必须显式；
  * 来源冲突不得静默选取；
  * 沿用 P2 单 Transaction settlement currency invariant。
* **Provider 隔离**：

  * Stripe-specific 判断留在 provider policy/adapter；
  * Core resolver 不直接引用 Stripe SDK class。
* **兼容**：

  * legacy Payment / transaction ownership nil 可解析；
  * 不要求历史 backfill；
  * 不修改现有 Payment state machine。
* **可维护性**：

  * instrument classification、capture policy、ownership resolution 分离；
  * 不把所有判断堆进一个超大 Resolver。
* **安全**：

  * Resolver 失败或 AMBIGUOUS 不得产生任何资金副作用。
* **Scope Lock**：

  * 无 migration；
  * 无 Ledger；
  * 无 fee/net；
  * 无 BalanceTransaction；
  * 无 Admin UI；
  * 无 Refund workflow 重写；
  * 无 Payment Router；
  * 无 ProviderRegistry；
  * 无完整 PSP reconciliation。

---

## 5. 验收标准（AC，与测试一一映射）

> 本包落实新版 P4 的 FIN-INV-01/02/03/04/07/08/09/12 等资金事实基础不变量。

* AC-4P1-01 ← FR-4P1-01~04：FinancialFact 能表达 fact_type/status/amount/currency/instrument/ownership/evidence。
* AC-4P1-02 ← FR-4P1-05~07：Stripe/StoreCredit/Offline/Unknown instrument 分类正确。
* AC-4P1-03 ← FR-4P1-08：代码不得以裸 `payment.completed?` 作为统一 CASH_CAPTURED 判定。
* AC-4P1-04 ← FR-4P1-09：Stripe auto-capture 的可靠完成事实解析为 CONFIRMED+CASH_CAPTURED。
* AC-4P1-05 ← FR-4P1-10：Stripe manual authorization 解析为 AUTHORIZED_ONLY，不产生 CASH_CAPTURED。
* AC-4P1-06 ← FR-4P1-10：Stripe manual capture 成功后解析为 CONFIRMED+CASH_CAPTURED。
* AC-4P1-07 ← FR-4P1-11：Combination 一次成功收款只产生一个 cash fact；N PaymentSplit 不产生 N cash facts。
* AC-4P1-08 ← FR-4P1-12：StoreCredit 返回 STORE_CREDIT_APPLIED，而不是 CASH_CAPTURED。
* AC-4P1-09 ← FR-4P1-12：Check/offline 返回 OFFLINE_PAYMENT_RECORDED。
* AC-4P1-10 ← FR-4P1-13/14：Legacy/冲突 evidence 无法证明时返回 AMBIGUOUS/UNSUPPORTED，不猜。
* AC-4P1-11 ← FR-4P1-18：Payment amount/currency 来源存在冲突时返回 AMBIGUOUS。
* AC-4P1-12 ← FR-4P1-20：一个 CommerceTransaction 可以解析 N 个 confirmed payment facts。
* AC-4P1-13 ← FR-4P1-21：Transaction 100 / Payment captured 40 被表达为 confirmed 40，不被 Resolver 错判 invalid。
* AC-4P1-14 ← FR-4P1-22：PaymentSession→CommerceTransaction ownership 正确解析。
* AC-4P1-15 ← FR-4P1-22：PaymentCombination→CommerceTransaction ownership 正确解析。
* AC-4P1-16 ← FR-4P1-23/24：PSP `transaction_id/response_code` 不得用于推断 CommerceTransaction。
* AC-4P1-17 ← FR-4P1-25：无法可靠归属 Transaction 的 legacy Payment 不伪造 transaction ownership。
* AC-4P1-18 ← FR-4P1-26~31：成功 Refund 解析为独立 REFUND_SUCCEEDED fact，amount/reference/ownership 正确。
* AC-4P1-19 ← FR-4P1-28：Multiple partial refunds 分别返回独立 facts。
* AC-4P1-20 ← FR-4P1-30：组合退款不会因为关联多个 participant 而重复产生退款金额事实。
* AC-4P1-21 ← FR-4P1-32~35：StoreCredit/offline provider reconciliation 为 NOT_APPLICABLE；unsupported legacy provider 不误报 provider mismatch。
* AC-4P1-22 ← FR-4P1-36/37：retry-payment policy 明确“存在可权威确认 provider reference 时，新 charge 前必须先验证旧资金事实”。
* AC-4P1-23 ← FR-4P1-38：ResolvePayment/ResolveRefund 不产生 DB 写入和 PSP 副作用。
* AC-4P1-24 ← FR-4P1-39：本包 schema 无 `financial_journal_entries`；无 FinancialJournal posting 实现。
* AC-4P1-25 ← FR-4P1-40：后续 Journal contract 文档明确只能接收标准 FinancialFact。
* AC-4P1-26：P0 Payment baseline 全绿。
* AC-4P1-27：P1 Checkout baseline 全绿。
* AC-4P1-28：P2 CommerceTransaction/Recovery baseline 全绿。
* AC-4P1-29：P3 Inventory baseline 全绿。

**核心 Invariants：**

* FIN-INV-01：Commercial Fact ≠ Payment Execution Fact ≠ Financial Journal Fact ≠ Provider Settlement Fact。
* FIN-INV-02：`Payment.completed` 不能跨所有 PaymentMethod 等价于 PSP CASH_CAPTURED。
* FIN-INV-03：Authorization ≠ Capture。
* FIN-INV-04：一个 CommerceTransaction 可对应 N 个 Financial Payment Facts。
* FIN-INV-05：PaymentSplit 是 allocation source，不是额外 cash inflow。
* FIN-INV-06：StoreCredit/Offline Payment 不能伪装 PSP Cash。
* FIN-INV-07：FinancialFactResolver 必须先于 Financial Journal Posting。
* FIN-INV-08：FinancialFact 解析失败不得创建新的 Payment。
* FIN-INV-09：AMBIGUOUS 不猜。
* FIN-INV-10：Refund 每一次成功资金事实独立存在。
* FIN-INV-11：PSP reference 与 CommerceTransaction identity 严格分离。
* FIN-INV-12：无法证明的 legacy financial fact 不得伪造 ownership/capture 状态。

---

## 6. 跨层搜索记录（6 层，gate 强制）

搜索关键词：`PaymentCaptureEvent / capture / authorize / auto_capture / PaymentSession / PaymentCombination / PaymentSplit / Refund / response_code / transaction_id / fetch_payment_status / financial fact`。

| 层                   | 路径                                       | 搜索关键词                                                                                                          | 找到的文件                                                                                                                                     | 是否满足需求                                                            |
| ------------------- | ---------------------------------------- | -------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| App                 | `backend/app/`                           | payment/capture/refund/financial_fact                                                                          | 宿主层无新的资金事实解析模型                                                                                                                            | 否，无需在 app 层新建重复逻辑                                                 |
| Core                | `pallastrade_gems/pallastrade_core/app/` | Payment / Processing / PaymentCaptureEvent / Refund / PaymentSplit / CommerceTransaction / PaymentFactResolver | Payment、PaymentSession、PaymentCaptureEvent、Refund、PaymentCombination、PaymentSplit、CommerceTransaction、Transactions::*、PaymentFactResolver | 部分满足：原始 evidence 足够，但缺统一 FinancialFact Resolver                   |
| Stripe              | `pallastrade_gems/pallastrade_stripe/`   | auto_capture / manual_capture / PaymentIntent / charge / fetch_payment_status                                  | Stripe gateway、PaymentIntent presenter、session completion/status query                                                                    | 部分满足：provider execution/capture evidence 已有，但未标准化为 Financial Fact |
| API                 | `pallastrade_gems/pallastrade_api/app/`  | payment complete / refund / transaction                                                                        | Payment session/controller/webhook 路径                                                                                                     | 无需新增 API；Resolver 为 core 内部能力                                     |
| Admin               | `pallastrade_admin/app/`                 | manual capture / payment / refund                                                                              | Admin payment capture/refund 路径存在                                                                                                         | 仅作为 evidence path，FIN-P4-8 再展示 Financial View                     |
| Storefront/Platform | `storefront/src/`、`platform/packages/`   | payment / financial fact                                                                                       | Storefront 只驱动 checkout/payment execution                                                                                                 | 本包无消费方，不改前端/SDK                                                   |

**结论**：

* 当前项目并不缺 Payment/Refund/Capture 原始事实；
* 真正缺口是**统一金融语义解析层**；
* FinancialFactResolver 应位于 `pallastrade_core`；
* provider-specific capture predicate 应留在 gateway/policy adapter，不把 Stripe SDK 泄漏进 Core；
* 本包不存在重复造 Payment/Refund/Journal 模型风险。

---

## 7. 技术影响

* **新建（core gem）**：

  ```text
  backend/pallastrade_gems/pallastrade_core/app/models/
    pallastrade/financial_fact.rb
  ```

  或使用无 AR 的 value object 目录，按当前 core convention 决定。

  ```text
  backend/pallastrade_gems/pallastrade_core/app/services/pallastrade/financial_facts/
    resolve_payment.rb
    resolve_refund.rb
    instrument_classifier.rb
    ownership_resolver.rb
    capture_evidence_policy.rb
  ```

* **Provider extension（仅 policy/adapter，不新增 financial API）**：

  * Stripe 提供 manual/auto capture evidence 判定适配；
  * Bogus 提供测试 parity；
  * Adyen/PayPal 如无可靠 contract，显式 unsupported/ambiguous。

* **可能读取但原则上不修改**：

  * `Payment`
  * `PaymentSession`
  * `PaymentCaptureEvent`
  * `PaymentCombination`
  * `PaymentSplit`
  * `Refund`
  * `CommerceTransaction`
  * `TransactionOrder`

* **DB**：

  * 无 migration；
  * 无 schema change；
  * 无 backfill。

* **API**：

  * 无 controller；
  * 无 route；
  * 无 serializer；
  * 不更新 OpenAPI。

* **Storefront/SDK**：

  * 无变化。

* **CommerceTransaction**：

  * 不新增 state；
  * 不新增 finance column。

* **Payment/Refund**：

  * 不改 state machine；
  * 不改变 capture/refund execution。

* **后续 FIN-P4-2 contract**：

  * Financial Journal posting 必须接收本包标准 FinancialFact；
  * 不允许 P4-2 自行重做 provider-specific captured 判定。

* **代码命名纪律**：

  * `commerce_transaction_id` = txn_ domain；
  * `provider_payment_reference` = pi_/provider equivalent；
  * `provider_refund_reference` = re_/provider equivalent；
  * 禁止新增含糊 PSP `transaction_id` 语义。

* **Scope 外明确不创建**：

  * `financial_journal_entries`
  * `financial_reconciliations`
  * `provider_financial_snapshots`
  * fee/net columns。

---

## 8. 测试计划

* **新增**：

  ```text
  backend/spec/services/pallastrade/financial_facts/
    instrument_classifier_spec.rb
    capture_evidence_policy_spec.rb
    ownership_resolver_spec.rb
    resolve_payment_spec.rb
    resolve_refund_spec.rb
  ```

* **ResolvePayment 必测矩阵**：

  * Stripe auto capture；
  * Stripe manual authorize；
  * Stripe manual capture；
  * PaymentCombination；
  * StoreCredit；
  * Check/offline；
  * Bogus；
  * legacy/unknown provider；
  * short payment；
  * multiple successful payments；
  * amount/currency conflict；
  * missing CommerceTransaction ownership。

* **ResolveRefund 必测矩阵**：

  * 单订单 refund；
  * partial refund；
  * multiple refunds；
  * combination target refund；
  * provider refund reference；
  * missing transaction ownership；
  * failed perform 不产生 REFUND_SUCCEEDED。

* **Capture 测试要求**：

  * 至少一条 Stripe manual-capture 测试真实经过项目 capture service/model method；
  * 不允许全部通过 factory 手工 `state=completed` 制造结果。

* **只读性测试**：

  * Resolver 前后 Payment/Refund/Transaction row 不发生 mutation；
  * 不调用 purchase/capture/refund side-effect method。

* **Provider boundary 测试**：

  * StoreCredit/Offline 不触发 provider query；
  * unsupported provider 返回明确 status。

* **Regression**：

  * P0 PaymentSession/Payment/Webhook specs；
  * P1 Checkout specs；
  * P2 Transaction Start/Finalize/Recover specs；
  * P3 Inventory specs。

* **AC→测试映射**：

  * AC-4P1-01~29 强制映射；
  * 每个 spec 按项目 convention 标注 PRD/AC。

* **建议重点运行时验证**：

  * Stripe sandbox manual authorize → capture；
  * 验证 authorize 阶段 resolver != CASH_CAPTURED；
  * capture 后 resolver = CASH_CAPTURED。

---

## 9. 文档同步清单（知识同步门）

* [ ] `ai/skills/pallastrade-payments/SKILL.md`

  * 新增 Financial Fact 四层模型；
  * `Payment.completed != universal captured`;
  * manual authorization/capture；
  * FinancialFactResolver 为 Journal 唯一入口。
* [ ] `ai/skills/pallastrade-data-model/SKILL.md`

  * 如包含 CommerceTransaction/Payment ownership 图，补 FinancialFact 为 transient/value-object，不是新 DB aggregate。
* [ ] `ai/skills/pallastrade-testing/SKILL.md`

  * Capture critical-path testing rule；
  * 禁止只 factory 造 completed payment 覆盖全部资金测试。
* [ ] 支付反模式：

  * `payment.completed? → CASH_CAPTURED` 通用判断；
  * PaymentSplit 当第二笔 cash；
  * StoreCredit 当 PSP cash；
  * PSP transaction_id 当 CommerceTransaction；
  * AMBIGUOUS 强行判 captured。
* [ ] FIN-P4-0 审计文档正式落档，至少冻结：

  * FINANCIAL_INSTRUMENT_CLASSIFICATION
  * CAPTURE_EVIDENCE_POLICY
  * FINANCIAL_FACT_AUTHORITY
  * SUCCESSFUL_PAYMENT_CARDINALITY
  * REFUND_OWNERSHIP_POLICY
  * RETRY_PAYMENT_FINANCIAL_SAFETY_POLICY
* [ ] 原附件 `FIN-P4-1 Immutable Financial Journal` 文档改号/迁移为：

  * `FIN-P4-2 Immutable Financial Journal`
  * 删除其直接从 Payment state 判断 posting 的表述；
  * posting input 改为 `FinancialFact`。
* [ ] `docs/prd/README.md` 更新 P4 拆包顺序。
* [ ] 本包无 API 文档更新。
* [ ] 本包无 schema migration。
* [ ] 本包完成报告中明确记录 unsupported legacy providers，不得把未支持能力描述为 reconciliation PASS。

---

## 10. 变更记录

| 日期         | 版本  | 变更                                                                                                                                                                                                                                                                   | 操作者 |
| ---------- | --- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --- |
| 2026-09-06 | 0.1 | 原 FIN-P4-1 初稿：Immutable Financial Journal                                                                                                                                                                                                                            | AI  |
| 2026-09-06 | 0.2 | 根据 FIN-P4-0 实际代码审计与 P4 V2 架构重排：FIN-P4-1 改为 Financial Fact Resolution；Journal 顺延 FIN-P4-2；新增 instrument classification、capture evidence、manual capture、multiple successful payments、Refund ownership、retry-payment safety、provider capability、只读 side-effect boundary | AI  || 2026-09-06 | 0.3 | 实施完成（TASK-20260905162544-eb1316bf / GATE-2026-09-05T16-26-02）：core 新增 FinancialFact VO + FinancialFacts::{InstrumentClassifier,CaptureEvidencePolicy,OwnershipResolver,ResolvePayment,ResolveRefund,RetryPaymentSafetyPolicy}；spec 新增 56 examples 0 failures（含真实 confirm!/capture! manual-capture 路径）+ P0-P3 回归 92 examples 0 failures；supervise diff 0 findings；knowledge 同步（payments/data-model/testing skills + scenarios GS-050）；无 migration/API | AI |