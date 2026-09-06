# FIN-P4-6：Source Reconciliation —— Payment/Refund ↔ PSP 独立源级核对（P4 拆包第 6 包）

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-06 |
| 来源 | 用户「自主推进」→ P4 V2 拆包第 6 包（Source Reconciliation）；前序 FIN-P4-1~5 均 done |
| 分类 | payments |
| 关联 Skill | `ai/skills/pallastrade-payments/SKILL.md`、`pallastrade-testing/SKILL.md` |
| 关联 REQ | REQ-20260906-fin-p4-6.md |
| 关联 PRD | 上游：`豆包梳理业务需求/P4 — ...md`（V2；§62 FIN-P4-6 + §36/§37/§39-44/§66 AC-4018~4024）；前序 FIN-P4-1~5 |
| 需求类型 | 新功能（core 只读 reconciliation 服务 + provider refund 只读契约 + Bogus 替身；**无 migration/API/UI**——结果 transient VO，持久化归 P4-7/8） |

> V2 顺序：FIN-P4-1 ✅ → … → FIN-P4-5 ✅ → **FIN-P4-6 Source Reconciliation（本包）** → FIN-P4-7 Transaction Reconciliation。
> 复用：FIN-P4-5 `fetch_financial_details`（Payment↔PSP provider 侧）+ FIN-P4-1 `CaptureEvidencePolicy`（local captured）+ capability method-owner 判定。

---

## 1. 背景与目标

- **一句话需求原文**：实现 Payment ↔ PSP 与 Refund ↔ PSP 的独立 source-level reconciliation（P4 §62/§36 第一层/§37）。
- **背景**：FIN-P4-5 已提供只读 provider 财务明细（PI/Charge/BT/Refunds 归一）。但尚无"本地 vs provider"核对：local Payment captured ↔ provider gross、local Refund ↔ provider Refund 是否一致不可知（RISK-FIN-06 背景）。
- **目标**：core 新增**只读、无副作用、幂等**的源级核对服务，输出标准状态（§39）+ 原因码（§42）；**绝不修改 Payment/Refund、绝不自动 charge/refund**（§44/AC-4023）；settlement pending 不误报（§43/AC-4020）；StoreCredit/Check → NOT_APPLICABLE（§40/AC-4021）；Adyen/PayPal legacy → UNSUPPORTED 非 MISMATCH（§41/AC-4022）。供 P4-7 聚合与后续 admin/ops 消费。
- **成功指标**：AC-4P6-* 全绿；新增 spec + 全量 backend-rspec 0 failures；无 migration/API/UI。

## 2. 用户故事 / 场景

| # | 场景 | 类型 | 描述 |
|---|---|---|---|
| S1 | Payment MATCHED | 正常 | local captured == provider gross（Stripe cs_/pi_）→ MATCHED |
| S2 | Payment AMOUNT_MISMATCH | 异常 | local 与 provider gross 不同 → MISMATCH + AMOUNT_MISMATCH（不改不扣） |
| S3 | Settlement pending | 边界 | provider details settlement 非 settled → PENDING + SETTLEMENT_PENDING（AC-4020 不误报） |
| S4 | Provider unavailable | 异常 | provider 查询异常 → NEEDS_ATTENTION + PROVIDER_UNAVAILABLE（可重跑） |
| S5 | local captured 但 provider 无 | 异常 | provider settled 但 local 未 captured → NEEDS_ATTENTION（LOCAL_PAYMENT_MISSING） |
| S6 | Refund MATCHED | 正常 | local refund amount/currency == provider refund → MATCHED |
| S7 | Refund MISMATCH | 异常 | 金额不符 → MISMATCH + REFUND_MISMATCH |
| S8 | StoreCredit/Check | 正常 | NOT_APPLICABLE（无 PSP） |
| S9 | Adyen/PayPal legacy | 边界 | UNSUPPORTED（不误报 MISMATCH） |
| S10 | 幂等/只读 | 边界 | 重复 reconcile 同结果；零写库/零 state/零自动资金动作 |

## 3. 功能需求（FR）

- FR-4P6-01：新增 `PallasTrade::Reconciliations::SourceResult`（transient 只读 VO）：`source_type(payment/refund) / source_id(prefixed) / status / reasons[] / local_amount / local_currency / provider_gross_amount / provider_currency / provider_settlement_status / provider_payment_reference / provider_charge_reference / provider_error / observed_at`；STATUSES = `PENDING MATCHED MISMATCH NEEDS_ATTENTION NOT_APPLICABLE UNSUPPORTED`（§39）；`matched?/mismatch?/not_applicable?/unsupported?`；构造后 freeze。
- FR-4P6-02：`ReconcilePayment.call(payment:)` 只读服务：
  - StoreCredit/Check → NOT_APPLICABLE；payment.payment_session 缺失且无法 provider 查询 → NEEDS_ATTENTION + `UNLINKED_LEGACY_PAYMENT`（可含 local captured 信息）。
  - provider capability 无 `fetch_financial_details` 实现 → UNSUPPORTED + `PROVIDER_CONTRACT_UNSUPPORTED`（Adyen/PayPal）。
  - local captured（经 FIN-P4-1 `CaptureEvidencePolicy`：completed + capture_event / combination succeeded → captured_amount）：
    - provider details 可获取：settlement == settled → 比对 amount/currency/reference → MATCHED；不符 → MISMATCH（`AMOUNT_MISMATCH`/`CURRENCY_MISMATCH`）；provider ref 缺失 → NEEDS_ATTENTION `PROVIDER_PAYMENT_MISSING`。
    - provider details settlement 非 settled → PENDING + `SETTLEMENT_PENDING`（AC-4020）。
  - provider 异常（Stripe::StripeError/GatewayError）→ NEEDS_ATTENTION + `PROVIDER_UNAVAILABLE`（记录 provider_error；reconcile 幂等可重跑，AC-4024）。
  - local 未 captured 但 provider settled → NEEDS_ATTENTION + `LOCAL_PAYMENT_MISSING`（证据冲突，不猜）。
  - **只读/无副作用**：不创建/更新 Payment/Refund/Journal/session；永不自动 charge/refund（§44/AC-4023）。
- FR-4P6-03：新增 provider 只读契约 `PaymentMethod#fetch_refund_details(refund:)`（default raise，镜像）→ 归一 `{ provider_refund_reference, amount, currency, status }`。`PallasTradeStripe::Gateway` 实现：`Stripe::Refund.retrieve(refund.transaction_id)`（新增只读 `retrieve_refund`；transaction_id 缺失 → GatewayError「无 provider refund reference」）；`Gateway::Bogus` 确定性替身（transaction_id 存在 → amount/currency/succeeded；否则 provider 缺失语义）。
- FR-4P6-04：`ReconcileRefund.call(refund:)` 只读服务：
  - payment 为 StoreCredit/Check → NOT_APPLICABLE；provider 无 refund 契约实现 → UNSUPPORTED + `PROVIDER_CONTRACT_UNSUPPORTED`。
  - local refund 无 transaction_id（未链接）→ NEEDS_ATTENTION + `UNLINKED_LEGACY_PAYMENT`。
  - provider 查询异常 → NEEDS_ATTENTION + `PROVIDER_UNAVAILABLE`。
  - 比对 local amount/currency vs provider → MATCHED / MISMATCH（`REFUND_MISMATCH`）。
  - 只读/无副作用（同 FR-4P6-02）。
- FR-4P6-05：capability：`ReconcilePayment/Refund` 用 `implements_financial_details?` / 新增 `implements_refund_details?`（method owner ≠ base）路由；与实现存在性一致，禁止 rescue NotImplementedError 表达（沿用 P4-5）。
- FR-4P6-06：范围外——不做 Transaction 级聚合（P4-7）；不持久化 reconciliation 结果/快照（§34 JSON snapshot → P4-7/8 admin 决定）；不 repair/backfill（P4-8）；无 migration/API/UI。

## 4. 非功能需求（NFR）

- 只读：零本地写、零 provider mutation、零自动资金动作（§44/AC-4023）。
- 幂等：纯函数（输入 payment/refund + provider 状态）→ 重跑同结果（AC-4024）。
- 失败语义：provider/网络异常捕获为 `PROVIDER_UNAVAILABLE` 结果（reconciliation 是 ops 检查非支付流——区别于 recovery 的 raise 语义），可重跑。
- 确定性：Bogus 替身（spec/P4-7 确定性）；Stripe stub 测试。
- 性能：每 source 1-3 次 provider 调用；无缓存要求。
- 兼容：无 schema/API；P0-P4-5 行为不变。

## 5. 验收标准（AC，与测试一一映射）

> 对齐 P4 §39/§40-44/§66 AC-4018~4024。

- AC-4P6-01 ← FR-4P6-02 / AC-4018：local captured == provider gross（cs_/pi_ 双模式）→ `MATCHED`（含 amount/currency/reference 核对）。
- AC-4P6-02 ← FR-4P6-02：金额/币种不符 → `MISMATCH` + `AMOUNT_MISMATCH`/`CURRENCY_MISMATCH`；**不修改 Payment、不自动扣款**（AC-4023）。
- AC-4P6-03 ← FR-4P6-02 / AC-4020：provider settlement 非 settled → `PENDING` + `SETTLEMENT_PENDING`（不误报 MISMATCH）。
- AC-4P6-04 ← FR-4P6-02：provider 异常 → `NEEDS_ATTENTION` + `PROVIDER_UNAVAILABLE`；重跑幂等同结果（AC-4024）。
- AC-4P6-05 ← FR-4P6-02：local 未 captured 但 provider settled → `NEEDS_ATTENTION` + `LOCAL_PAYMENT_MISSING`（证据冲突不猜）。
- AC-4P6-06 ← FR-4P6-04 / AC-4019：local Refund amount/currency == provider Refund → `MATCHED`（reference 链接核对）。
- AC-4P6-07 ← FR-4P6-04：Refund 金额不符 → `MISMATCH` + `REFUND_MISMATCH`（不自动 refund）。
- AC-4P6-08 ← FR-4P6-02/04 / AC-4021/4022：StoreCredit/Check → `NOT_APPLICABLE`；无实现 legacy（Adyen/PayPal 代理）→ `UNSUPPORTED`（非 MISMATCH）。
- AC-4P6-09 ← FR-4P6-02/04：只读边界——reconcile 零写库、零 state 变更、零 Journal/payment/refund 创建；重复执行同结果。
- AC-4P6-10 ← FR-4P6-01：`SourceResult` VO 白名单/freeze/status helper。
- AC-4P6-11 ← FR-4P6-06：回归零破坏——P4-1~5 + P0-P3 + stripe gem specs 全绿。

## 6. 跨层搜索记录（6 层，gate 强制）

关键词：`reconciliation / reconcile / SourceResult / source-level / MISMATCH / reconcile_payment / reconcile_refund`。

| 层 | 路径 | 关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | reconcile | 无 | 否 |
| Core models/services | `pallastrade_core/app/` | reconciliation/reconcile | 无 reconciliation 服务；`FinancialFacts::CaptureEvidencePolicy`（local captured）；`PaymentMethod#fetch_financial_details`（P4-5 base 契约）；`Gateway::Bogus`（P4-5 替身）；`PaymentMethod`/`Refund` | 部分：P4-5 provider 侧就绪，缺 reconcile 服务/VO |
| Stripe gem | `pallastrade_stripe/app/` | refund retrieve | `Gateway#retrieve_charge/retrieve_balance_transaction`；`fetch_financial_details`（P4-5）；**无 refund retrieve/`fetch_refund_details`** | 部分：缺 refund 只读契约 |
| DB schema | schema | reconciliation 表 | 无（结果 transient VO） | 本包无 migration |
| API/Admin/Storefront/Platform | 各层 | reconciliation | 无 | 否（无 API/UI） |

**结论**：P4-5 provider 财务明细 + P4-1 local captured 判定就绪；缺口 = SourceResult VO + ReconcilePayment/ReconcileRefund 服务 + provider `fetch_refund_details`（Stripe/Bogus）+ capability。无重复能力、无 migration。

## 7. 技术影响

- **修改（core gem）**：
  - `app/models/pallastrade/payment_method.rb`：+`fetch_refund_details(refund:)` base 契约（default raise）。
  - `app/models/pallastrade/gateway/bogus.rb`：+确定性 `fetch_refund_details`。
- **修改（stripe gem）**：`gateway.rb`：+只读 `retrieve_refund(id)`；`gateway/payment_sessions.rb` 或 gateway.rb：+`fetch_refund_details(refund:)`（Refund.retrieve → amount/currency/status 归一；缺 transaction_id → GatewayError）。
- **新建（core gem）**：
  - `app/services/pallastrade/reconciliations/source_result.rb`
  - `app/services/pallastrade/reconciliations/reconcile_payment.rb`
  - `app/services/pallastrade/reconciliations/reconcile_refund.rb`
- **不修改**：Payment/Refund state machine、Journal、Transactions::*、fetch_payment_status/fetch_financial_details 路径；无 migration/schema；无 API/UI。
- **关键设计决策（实施冻结）**：结果 transient VO 不落表（P4-7/8 决定持久化）；status/reason 枚举对齐 §39/§42；local captured 唯一入口 = CaptureEvidencePolicy（FIN-INV-02）；provider 异常捕获为 PROVIDER_UNAVAILABLE 结果；reconcile 纯函数幂等（AC-4024）；Stripe refund 按 transaction_id retrieve。

## 8. 测试计划

- 新增（backend/spec + stripe gem spec）：
  - `spec/services/pallastrade/reconciliations/source_result_spec.rb` —— AC-4P6-10
  - `spec/services/pallastrade/reconciliations/reconcile_payment_spec.rb` —— AC-4P6-01/02/03/04/05/08/09（bogus 确定性 + Stripe stub）
  - `spec/services/pallastrade/reconciliations/reconcile_refund_spec.rb` —— AC-4P6-06/07/08/09
  - `pallastrade_gems/pallastrade_stripe/spec/.../fetch_refund_details_spec.rb`（或并入 gateway spec）—— Stripe refund 归一
- 真实路径：Bogus 确定性（completed session+payment ↔ settled gross → MATCHED）；Stripe stub（PI/Charge/BT 对象）。read-only 强证（不发 mutation、不建记录）。
- 回归：P4-1~5 specs（financial_facts/financial_ledger/payments/transactions/allocations）+ stripe gem specs + P0-P3 → 0 failures；全量 backend-rspec（coverage-gate）。
- AC 映射：AC-4P6-01~11 → 上述 spec + 回归（spec 内 `AC-4P6-xx` 标注）。

## 9. 文档同步清单（知识同步门）

- [ ] `ai/skills/pallastrade-payments/SKILL.md`：补 Source Reconciliation 章节（ReconcilePayment/Refund + SourceResult + fetch_refund_details 契约 + status/reason 语义）。
- [ ] `harness/scenarios/scenarios.json`：新增 GS-055（source reconciliation 场景）。
- [ ] 本 PRD 状态 + `docs/prd/README.md` 索引。
- [ ] API/schema：不涉及。

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-06 | 0.1 | 初稿：FIN-P4-6 Source Reconciliation 拆包 PRD（P4 §62/§36-37/§39-44/AC-4018-4024 + FIN-P4-5 provider 明细复用；SourceResult VO + ReconcilePayment/ReconcileRefund + provider fetch_refund_details（Stripe/Bogus）+ capability；无 migration，结果不落表归 P4-7/8） | AI |
| 2026-09-06 | 0.2 | 实施完成：SourceResult/ReconcilePayment/ReconcileRefund + PaymentMethod#fetch_refund_details（Stripe retrieve_refund/re_ → Refund cents→元 + Bogus 确定性替身）；新 24 specs + 回归 core 202/stripe 59 0 failures；skills §Source Reconciliation + scenarios GS-055 同步（修复 symbol vs 字符串常量谓词坑） | AI |
