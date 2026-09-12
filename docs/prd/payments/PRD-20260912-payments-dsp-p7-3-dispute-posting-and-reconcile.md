# PRD-20260912-payments-dsp-p7-3-dispute-posting-and-reconcile（争议退款资金入账与对账）

| 元数据 | 值 |
|---|---|
| 状态 | done（2026-09-12 实施 / 验证 / 知识同步完成；待提交） |
| 创建日期 | 2026-09-12 |
| 来源 | 用户指令「完成全部收尾」→ 承接 DSP-P7-0 / P7-1 / P7-2 的下一切片（P7-2 PRD 已显式预留） |
| 分类 | payments（`harness prd new` 自动判定，关键词「退款」命中；查重命中 FIN-P4-3 仅词汇重合，非重复需求） |
| 关联 Skill | `pallastrade-payments`、`pallastrade-data-model`、`pallastrade-customization`、`pallastrade-testing` |
| 关联 REQ | `REQ-20260912-dsp-p7-3-dispute-posting-and-reconcile.md`（待创建） |
| 关联 PRD | `PRD-20260911-payments-dsp-p7-0-dispute-semantic-audit-and-data-model-freeze.md`（语义冻结）、`-p7-1-durable-dispute-model-and-provider-event-ingestion.md`（模型与入口）、`-p7-2-dispute-fact-resolution.md`（事实裁决层）、`PRD-20260906-payments-fin-p4-1/2/3`（FinancialFact / Journal / Payment+Refund posting） |
| 需求类型 | 新功能（资金事实入账 + 只读对账；含 1 个 migration、0 个 API/UI 变更） |

> **切片定位（P7-2 PRD 原文预留）**：P7-2 只做「事实裁决层」，明确「**不做**：Journal/Entry 激活（P7-3）」。
> 本切片 = 把已冻结的争议资金事实**激活到不可变 Journal**（`PostDispute`）并落地**只读对账**（`ReconcileDispute`）。
> **不做**：Evidence 取证（P7-4）、Sweeper 自动补记（P7-5）、Recovery 收敛动作（P7-6）、Admin Console（P7-7）、多 provider 实现（P7-8）。

---

## 1. 背景与目标

- **一句话需求原文**：「完成全部收尾」→ 推进 P7 线下一包（DSP-P7-3）。
- **背景**：
  1. **事实已冻结、账本未激活**：P7-2 交付 `Disputes::DisputeFact`（5 个事实类型：`DISPUTE_OPENED` /
     `DISPUTE_FUNDS_WITHDRAWN` / `DISPUTE_FUNDS_REINSTATED` / `DISPUTE_WON` / `DISPUTE_LOST`）与
     `Disputes::ResolveFact` 裁决，但 `FinancialFact::FACT_TYPES` 与 `FinancialLedgerEntry::ENTRY_TYPES`
     中**没有任何 DISPUTE_\* 类型**（已核实：`financial_fact.rb:24`、`financial_ledger_entry.rb:23`）。
  2. **资金事实无法追溯**：`charge.dispute.funds_withdrawn` / `funds_reinstated` 落到
     `PaymentWebhookEvent.action` + `dispute.funds_*_at`，但**不产生 Journal entry** —— P4「所有金融事实可追溯」目标
     在争议域**未闭环**；审计/对账无法回答「这笔扣款/返还进了哪条账」。
  3. **无幂等键位**：`FinancialLedgerEntry.fact_posting_key` 的来源优先级为
     `refund > payment > combination > split > order > txn`（`financial_ledger_entry.rb:88`）——
     同一 payment 的两笔争议（同秒）会派生出**相同 key**，存在**错误去重**风险。
  4. **无对账能力**：`Reconciliations::` 命名空间只有 `ReconcilePayment` / `ReconcileRefund` /
     `ReconcileTransaction` + `ReconcileSweeperJob`（已核实），争议域无对应只读对账。
- **目标**：
  1. **激活现金事实**：`DISPUTE_FUNDS_WITHDRAWN` / `DISPUTE_FUNDS_REINSTATED` 两个**现金**类型激活为
     `ENTRY_TYPES`；`DISPUTE_OPENED` / `DISPUTE_WON` / `DISPUTE_LOST` 三个**非现金**类型仅激活为
     `FACT_TYPES`（事实词汇），**不产生 ledger entry**（防双记，FIN-INV-05 精神）。
  2. **可追溯**：`pallastrade_financial_ledger_entries` 增加 `dispute_id`，`fact_posting_key` 增加 dispute 分支，
     争议资金行可直连 dispute 主体（P4 §12 命名纪律：entry 与资金事实类型**同名单对齐**）。
  3. **恰好一次**：`PostDispute` 编排（复用 `Post` 幂等原语），重复 webhook / 重试 / replay 不重复入账。
  4. **只读对账**：`Reconciliations::ReconcileDispute` 返回结构化分类（含 `journal_missing` /
     `amount_mismatch` / `orphan_entry`），**零写、零 provider I/O**（为 P7-5 sweeper、P7-6 收敛提供输入）。
  5. **零行为回归**：不触碰 Payment / Refund / Transaction / Dispute 状态机与既有 posting 链路。
- **成功指标**（可验证）：
  1. 现金争议事实 → **恰好 1 条**对应 entry（重复触发仍 1 条）；
  2. `won` 争议净额为 0（withdrawn + reinstated 在同一 currency 下抵消）；
  3. 非现金/不可证事实 → **0 条 entry** 且 skip reason 为封闭枚举；
  4. `ReconcileDispute` 五类分类各自可断言，调用前后 DB 行数不变（只读快照断言）；
  5. 回归：`p0-payment-rspec` + FIN-P4 全链 + P7-1/P7-2 specs 全绿；`harness generated:check` / `doc-impact` 通过。

## 2. 用户故事 / 场景

- 作为**财务**：我希望争议扣款/返还自动、恰好一次进入不可变账本，以便月末对账与审计能直接按 dispute 追溯。
- 作为**平台运维**：我希望知道「某争议的资金事实是否已入账、金额是否一致、有没有孤儿账行」，而不需要手工比对。
- 作为**开发**：我希望争议入账与既有 `PostPayment` / `PostRefund` 完全同构（Resolve → 门禁 → Post），可直接复用既有模式与测试骨架。

| # | 场景 | 类型 | 描述 |
|---|---|---|---|
| S1 | 提款（chargeback 发起） | 正常 | dispute 状态含 `funds_withdrawn_at` 且 CONFIRMED → 1 条 `DISPUTE_FUNDS_WITHDRAWN`（金额为负） |
| S2 | 返还（争议胜诉） | 正常 | `funds_reinstated_at` 存在且 CONFIRMED → 1 条 `DISPUTE_FUNDS_REINSTATED`（金额为正）；净额 0 |
| S3 | 重复 webhook / job 重试 / replay | 边界 | 同一 dispute + 同一事实重复触发 → 仍 1 条（幂等键稳定） |
| S4 | 同 payment 多争议 | 边界 | 两笔不同 dispute（同秒）→ **各自独立 entry**（旧 key 会误去重，本切片修复） |
| S5 | 非现金事实 | 边界 | `DISPUTE_OPENED` / `WON` / `LOST` → 0 条 entry，`reason=entry_type_not_activated` |
| S6 | provider 不可证 | 异常 | `AMBIGUOUS` / `UNSUPPORTED`（如 Adyen/PayPal 无 dispute 取证能力）→ 0 条 entry，**不猜** |
| S7 | 关键字段缺失 | 异常 | 无 `commerce_transaction` / 金额或币种缺失 / `funds_*_at` 缺失 → skip + 明确 reason（不产生部分记录） |
| S8 | 入账失败 | 异常 | `Post` 硬失败 → dispute 事实**不受影响**（异步 job 可重试，日志留痕） |
| S9 | 只读对账 | 正常 | `ReconcileDispute` 分类：`aligned` / `journal_missing` / `amount_mismatch` / `orphan_entry` / `not_applicable` |
| S10 | 对账无损 | 边界 | 调用 `ReconcileDispute` 前后：entry/dispute/payment 行数与状态**完全不变** |

## 3. 功能需求（FR）

- **FR-P73-01**：`PallasTrade::FinancialFact::FACT_TYPES` 增加 5 个事实类型（与 `Disputes::DisputeFact::FACT_TYPES`
  **同名单**）：`DISPUTE_OPENED` `DISPUTE_FUNDS_WITHDRAWN` `DISPUTE_FUNDS_REINSTATED` `DISPUTE_WON` `DISPUTE_LOST`；
  `FinancialFact::ATTRIBUTES` 增加 `dispute_id`。
- **FR-P73-02**：`PallasTrade::FinancialLedgerEntry::ENTRY_TYPES` **只激活 2 个现金类型**
  （`DISPUTE_FUNDS_WITHDRAWN` `DISPUTE_FUNDS_REINSTATED`）；其余 3 个**保持未激活**（不进入 `ENTRY_TYPES`，也不进
  `RESERVED_ENTRY_TYPES` 的 PSP 预留位；以常量注释记录「非现金事实，永不入账」的依据）。
- **FR-P73-03**：新增 migration —— `pallastrade_financial_ledger_entries.dispute_id`（bigint，nullable，索引）；
  按 data-model SKILL §Immutable Financial Journal 的行文约定放 `backend/db/migrate/`（FIN-P4-2 先例）；
  `FinancialLedgerEntry` 增加 `belongs_to :dispute, optional: true` 与 `dispute_id` 到 `IMMUTABLE_ATTRIBUTES`。
- **FR-P73-04**：`FinancialLedgerEntry.fact_posting_key` 增加 **dispute 最高优先级分支**，产出
  `fact:<fact_type>:<txn_id>:dispute:<dispute_id>:<effective_at>`；无 dispute 时行为**逐字节不变**（回归保护）。
- **FR-P73-05**：新增 `PallasTrade::FinancialFacts::ResolveDispute.call(dispute:, fetch: false, fact_type: nil)`：复用
  `Disputes::ResolveFact`（只读）→ 映射为 `FinancialFact`（P4 §16 契约：Journal 只消费 `FinancialFact`）。映射规则：
  `PSP_CASH`（现金两类）/ `UNKNOWN`（非现金三类）；`effective_at` = `funds_withdrawn_at` / `funds_reinstated_at`（无 fallback）；
  `provider_reference` 取 dispute 的 provider 引用（含 `provider_dispute_reference`）；不可判 → `status=AMBIGUOUS`。
  **事件作用域提示（实施精化，见 §10）**：`fact_type:` 可显式指定本次入账对应的现金事实（subscriber 按事件名传入），
  用于避开 P7-2 的**终态优先**（`won`/`lost` 覆盖 funds 时间戳）导致的资金缺口；不传时保持 P7-2 语义。
- **FR-P73-06**：新增 `PallasTrade::FinancialLedger::PostDispute.call(dispute:, fact_type: nil)`（编排，与 `PostRefund` 同构）：
  `ResolveDispute` → `Post.postable?` 门禁 → `Post`；返回
  `success({ entry:, fact:, skipped:, reason: })` 或 `failure(fact, message)`。**不创建/不更新 Dispute/Payment/Transaction**。
  `skip_reason` 判定提升为**类方法** `PostDispute.skip_reason_for(fact)`，供 `ReconcileDispute` 复用（入账与对账同口径）。
- **FR-P73-07**：skip reason 为封闭枚举（与 `PostRefund#skip_reason` 对齐并扩展）：
  `fact_status_not_confirmed` / `entry_type_not_activated` / `commerce_transaction_missing` /
  `amount_or_currency_missing` / `effective_at_missing` / `not_postable`。
- **FR-P73-08**：金额方向约定 —— `DISPUTE_FUNDS_WITHDRAWN` 记**负数**（资金流出），`DISPUTE_FUNDS_REINSTATED` 记**正数**
  （资金流入）；同一 dispute 两者之和为 0（币种一致时）。常量注释 + spec 断言。
- **FR-P73-09**：接线 —— `PallasTrade::Dispute` 增加 after_commit 生命周期事件发布（`dispute.funds_withdrawn` /
  `dispute.funds_reinstated`，仅当对应 `funds_*_at` 由空变非空时发布，幂等）；新增
  `FinancialLedger::DisputeFundsSubscriber`（订阅二者）→ `PostDispute`；subscriber 默认 async（SubscriberJob），
  异常 rescue 记录日志、**不阻断**争议落库；注册到 `pallastrade_core/lib/pallastrade/core/engine.rb` 的
  subscribers.concat（与 `PaymentPaidSubscriber` 同列）。
- **FR-P73-10**：新增 `PallasTrade::Reconciliations::ReconcileDispute.call(dispute:)`（**只读**）：返回
  `ServiceModule::Result`，含 `classification`（`aligned` / `journal_missing` / `amount_mismatch` /
  `orphan_entry` / `not_applicable`）、`reasons[]`、`expected_entries[]`、`entries[]`、`skip_reason`、`capability`；
  **零 provider I/O、零写**。
  **期望模型（实施精化，见 §10）**：期望账行 = **funds 时间戳集合**（`funds_withdrawn_at` → 期望一条 withdrawn、
  `funds_reinstated_at` → 期望一条 reinstated），**不是**「当前最强事实」——否则已 `won` 的争议（事实=非现金）会被误判缺账。
- **FR-P73-11**：边界（明确不做，避免范围蔓延）——无 migration 之外的结构变更、无 API/UI、无 provider 网络调用、
  无 sweeper 自动补记（P7-5）、无收敛动作（P7-6）、无历史 backfill（P4 §44 口径）。
- **FR-P73-12**：不改既有行为 —— `PostPayment` / `PostRefund` / `PostAllocation` / `Reverse` /
  `ReconcilePayment` / `ReconcileRefund` / `ReconcileTransaction` 代码路径零改动（除
  `FinancialLedgerEntry::IMMUTABLE_ATTRIBUTES` / `fact_posting_key` 的**追加式**扩展）。

## 4. 非功能需求（NFR）

- **幂等性**：`idempotency_key` 唯一约束（DB 层）+ `fact_posting_key` 稳定派生；重复触发不产生第二条 entry。
- **事务边界**：posting 在 dispute 落库**提交之后**、**独立事务**内执行（事件 after_commit + subscriber job），
  失败不回滚资金事实（P4 §16）。
- **只读边界**：`ResolveDispute` / `ReconcileDispute` 零写；`PostDispute` 唯一写 = `FinancialLedgerEntry`。
- **可审计**：entry 携带 `dispute_id` + `provider_reference` + `effective_at`；skip 一律留 reason（不静默）。
- **性能**：单 dispute 解析固定查询数（无 N+1）；对账不触发 provider 网络（index/列表路径零 I/O）。
- **兼容**：无 API/SDK/UI 变更 → `generated:check` 应无差异；Schema 追加 nullable 列（历史行不受影响）。
- **可维护**：与 FIN-P4-3 同构（Resolve → 门禁 → Post），复用既有 service/spec 骨架与命名纪律。

## 5. 验收标准（AC，与测试一一映射）

- **AC-P73-01 ← FR-P73-06/08**：CONFIRMED 的 `funds_withdrawn` 事实 → 恰好 1 条 entry，
  `entry_type=DISPUTE_FUNDS_WITHDRAWN`、`amount<0`、`state=posted`、`dispute_id` 指向该 dispute。
- **AC-P73-02 ← FR-P73-04/06**：同一 dispute 重复 `PostDispute`（模拟重复 webhook / job 重试）→ entry 总数仍 1，
  第二次返回 `skipped: false` 且 `entry` 为同一行（幂等命中）。
- **AC-P73-03 ← FR-P73-04/08**：同一 payment 下两笔不同 dispute（同秒、同金额）→ **2 条独立 entry**（修复旧 key 误去重）。
- **AC-P73-04 ← FR-P73-01/05/06**：`won` 争议（withdrawn + reinstated 均 CONFIRMED）：带事件提示入账 → withdrawn 负值 +
  reinstated 正值两条、净额 0；**不带提示**（当前最强事实 `DISPUTE_WON`）→ `skipped: true` /
  `reason=entry_type_not_activated` 且**不产生第 3 条 entry**。
- **AC-P73-05 ← FR-P73-02/07**：`DISPUTE_OPENED` / `DISPUTE_WON` / `DISPUTE_LOST` → 0 条 entry 且
  `reason=entry_type_not_activated`。
- **AC-P73-06 ← FR-P73-05/07**：`AMBIGUOUS`（provider 不可证）/ `UNSUPPORTED`（provider 无能力）→ 0 条 entry 且
  `reason=fact_status_not_confirmed`；**无部分记录**。
- **AC-P73-07 ← FR-P73-07**：无 `commerce_transaction` → `commerce_transaction_missing`；金额或币种缺失 →
  `amount_or_currency_missing`；`funds_*_at` 缺失 → `effective_at_missing`。
- **AC-P73-08 ← FR-P73-06/12**：posting 前后 Dispute / Payment / Transaction / CommerceTransaction 的
  属性与行数**完全不变**（快照断言）。
- **AC-P73-09 ← FR-P73-09**：发布 `dispute.funds_withdrawn` 事件（或直接执行 subscriber）→ 产生 entry；
  dispute 落库回滚时**不产生** entry（事务边界断言）。
- **AC-P73-10 ← FR-P73-10**：`ReconcileDispute` 五类分类各自可断言（`aligned` / `journal_missing` /
  `amount_mismatch` / `orphan_entry` / `not_applicable`），`won`+双账行场景判 `aligned`（终态不误报），
  且调用前后 DB 行数与 dispute 属性不变（只读断言）。
- **AC-P73-11 ← FR-P73-11/12**：回归 —— FIN-P4 全链（financial_facts / financial_ledger / allocations）+
  P7-1/P7-2 dispute specs 全绿，无既有断言修改（除为 dispute 增加的新用例文件）。
- **AC-P73-12 ← 全局**：`npx harness generated:check` 无差异、`npx harness doc-impact --base origin/dev` 通过、
  `npx harness sync-check --id PRD-20260912-payments-dsp-p7-3-...` 已确认。

## 6. 跨层搜索记录（6 层，gate 强制）

关键词：`dispute` / `chargeback` / `DISPUTE_FUNDS` / `FinancialLedger` / `PostDispute` / `ReconcileDispute` / `fact_posting_key`

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | dispute / ledger | **无命中**（`backend/**` 全域命中仅 gems/specs/log） | ❌ 无既有能力 → 本切片在 gems 层实现（PallasTrade 自身产品线） |
| Core | `backend/pallastrade_gems/pallastrade_core/app/` | 同上 | `models/pallastrade/financial_fact.rb`（FACT_TYPES 无 DISPUTE_*）、`models/pallastrade/financial_ledger_entry.rb`（ENTRY_TYPES 无 DISPUTE_*；`fact_posting_key:88`）、`services/pallastrade/financial_ledger/{post,post_payment,post_refund,post_allocation,post_combination_allocations,allocation_integrity,reverse,repair_transaction}.rb`、`services/pallastrade/reconciliations/{reconcile_payment,reconcile_refund,reconcile_transaction}.rb`、`services/pallastrade/disputes/{dispute_fact,resolve_fact,handle_provider_event,provider_payload}.rb`、`models/pallastrade/dispute.rb`、`models/pallastrade/payment_webhook_event.rb` | ⚠️ 部分：事实层/裁决层已有（P7-2），**入账与对账不存在** → 本切片补 |
| API | `backend/pallastrade_gems/pallastrade_api/app/` | dispute | **无命中** | ❌ 本切片无 API 变更（争议读接口归 P7-7） |
| Admin | `backend/pallastrade_gems/pallastrade_admin/app/` | dispute | **无命中** | ❌ 本切片无 Admin UI（归 P7-7） |
| Storefront | `storefront/src/` | dispute / chargeback | **无命中** | ❌ 不适用（客户侧不感知账本） |
| Platform | `platform/packages/` | dispute / chargeback | 仅 `docs/dist/integrations/payments/adyen.md:129` 说明性文字 | ❌ 无代码能力，本切片无 SDK/类型变更 |

**结论**：无任何一层存在争议入账/对账能力 → 属**新增**（非改已有）；唯一权威落点 = `pallastrade_core`（框架自身产品线，
按 AGENTS §3 优先级 8「直接改 Gem」并加 `# PALLAS-CUSTOM` 注释，与 FIN-P4-x 既有做法一致）。

## 7. 技术影响

- **数据**：1 个 migration（`financial_ledger_entries.dispute_id`，nullable + index）→ `harness check --profile full`。
- **代码**：core gem 新增 2 个 service（`FinancialFacts::ResolveDispute`、`FinancialLedger::PostDispute`）
  + 1 个 subscriber + 1 个 reconciler（`Reconciliations::ReconcileDispute`）+ `Dispute` 事件发布 + 常量/模型追加式扩展。
- **接口**：无 API 路由/serializer 变更 → SDK/OpenAPI 无差异（仍跑 `generated:check` 确认）。
- **兼容**：`fact_posting_key` 追加分支，非 dispute 路径输出不变；`ENTRY_TYPES` 追加 2 项，`inclusion` 校验放宽（无历史行受影响）。
- **回滚**：新列 nullable + 新服务独立；回滚 = revert 代码 + `rails db:rollback` 单步（无数据回填，可安全回退）。
- **风险**：①金额方向记错（用 S1/S2 与净额 0 断言兜住）；②幂等键碰撞（AC-P73-03 断言兜住）；
  ③误把非现金事实入账（AC-P73-05 兜住）；④publish 与 after_commit 的时序（AC-P73-09 兜住）。

## 8. 测试计划（AC ↔ 测试文件）

| AC | 测试文件（新增） | 类型 |
|---|---|---|
| AC-P73-01/02/03/07/08 | `backend/spec/services/pallastrade/financial_ledger/post_dispute_spec.rb` | 单元/服务 |
| AC-P73-04/05/06 | `backend/spec/services/pallastrade/financial_facts/resolve_dispute_spec.rb` | 单元/服务 |
| AC-P73-09 | `backend/spec/subscribers/pallastrade/financial_ledger/dispute_funds_subscriber_spec.rb` | 集成 |
| AC-P73-10 | `backend/spec/services/pallastrade/reconciliations/reconcile_dispute_spec.rb` | 只读断言 |
| AC-P73-11 | 既有 FIN-P4 + P7-1/P7-2 spec 全量回归 | 回归 |
| AC-P73-03 | `financial_ledger_entry_spec`（`fact_posting_key` dispute 分支） | 单元 |

命令：`docker exec pallastrade-web-1 bash -lc "cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec <files>"`；
全量回归 `harness check --profile full`（含 migration 场景）。

## 9. 文档同步清单（实施后必做）

| 资产 | 结论（sync-check 逐项评估） |
|---|---|
| `ai/skills/pallastrade-payments/SKILL.md` | ✅ 已更新：新增 DSP-P7-3 段（现金/非现金口径、方向约定、事件作用域事实、幂等键修复、只读对账）。 |
| `ai/skills/pallastrade-data-model/SKILL.md` | ✅ 已更新：`pallastrade_financial_ledger_entries.dispute_id`（迁移 `20260912000004`、nullable + index、key 碰撞背景）。 |
| `ai/skills/pallastrade-events-webhooks/SKILL.md` | ✅ 已更新：新增「Dispute funds lifecycle」出站事件段（两个事件 + subscriber + after_commit/幂等要点）。 |
| `harness/scenarios/scenarios.json` | ✅ 已更新：新增 **GS-094**（现金事实激活 / 事件作用域事实 / posting key 正确性 / 只读对账）；`eval-ai --scenarios` 95/95。 |
| `docs/prd/README.md` | ✅ 已登记本 PRD 索引行（approved + REQ 关联）。 |
| `ai/skills/pallastrade-testing/SKILL.md` | ⏭ 评估后不更新：沿用既有 rspec 约定与容器执行方式，无新测试模式。 |
| `ai/skills/pallastrade-prd/SKILL.md` | ⏭ 评估后不更新：PRD 流程本身无变化（本次按既有 R8 流程执行）。 |
| `AGENTS.md` / `.github/copilot-instructions.md` | ⏭ 评估后不更新：未新增全局规则、门禁或反模式。 |
| `backend/public/api-docs/*.yaml` / `platform/docs/api-reference/` | ⏭ 评估后不更新：`harness generated:check` 无漂移（本切片无 API/SDK 变更）。 |

## 10. 变更记录

| 日期 | 变更 | 说明 |
|---|---|---|
| 2026-09-12 | 创建（draft） | 承接 P7-2 预留的 P7-3 切片 |
| 2026-09-12 | draft → approved | 用户问答工具选择『确认实施 P7-3』；批准证据已记录；gate `GATE-2026-09-12T05-17-51` preparation 已清 |
| 2026-09-12 | 设计精化（实施中） | ①`ResolveDispute` 增 `fact_type:` **事件提示**：P7-2 终态优先会让已 `won` 争议的 `funds_reinstated` **永不入账**（资金缺口），入账层改按**实际发生的现金事件**解析（不传 hint 保持 P7-2 语义）；②`ReconcileDispute` 改为**期望账行集合**模型（期望 = funds 时间戳集合，而非「当前最强事实」），否则 won 争议会被误判缺账；③AC-P73-04/10 与 FR-P73-05/06/10 同步细化 |
| 2026-09-12 | 实施完成（待验证/提交） | 1 migration（`financial_ledger_entries.dispute_id`）+ `ResolveDispute` + `PostDispute` + `ReconcileDispute` + `DisputeFundsSubscriber` + 常量/模型/subscriber 注册扩展；新增 4 spec（**26 examples 0 failures**）；FIN-P4/P7 域回归 **228 examples 0 failures**；改动文件 rubocop 干净 |
| 2026-09-12 | 验证完成 → done | 注册 verifier `backend-rspec` 全量套件通过（**1515 examples, 0 failures, 6 pending**；EVD-20260912090631-c37f9b15dd）；`sync-check --ack` 知识同步门通过；`doc-impact` / `generated:check` / freshness（0 error）/ scenarios（95/95）全绿；Gate `GATE-2026-09-12T05-17-51` 已关闭 |
| 2026-09-12 | 既有 spec 触碰说明（2 处） | ①`spec/models/pallastrade/financial_fact_spec.rb`：**必须**同步 `FACT_TYPES` 冻结词汇断言（本切片正是向该词汇追加 5 类），并新增「非现金争议事实不得进入 `ENTRY_TYPES`」断言；②`spec/services/pallastrade/transactions/reserve_inventory_spec.rb`：verifier 复跑命中**既有 flaky**（与 P7-3 无关），根因同前次修复——`Store#default_stock_location` 取全局首个 `default: true` 库存点，工厂 stock_item 落在不受控位置导致结果随 DB 状态漂移；修法为把变体 stock_items 收敛到本 spec 显式指定的库存点（两种随机种子各 7/7 稳定）。 |
