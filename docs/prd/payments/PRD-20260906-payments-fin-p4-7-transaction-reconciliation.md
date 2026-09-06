# FIN-P4-7：Transaction Reconciliation —— CommerceTransaction 级财务聚合与核对（P4 拆包第 7 包）

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-06 |
| 来源 | 用户「继续 P4-7」→ P4 V2 拆包第 7 包（Transaction Reconciliation）；前序 FIN-P4-1~6 均 done |
| 分类 | payments |
| 关联 Skill | `ai/skills/pallastrade-payments/SKILL.md`、`pallastrade-testing/SKILL.md` |
| 关联 REQ | REQ-20260906-fin-p4-7.md（实施时回填） |
| 关联 PRD | 上游：`豆包梳理业务需求/P4 — ...md`（V2；§63 FIN-P4-7 + §25/§36 第二层/§38/§39-44/§66 AC-4013~4016/§67 INV-04/09/11）；前序 FIN-P4-1~6 |
| 需求类型 | 新功能（core 只读 transaction 级聚合 + 核对服务；**无 migration/API/UI**——结果 transient VO，持久化/Admin/Repair 归 FIN-P4-8） |

> V2 顺序：FIN-P4-1 ✅ → … → FIN-P4-6 ✅ → **FIN-P4-7 Transaction Reconciliation（本包）** → FIN-P4-8 Repair / Legacy / Operations。
> 复用：FIN-P4-2 Journal（`FinancialLedgerEntry.by_transaction` immutable 事实源）+ FIN-P4-4 Allocation（ORDER_ALLOCATION entries/AllocationIntegrity）+ FIN-P4-6 Source Reconciliation（逐 payment/refund provider 核对）。

---

## 1. 背景与目标

- **一句话需求原文**：实现 CommerceTransaction 级 Transaction Financial Reconciliation（P4 §63/§36 第二层/§38）——聚合 Journal + Allocation + Provider Source Reconciliations，产生交易级财务对账结论（§25 TransactionFinancialSummary）。
- **背景**：FIN-P4-6 已实现 Payment/Refund ↔ PSP 的**源级**核对（第一层）。但一个 CommerceTransaction 可对应 N successful payments（INV-04/FIN-P4-1），且缺交易级视角：commercial vs captured、allocation vs captured、refund vs captured、provider gross vs local captured、provider refund vs local refund 是否一致**不可知**。P2 `CommerceTransaction#trace` 是执行层 trace（状态/attempt/session），非财务面。
- **目标**：core 新增**只读、无副作用、幂等**的 Transaction 级聚合与核对服务，输出交易级财务摘要（§25 字段）+ 六态结论（§39）+ 原因码（§42）；**绝不修改 Payment/Refund/Transaction、绝不自动 charge/refund、绝不自动倒退 transaction state**（§44/§46/AC-4023/INV-11）；Journal 缺失/未 posting 如实暴露（不猜，INV-09/12）。
- **成功指标**：AC-4P7-* 全绿；新增 spec + 全量 backend-rspec 0 failures；无 migration/API/UI。

## 2. 用户故事 / 场景

| # | 场景 | 类型 | 描述 |
|---|---|---|---|
| S1 | 单支付 exact-paid | 正常 | txn amount == journal cash_captured == allocation_total（无组合）→ MATCHED |
| S2 | 组合支付 exact-paid | 正常 | combined_payment txn：Σ splits captured == Σ ORDER_ALLOCATION == commercial → MATCHED（AC-4014/4015） |
| S3 | Short payment | 边界 | cash_captured < commercial → 明确表现（short-paid 非 ledger error，AC-4016） |
| S4 | 多支付累计 | 正常 | 1 txn → N payments → journal Σ CASH_CAPTURED == 实际收款（INV-04/RV-F03） |
| S5 | 部分退款 | 正常 | cash_captured + refund 后 net 正确（RV-F05）；refund 逐笔保留 |
| S6 | Journal 缺失 | 异常 | 本地有 payment 证据但 Journal 无 entry → 暴露缺失（不猜、不自动 repair，repair 归 P4-8） |
| S7 | Provider 单侧不一致 | 异常 | provider gross ≠ local captured → 逐 payment source 层已捕获；交易级聚合如实汇总 |
| S8 | 无 PSP 交易 | 正常 | StoreCredit/Check-only txn → provider 面 NOT_APPLICABLE（local 仍可核对） |
| S9 | 只读/幂等 | 边界 | 重复 reconcile 同结果；零写库/零 state 变更/零 Journal 创建/零自动资金动作 |

## 3. 功能需求（FR）

- FR-4P7-01：新增 `PallasTrade::Reconciliations::TransactionResult`（transient 只读 VO，镜像 SourceResult 模式）：
  `transaction_id(prefixed) / status / reasons[] / summary(TransactionFinancialSummary) / source_reconciliations[] / provider_gross_amount / provider_currency / provider_fee / provider_net / observed_at`；
  STATUSES 复用六态（§39：PENDING/MATCHED/MISMATCH/NEEDS_ATTENTION/NOT_APPLICABLE/UNSUPPORTED，const_set 字符串常量——P4-6 教训）；
  `matched?/mismatch?/pending?/needs_attention?/not_applicable?/unsupported?`；构造后 freeze。
- FR-4P7-02：新增 `PallasTrade::Reconciliations::TransactionFinancialSummary`（transient 只读 VO，§25 字段）：
  `commercial_amount / cash_captured / store_credit_applied / offline_payment_recorded / gross_value_received / refund_total / net_customer_value / allocation_total / unallocated_amount / currency / provider_fee / provider_net / reconciliation_status`；
  `gross_value_received = cash_captured + store_credit_applied + offline_payment_recorded`；`net_customer_value = gross_value_received − refund_total`；
  派生 helper：`short_paid?`（cash < commercial）/`overpaid?`；freeze。
- FR-4P7-03：新增 `PallasTrade::Reconciliations::ReconcileTransaction.call(transaction:)` 只读服务：
  - `transaction` nil → failure；无 Journal 数据能力 → 按真实查询聚合。
  - **local 面（Journal 权威源，FIN-P4-2 immutable）**：`FinancialLedgerEntry.active.by_transaction(transaction)` 按 entry_type 聚合 sum(amount)：
    `CASH_CAPTURED→cash_captured / STORE_CREDIT_APPLIED→store_credit_applied / OFFLINE_PAYMENT_RECORDED→offline_payment_recorded / REFUND_SUCCEEDED→refund_total（负数取正）/ ORDER_ALLOCATION→allocation_total`。
  - **provider 面（复用 FIN-P4-6，逐源）**：枚举 transaction 可达的 payments（sessions→payment；组合 purpose=combined_payment → payment_combination.payments）与 refunds（payment.refunds），逐个调 `ReconcilePayment`/`ReconcileRefund`（只读、幂等）聚合：
    - provider gross = Σ 各 payment provider_gross_amount（provider 面 NOT_APPLICABLE 的交易 → provider_gross nil）；
    - provider fee/net = Σ 各 payment provider 侧 fee/net（P4-5 provider details 已归一；可空不猜）；
    - provider refund 核对经各 ReconcileRefund SourceResult 汇总。
  - **核对矩阵（§38）**：
    1. allocation vs captured：`allocation_total == cash_captured`？否 → reason `ALLOCATION_MISMATCH`（组合下镜像 AllocationIntegrity 语义，per txn）；
    2. refund vs captured：`refund_total <= cash_captured`？否 → reason `REFUND_MISMATCH`；
    3. provider gross vs local captured：provider 面支持时 `provider_gross ≈ cash_captured`？否 → reason `AMOUNT_MISMATCH`；provider 面 UNSUPPORTED → 记 `PROVIDER_CONTRACT_UNSUPPORTED`（非 MISMATCH，§41）；
    4. commercial vs captured：`cash_captured < commercial_amount` → 合法 short-paid（不 alarm，summary 如实暴露）；`cash_captured > commercial_amount` → reason `COMMERCIAL_AMOUNT_MISMATCH`（over-collect 异常）。
  - **状态合成**：任一 provider source NEEDS_ATTENTION → NEEDS_ATTENTION；任一 MISMATCH → MISMATCH；provider 面有 PENDING（settlement pending，§43/AC-4020）→ PENDING 不误报 MISMATCH；local 全核对通过且 provider 一致 → MATCHED；Journal 缺失但 payment 证据存在 → NEEDS_ATTENTION + `JOURNAL_POSTING_MISSING`（暴露不猜，repair 归 P4-8）；无 PSP 交易 → provider 面 NOT_APPLICABLE（local 可 MATCHED 语义单独表述）。
  - **只读/无副作用**：不创建/更新 Journal/Payment/Refund/Transaction，不改任何 state machine，绝不自动 charge/refund/倒退 transaction（§44/§46/AC-4023）；纯函数幂等（AC-4024）。
- FR-4P7-04：范围外——不落表 transaction summary/reconciliation 快照（§25「首版不必落表」/§34 JSON snapshot → P4-8 admin/持久化决定）；不 repair Journal/backfill/retry/sweeper（FIN-P4-8）；不 Admin Financial View/UI（FIN-P4-8/§51）；无 migration/API。
- FR-4P7-05：capability/复用纪律：local captured 判定继续经 FIN-P4-1 `CaptureEvidencePolicy` 的消费方（provider 面已由 P4-6 承载）；Journal 为本地金额唯一权威聚合源（不重复从 Payment 现算 cash，避免与 immutable ledger 分歧）。

## 4. 非功能需求（NFR）

- 只读：零本地写、零 provider mutation、零自动资金动作（§44/AC-4023/INV-09）。
- 幂等：纯函数（输入 transaction + provider/journal 状态）→ 重跑同结果（AC-4024）。
- 失败语义：provider 侧逐源异常已被 P4-6 捕获为 NEEDS_ATTENTION/PROVIDER_UNAVAILABLE（本服务不重复 raise；聚合继续）。
- 性能：单 txn 内 journal 聚合 1 次查询 + 逐源 provider 查询（复用 P4-6）；无缓存要求。
- 兼容：无 schema/API；P0~P4-6 行为不变；Journal/Payment/Refund/Transaction state machine 全不动。
- 确定性：Bogus provider 替身确定性；Stripe stub 测试（沿 P4-5/4-6 模式）。

## 5. 验收标准（AC，与测试一一映射）

> 对齐 P4 §63/§25/§36 第二层/§38/§39-44/§66 AC-4013~4016/§67 INV-04/09/11/12。

- AC-4P7-01 ← FR-4P7-03 / AC-4014/4015：组合 exact-paid：`commercial_amount == Σ CASH_CAPTURED == Σ ORDER_ALLOCATION` → `MATCHED`。
- AC-4P7-02 ← FR-4P7-03 / AC-4016：short payment：`cash_captured < commercial_amount` → 不 alarm，summary 如实暴露（`short_paid?` true）。
- AC-4P7-03 ← FR-4P7-03 / INV-04 / RV-F03：1 txn → N payments（multi capture）→ journal Σ 正确累计为 cash_captured。
- AC-4P7-04 ← FR-4P7-03 / RV-F05：部分退款：cash_captured/refund_total/net_customer_value 正确；refund 逐笔独立保留。
- AC-4P7-05 ← FR-4P7-03：Journal 缺失（payment 证据在但无 CASH_CAPTURED entry）→ `NEEDS_ATTENTION` + `JOURNAL_POSTING_MISSING`（不猜、不自动 repair）。
- AC-4P7-06 ← FR-4P7-03：allocation != captured → `MISMATCH` + `ALLOCATION_MISMATCH`。
- AC-4P7-07 ← FR-4P7-03：provider 面 UNSUPPORTED（Adyen/PayPal legacy）→ 不误报 MISMATCH（记 `PROVIDER_CONTRACT_UNSUPPORTED`）；StoreCredit/Check-only → provider 面 NOT_APPLICABLE。
- AC-4P7-08 ← FR-4P7-03 / AC-4023/INV-09：只读边界——零写库、零 state 变更、零 Journal/Payment/Refund 创建、零自动资金动作、零 transaction 倒退；重复执行同结果。
- AC-4P7-09 ← FR-4P7-01/02：`TransactionResult`/`TransactionFinancialSummary` VO 白名单/freeze/派生 helper（`short_paid?`/`gross_value_received`/`net_customer_value`）。
- AC-4P7-10 ← FR-4P7-04：范围外确认——无 migration/schema/API/UI；不落表、不 repair/backfill。
- AC-4P7-11 ← FR-4P7-03：回归零破坏——P4-1~6 + P0-P3 + stripe gem specs 全绿。

## 6. 跨层搜索记录（6 层，gate 强制）

关键词：`transaction reconciliation / TransactionFinancialSummary / 财务聚合 / financial summary / reconcile_transaction / 交易级核对`。

| 层 | 路径 | 关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | financial summary/reconcile | 无（仅 admin ai_controller overview 无关） | 否 |
| Core models/services | `pallastrade_core/app/` | transaction/reconcile/summary | `CommerceTransaction`（amount/state/trace=P2 执行层读模型，非财务面）；`FinancialLedgerEntry`（by_transaction/by_entry_type/active scopes——本地聚合源就绪）；`Reconciliations::{SourceResult,ReconcilePayment,ReconcileRefund}`（P4-6 源级）；`FinancialLedger::AllocationIntegrity`（combination 维度恒等式，P4-4）；`CaptureEvidencePolicy` | 部分：Journal/源级/Allocation 就绪；缺 transaction 级聚合+核对服务/VO |
| API gem | `pallastrade_api/app/` | reconcile/ledger | 无 | 否（本包无 API） |
| Admin gem | `pallastrade_admin/app/` | transactions/trace | `TransactionsController#show` = `#trace`（P2 执行 trace，非财务面） | 否（Admin financial view 归 P4-8） |
| DB schema | schema | reconciliation/summary 表 | 无（结果 transient VO；§25 首版不必落表） | 本包无 migration |
| Storefront | `storefront/src/` | reconcile/financial | 无 | 否 |
| Platform | `platform/packages/` | reconcile/financial | 无 | 否 |

**结论**：Journal（本地金额权威）+ P4-6 Source Reconciliation（provider 逐源）+ P4-4 Allocation 就绪；缺口 = TransactionResult/TransactionFinancialSummary VO + ReconcileTransaction 聚合服务。无重复能力、无 migration。

## 7. 技术影响

- **修改（core gem）**：无（全部新增；不改既有 Journal/Payment/Refund/Transaction/P4-6 文件）。
- **新建（core gem）**：
  - `app/services/pallastrade/reconciliations/transaction_result.rb`（transient VO + 六态常量 + 谓词 + freeze）
  - `app/services/pallastrade/reconciliations/transaction_financial_summary.rb`（transient VO + 派生 helper + freeze）
  - `app/services/pallastrade/reconciliations/reconcile_transaction.rb`（编排：Journal 聚合 + 逐源 P4-6 provider 聚合 + §38 核对矩阵 + 状态合成）
- **不修改**：Payment/Refund/Transaction state machine、Journal/Post/Reverse、P4-6 reconcile 服务、fetch_* 契约路径；无 migration/schema；无 API/UI。
- **关键设计决策（实施冻结）**：本地金额唯一权威 = immutable Journal（FIN-P4-2）按 entry_type 聚合，不从 Payment 现算 cash（避免与 ledger 分歧）；provider 面复用 P4-6 逐源（不重复实现 provider fetch）；结果 transient VO 不落表（P4-8 决定持久化）；status/reason 枚举对齐 §39/§42；构造端一律用字符串常量（P4-6 symbol 坑）；纯函数幂等（AC-4024）；Journal 缺失暴露为 NEEDS_ATTENTION 不猜（INV-09/12）。

## 8. 测试计划

- 新增（backend/spec）：
  - `spec/services/pallastrade/reconciliations/transaction_result_spec.rb` —— AC-4P7-09
  - `spec/services/pallastrade/reconciliations/transaction_financial_summary_spec.rb` —— AC-4P7-09
  - `spec/services/pallastrade/reconciliations/reconcile_transaction_spec.rb` —— AC-4P7-01~08/10/11（Bogus 确定性 + 真实 Journal posting fixture）
- 真实路径：单支付 txn（payment captured + journal CASH_CAPTURED posted）→ MATCHED；组合 txn（combination complete fixture + splits + ORDER_ALLOCATION posted）→ MATCHED/exact-paid；short payment 构造（captured < amount）；multi-payment（2 支付 2 entries）；refund（partial refund + REFUND_SUCCEEDED）；Journal 缺失（payment 有但无 entry）；legacy/无 PSP。
- 回归：P4-1~6 specs（financial_facts/financial_ledger/payments/transactions/reconciliations）+ stripe gem specs + P0-P3 → 0 failures；全量 backend-rspec（coverage-gate）。
- AC 映射：AC-4P7-01~11 → 上述 spec + 回归（spec 内 `AC-4P7-xx` 标注）。

## 9. 文档同步清单（知识同步门）

- [ ] `ai/skills/pallastrade-payments/SKILL.md`：补 Transaction Reconciliation 章节（ReconcileTransaction + TransactionResult/TransactionFinancialSummary + §38 核对矩阵 + 状态合成语义）。
- [ ] `harness/scenarios/scenarios.json`：新增 GS-056（transaction reconciliation 场景）。
- [ ] 本 PRD 状态 + `docs/prd/README.md` 索引。
- [ ] API/schema：不涉及。

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-06 | 0.1 | 初稿：FIN-P4-7 Transaction Reconciliation 拆包 PRD（P4 §63/§25/§36 第二层/§38/§39-44/AC-4013~4016/INV-04/09/11/12 + P4-2 Journal/P4-4 Allocation/P4-6 源级复用；TransactionResult + TransactionFinancialSummary VO + ReconcileTransaction；无 migration，结果不落表归 P4-8） | AI |
| 2026-09-06 | 0.2 | 实施完成：ReconcileTransaction/TransactionResult/TransactionFinancialSummary + SourceResult additive provider_fee/net；新 41 specs + 回归 core 256/stripe 59 0 failures（全量 EVD-20260906044533-5ac3db64a4）；skills §Transaction Reconciliation + scenarios GS-056 同步（Journal 权威聚合 + §38 核对矩阵 + journal-missing/short-paid 语义） | AI |
