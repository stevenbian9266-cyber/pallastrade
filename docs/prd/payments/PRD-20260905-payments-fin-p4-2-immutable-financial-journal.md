# FIN-P4-2：Immutable Financial Journal —— CommerceTransaction 级不可变资金账本（P4 拆包第 2 包）

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-05 |
| 来源 | 用户任务：「继续拆」——按 P4 V2 拆包顺序推进（用户已确认范围 P4-1~P4-4、拆包推进）。FIN-P4-1（Financial Fact Resolution）已 done（GATE-2026-09-05T16-26-02 finished）；本包 = FIN-P4-2 Immutable Financial Journal |
| 分类 | payments（CLI 自动判定误归 platform，AI 语义微调回 payments——记录在案，符合 PRD 分类语义微调约定） |
| 关联 Skill | `ai/skills/pallastrade-payments/SKILL.md`、`ai/skills/pallastrade-data-model/SKILL.md`、`ai/skills/pallastrade-testing/SKILL.md` |
| 关联 REQ | REQ-20260906-fin-p4-2.md（实施时回填） |
| 关联 PRD | 上游：`豆包梳理业务需求/P4 — Transaction Financial Ledger & PSP Reconciliation Foundation.md`（V2；Journal 规格见其 §8/§10/§11/§13/§43/§56，编号顺延 FIN-P4-2）；前序：`PRD-20260905-payments-fin-p4-1-*`（Financial Fact Resolution，done） |
| 需求类型 | 新功能（不可变资金账本基础设施，含 migration） |

> V2 顺序：FIN-P4-1 Financial Fact Resolution ✅ → **FIN-P4-2 Immutable Financial Journal（本包）** →
> FIN-P4-3 Payment/Refund Posting → FIN-P4-4 Allocation Integrity → FIN-P4-5~8 PSP Reconciliation / Ops。
>
> **关键约束（P4-1 已冻结）**：本包 Journal **只接收 FIN-P4-1 的 `PallasTrade::FinancialFact` 作为 posting 输入**
> ——禁止重新从 `payment.completed?` / provider-specific 判定生成 posting（FR-4P1-40 / FIN-INV-02）。

---

## 1. 背景与目标

- **一句话需求原文**：继续 P4 拆包——实现 CommerceTransaction 级不可变资金账本（FinancialLedgerEntry + 幂等 Posting + Reversal/Correction）。
- **背景**：
  - FIN-P4-1 已落地标准资金事实语义层（FinancialFact + Resolvers + CaptureEvidencePolicy），但**事实仍散落在可变行**（Payment.state、PaymentSplit、Order totals）——没有不可变、可重放、可审计的账本流水。
  - P4 文档 §8/§66（FIN-INV-01/07）：Ledger 必须 append-only；错误用 reversal/correction 追加，禁止原地改历史。
  - P4 文档 §72 纪律：FIN-P4-0 审计（2026-09-05 完成）→ 才允许建 Journal；V2 下该审计已由 FIN-P4-1 落地，本包进入 Journal 建表。
- **目标**：
  - 新增 `financial_ledger_entries` 表与 `PallasTrade::FinancialLedgerEntry` 模型（不可变、commerce_transaction ownership、source identity、幂等、reversal/correction）。
  - `PallasTrade::FinancialLedger::{Post, Reverse}` 幂等原语：Post 接受 FIN-P4-1 `FinancialFact`，只读消费、不重复 posting。
  - 本包**不接业务接线**（Payment 完成事件→posting 在 FIN-P4-3）、不接 PSP（fee/net/settlement 留 FIN-P4-5）。
- **成功指标**：本包 AC-4P2-* 全绿；P0-P3 + FIN-P4-1 specs 零回归（新增 financial_facts 56 + 全量 backend-rspec 0 failures 保持）。

## 2. 用户故事 / 场景

- 作为支付工程/财务，我希望每笔 CommerceTransaction 的资金事实进入不可变账本，以便审计追溯、重放与未来对账（P4 §71 Definition of Done）。
- 场景（本包只测 Journal 原语 + 幂等 + reversal；业务接线 P4-3 起）：

| # | 场景 | 类型 | 描述 |
|---|---|---|---|
| S1 | Post 首笔 | 正常 | 将一笔 CONFIRMED `CASH_CAPTURED` FinancialFact post 到 Journal → 一条 entry |
| S2 | Post 幂等重放 | 边界 | 同一 idempotency_key 再次 post → 返回既有 entry，不重复 |
| S3 | Post 并发 | 边界 | 并发同 key → DB 唯一约束兜底，仅 1 条 |
| S4 | 不可变 | 异常 | 尝试 update amount/currency/source/entry_type/ownership → ImmutableError |
| S5 | Reversal | 异常 | 原 +100 有误 → reverse 生成 -100（reversal_of 指向原），原 entry state=reversed |
| S6 | Reverse 重复 | 异常 | 已 reversed 的 entry 不能再被冲销 |
| S7 | 非 CONFIRMED 拒绝 | 异常 | AMBIGUOUS/UNSUPPORTED/无 ownership 的 fact 不可 post |

## 3. 功能需求（FR）

- FR-4P2-01：新增 `financial_ledger_entries` 表 + `PallasTrade::FinancialLedgerEntry` 模型（`has_prefix_id :fle`；SingleStoreResource 视需要）。列冻结见 §7；`commerce_transaction_id`/`currency`/`amount`/`entry_type`/`effective_at`/`idempotency_key` 必填。
- FR-4P2-02：Entry Type 常量与 FIN-P4-1 `FinancialFact::FACT_TYPES` 对齐（同名单常量）：激活 `CASH_CAPTURED / STORE_CREDIT_APPLIED / OFFLINE_PAYMENT_RECORDED / REFUND_SUCCEEDED`；`ORDER_ALLOCATION` 常量**预留不激活**（FIN-P4-4 启用）；`PSP_FEE / PSP_NET_SETTLEMENT` 预留不激活（FIN-P4-5）。白名单校验。
- FR-4P2-03：不可变性（append-only，FIN-INV-01）——amount/currency/各 source FK/entry_type/commerce_transaction_id/effective_at 创建后禁止原地修改，抛 `FinancialLedgerEntry::ImmutableError`；只允许 reversal 状态流转（posted→reversed + reversed_at）。
- FR-4P2-04：Reversal/Correction（FIN-INV-07）——`FinancialLedger::Reverse`：生成 amount 相反、`reversal_of_id` 指向原 entry 的新 entry；原 entry state→reversed；已 reversed 的 entry 不能再次作为 reversal 目标；同一原 entry 至多一条有效 reversal。
- FR-4P2-05：幂等 Posting 原语 `PallasTrade::FinancialLedger::Post`——输入 **`PallasTrade::FinancialFact`** + 可选显式 `idempotency_key`（缺省由 fact 派生 `fact_posting_key`）。先查 key → 命中返回既有；未命中 insert；`RecordNotUnique` rescue 后重查返回（复用 PaymentWebhookEvent.create_unique / PaymentSession.find_or_create_payment! 既有模式）。
- FR-4P2-06：Posting 门禁——仅 `postable_cash_fact?`（fact_type ∈ 激活集 且 status=CONFIRMED）且 `commerce_transaction_id` 可解析的 fact 可 post；AMBIGUOUS/UNSUPPORTED/NONE/无 txn → failure（不猜测、不产生部分记录）。
- FR-4P2-07：Posting Identity（P4 §13）——`idempotency_key` 唯一约束 + 规范化派生辅助 `FinancialLedgerEntry.fact_posting_key(fact)`（例如 `fact:{fact_type}:{commerce_transaction_id}:{payment_id|refund_id}:{effective_at}`，保证同一资金事实重放不重复）。
- FR-4P2-08：命名纪律（P4 §12 / FR-4P1-24）——列/关联一律 `commerce_transaction_id`；source 引用规范化（`payment_id/refund_id/payment_combination_id/payment_split_id/order_id` 取 fact 的 prefixed id）；无新增含糊 `transaction_id`。
- FR-4P2-09：只读查询辅助——`by_transaction`、`active`（未 reversed）、按 entry_type/时间过滤；不引入 TransactionFinancialSummary（FIN-P4-3/4 接线后由后续 projection 承担，避免空转）。
- FR-4P2-10：本包范围外明确不建：不接 Payment/Refund 事件挂钩（P4-3）；不建 PSP fee/net/settlement 字段语义（列可为空预留，P4-5 填）；不加 API/UI；不改 P0-P3/P4-1 任何既有行为。

## 4. 非功能需求（NFR）

- 并发：`idempotency_key` UNIQUE 为最终防线，Post 必须消化 `RecordNotUnique` 竞态（不 500）。
- 性能：索引覆盖 `(commerce_transaction_id, entry_type)`、`idempotency_key`(UNIQUE)、`reversal_of_id`、各 source FK（payment_id/refund_id/payment_combination_id/payment_split_id/order_id）。
- 金额精度：`amount` 为带符号 decimal（+收款 / -退款/冲销；与 FIN-P4-1 fact 一致方向），`currency` 独立字符串列（对齐 settlement currency invariant）；不用 Float。
- 可维护性：模型注释 PALLAS-CUSTOM + PRD 标记（对齐 TXN-P2/FIN-P4-1 惯例）；entry_type 常量集中。
- 迁移纪律：core 引擎 migration **必须复制到 `backend/db/migrate/`**（引擎 install:migrations 机制；只放 gem 目录 → `db:migrate:status` 看不到）。类名 acronym 匹配（`CreatePallasTradeFinancialLedgerEntries`）。
- 兼容：无 API 变更、无既有表修改（纯新增表）。

## 5. 验收标准（AC，与测试一一映射）

> 对齐 P4 §65 全局 AC 中 Journal 基础设施相关（AC-4002/4003/4004/4012/4018 精神）与 §66 INV-01/02/07/09/12。

- AC-4P2-01 ← FR-4P2-01：FinancialLedgerEntry 可创建；commerce_transaction/currency/amount/entry_type/effective_at 缺失校验失败；source FK 均可不填。
- AC-4P2-02 ← FR-4P2-02：激活 entry_type 可写；`ORDER_ALLOCATION/PSP_FEE/PSP_NET_SETTLEMENT` 未激活拒绝。
- AC-4P2-03 ← FR-4P2-03 / P4 AC-4003：创建后 update amount/currency/source/entry_type/ownership/effective_at → ImmutableError 且 DB 值不变。
- AC-4P2-04 ← FR-4P2-04 / P4 AC-4004 / INV-07：reverse 生成相反符号新 entry + 原 entry state=reversed + `active` 不再含原 entry；原 entry 字段未被修改。
- AC-4P2-05 ← FR-4P2-04：已 reversed entry 不能再冲销；同一原 entry 至多一条有效 reversal（INV-09）。
- AC-4P2-06 ← FR-4P2-05 / P4 AC-4002：同一 fact（同 idempotency_key）连续 Post N 次 → 1 条 entry，返回同一实例。
- AC-4P2-07 ← FR-4P2-05：并发同 key Post → 唯一约束兜底仅 1 条落库，无 500。
- AC-4P2-08 ← FR-4P2-06：非 CONFIRMED（AMBIGUOUS/UNSUPPORTED/NONE）或无 txn fact → Post failure，不产生任何记录。
- AC-4P2-09 ← FR-4P2-07：fact_posting_key 对同一资金事实稳定、跨 source/fact 唯一。
- AC-4P2-10 ← FR-4P2-08：schema/模型/服务无含糊 `transaction_id` 引用（grep 验证）；统一 `commerce_transaction_id`。
- AC-4P2-11 ← FR-4P2-09：by_transaction/active 查询正确（含 reversal 过滤）。
- AC-4P2-12 ← FR-4P2-10：本包无 Payment/Refund 事件挂钩、无 PSP 字段写入、无 API/UI。
- AC-4P2-13：P0-P3 baseline 回归全绿（含 FIN-P4-1 financial_facts specs）。

## 6. 跨层搜索记录（6 层，gate 强制）

搜索关键词：`financial ledger / journal / FinancialLedgerEntry / ledger_entry / posting / reversal / 资金账本`。

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | ledger/journal | 无（app 层无 services/models 复制） | 否，无需新建 |
| Core | `pallastrade_gems/pallastrade_core/app/` | FinancialLedgerEntry/ledger/journal/posting | 全库 grep 0 命中（FIN-P4-1 后复核）；`FinancialFacts::*` 已存在（fact contract） | **否 → 本包在 core 新建 Journal** |
| API | `pallastrade_gems/pallastrade_api/app/` | ledger/financial | 无 | 否（不加端点） |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | financial/ledger | transactions show = trace 读模型，无 financial 视图 | 否（FIN-P4-8） |
| Storefront | `storefront/src/` | ledger/financial | 无 | 否 |
| Platform | `platform/packages/` | ledger/financial | 无 | 否 |
| DB | `backend/db/schema.rb` | financial_ledger/journal | 无相关表 | 否 → 新建 migration |

**结论**：6 层 + schema 均无 ledger/journal 实现（FIN-P4-1 已建 FinancialFact VO/Resolvers——是 Journal 的**输入 contract**，非 Journal 本身）。本包在 **pallastrade_core 新建** `financial_ledger_entries`（模型+migration+服务），无重复能力。复用模式：幂等 = `PaymentWebhookEvent.create_unique` / `PaymentSession#find_or_create_payment!`；不可变值对象 = `FinancialFact#freeze`；prefix = `has_prefix_id :txn`（CommerceTransaction）。

## 7. 技术影响

- **新建（core gem）**：
  - `backend/pallastrade_gems/pallastrade_core/app/models/pallastrade/financial_ledger_entry.rb`（模型 + ImmutableError + state + 常量 + posting_key 辅助）
  - `backend/pallastrade_gems/pallastrade_core/db/migrate/<ts>_create_pallastrade_financial_ledger_entries.rb`（引擎迁移 → **同步复制 backend/db/migrate/**）
  - `backend/pallastrade_gems/pallastrade_core/app/services/pallastrade/financial_ledger/post.rb`、`.../reverse.rb`
- **表结构冻结**（P4 §11 裁剪：去掉 polymorphic source 冗余，显式 source FK 保引用完整性；source 实体 = payment/refund/payment_combination/payment_split/order，与 P4-1 fact contract 对齐）：

```text
pallastrade_financial_ledger_entries
  id, prefixed_id (has_prefix_id :fle)
  commerce_transaction_id   NOT NULL FK -> commerce_transactions   （P4 §12 命名纪律）
  order_id / payment_id / refund_id /
  payment_combination_id / payment_split_id   nullable FK
  entry_type                NOT NULL（白名单常量，与 FinancialFact::FACT_TYPES 对齐）
  amount                    NOT NULL decimal(10,2)（带符号）
  currency                  NOT NULL string(ISO)
  idempotency_key           NOT NULL string, UNIQUE
  reversal_of_id            nullable FK self
  state                     NOT NULL default 'posted'（posted|reversed）
  effective_at              NOT NULL（资金事实发生时间 = fact.effective_at）
  recorded_at               NOT NULL（本地记录时间，DB 默认 now）
  provider / provider_reference  nullable（FIN-P4-5 填，本包不写）
  metadata                  jsonb default {}
  reversed_at               nullable
  created_at / updated_at
```

- **既有能力影响面**：不改 P0-P3/P4-1 任何行为；不改 Payment/Refund/PaymentSplit/OrderUpdater。`harness affected` 预期：core 新增 + schema.rb + backend/db/migrate 新增。
- **无 API/接口变更**：不加 controller/routes/serializer；不动 store/admin yaml；不触发 SDK 类型。
- **命名空间**：模型 `PallasTrade::FinancialLedgerEntry`；服务 `PallasTrade::FinancialLedger::{Post, Reverse}`。

## 8. 测试计划

- 新增测试文件（backend/spec，core gem 测试挂 host）：
  - `backend/spec/models/pallastrade/financial_ledger_entry_spec.rb` —— AC-4P2-01/02/03/09/10/11（创建/校验/白名单/不可变/posting_key/命名/查询）
  - `backend/spec/services/pallastrade/financial_ledger/post_spec.rb` —— AC-4P2-06/07/08（幂等重放/并发/门禁）
  - `backend/spec/services/pallastrade/financial_ledger/reverse_spec.rb` —— AC-4P2-04/05（reversal 语义/重复保护）
- 每个测试头部标注 `# PRD-20260905-payments-fin-p4-2 AC-4P2-xx`。
- fixture/fact 构造：复用 FIN-P4-1 Resolvers 产物或直接构造 CONFIRMED FinancialFact（payment capture 走真实 confirm!/capture! 路径，遵守 capture critical-path 规则）。
- 回归：`financial_facts` specs（56）+ transactions/payments 关键（92）+ 全量 backend-rspec verifier（coverage-gate 依据，参照 P4-1 先例）。
- AC 映射：AC-4P2-01~13 → 三个新 spec + 回归。

## 9. 文档同步清单（知识同步门）

- [ ] `ai/skills/pallastrade-payments/SKILL.md`：新增 Immutable Financial Journal 章节（FinancialLedgerEntry、Post/Reverse 幂等原语、reversal/correction、posting input = FinancialFact）。
- [ ] `ai/skills/pallastrade-data-model/SKILL.md`：登记新表 `pallastrade_financial_ledger_entries` + ownership 图。
- [ ] `harness/scenarios/scenarios.json`：新增 GS-051（Journal posting 幂等 + reversal 场景）。
- [ ] README / AGENTS：本包不新增规范文件/反模式，评估后记录。
- [ ] 本 PRD 状态更新 + `docs/prd/README.md` 索引。
- [ ] `backend/db/schema.rb` 自动更新（migration 后生成，禁止手改）。
- [ ] API 文档：不涉及。

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-06 | 0.1 | 初稿：FIN-P4-2 Immutable Financial Journal 拆包 PRD（P4 需求文档 §8/§10/§11/§13/§43/§56 + FIN-P4-1 完成态 + V2 posting input = FinancialFact 约束） | AI |
| 2026-09-06 | 0.2 | 实施完成（TASK-20260905174733-43a78f7a / GATE-2026-09-05T17-47-48 finished）：迁移 20260906000001（financial_ledger_entries + partial UNIQUE）+ FinancialLedgerEntry（append-only/ImmutableError 双层拦截）+ FinancialLedger::{Post,Reverse}；新增 22 examples + 回归 148 + 全量 backend-rspec 0 failures；knowledge（skills GS-051）同步 | AI |
