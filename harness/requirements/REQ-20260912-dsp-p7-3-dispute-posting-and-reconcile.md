# REQ-20260912-dsp-p7-3-dispute-posting-and-reconcile

> 关联 PRD：`docs/prd/payments/PRD-20260912-payments-dsp-p7-3-dispute-posting-and-reconcile.md`
> 任务：`TASK-20260912051738-248bba99` ｜ Gate：`GATE-2026-09-12T05-17-51`（feature，branch `dev`）

---

## Step 0：跨层搜索（强制执行）

关键词：`dispute` / `chargeback` / `DISPUTE_FUNDS` / `FinancialLedger` / `PostDispute` / `ReconcileDispute` / `fact_posting_key`

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | dispute / ledger | 无命中 | ❌ 无既有能力 |
| App — views/decorators | `backend/app/` | dispute | 无命中 | ❌ |
| Core Gem — models | `.../pallastrade_core/app/models/` | dispute / Fact / Ledger | `dispute.rb`（P7-1 聚合，无事件发布）、`financial_fact.rb`（FACT_TYPES 无 DISPUTE_\*）、`financial_ledger_entry.rb`（ENTRY_TYPES 无 DISPUTE_\*；`fact_posting_key:88`）、`payment_webhook_event.rb`（DISPUTE_ACTIONS） | ⚠️ 事实/模型已有，**入账键位缺失** |
| Core Gem — services | `.../pallastrade_core/app/services/` | Post / Reconcile / Dispute | `financial_ledger/{post,post_payment,post_refund,post_allocation,...}.rb`、`reconciliations/{reconcile_payment,reconcile_refund,reconcile_transaction}.rb`、`disputes/{dispute_fact,resolve_fact,handle_provider_event}.rb` | ⚠️ 模式可复用，`PostDispute` / `ResolveDispute` / `ReconcileDispute` **不存在** |
| API Gem — controllers | `.../pallastrade_api/app/` | dispute | 无命中 | ❌ 本切片无 API 变更 |
| Admin Gem — controllers/views | `.../pallastrade_admin/app/` | dispute | 无命中 | ❌ 本切片无 Admin UI（归 P7-7） |
| Storefront | `storefront/src/` | dispute / chargeback | 无命中 | ❌ 不适用 |
| Platform | `platform/packages/` | dispute / chargeback | 仅 `docs/dist/integrations/payments/adyen.md:129` 说明文字 | ❌ 无代码能力 |

### 搜索结论

- **6 层均无**「争议资金事实入账 / 对账」能力 → 属**新增**（非改已有能力）。
- 唯一权威落点 = `pallastrade_core`（框架自身产品线；AGENTS §3 决策树第 8 级「直接改 Gem」+ `# PALLAS-CUSTOM` 注释，与 FIN-P4-x 既有做法一致）。
- 可复用契约（不重造）：`FinancialFacts::Resolve*`（fact 解析）→ `FinancialLedger::Post.postable?`（门禁）→ `FinancialLedger::Post`（幂等原语）；`Reconciliations::Reconcile*`（只读对账模式）。

---

## Step 1：Skill 文件咨询（强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树：扩展点优先 1–7 级；框架自身产品线允许第 8 级「直接改 Gem」（本切片属 gem 自研产品线，故走第 8 级 + `# PALLAS-CUSTOM` 注释，与 FIN-P4-x 一致） |
| `ai/skills/pallastrade-data-model/SKILL.md` | ✅ 已读 | §Disputes (DSP-P7-1)：`pallastrade_disputes`（`dsp_` 前缀）、唯一 `(provider, provider_dispute_reference)`、**一个 payment 可携带 1:N disputes 与部分金额**（→ 必须修 `fact_posting_key` 碰撞）；§Immutable Financial Journal：`pallastrade_financial_ledger_entries` 迁移放 `backend/db/migrate/`、append-only（`ImmutableError`）、posting 输入 = `FinancialFact` |
| `ai/skills/harness-prd/SKILL.md` | ✅ 已读 | 阶段 0：`harness prd new` 自动分类 + 查重 >0.3 阻止；命中相似 → `prd update` 回写；确属全新才 `--force`（本次命中 FIN-P4-3 仅词汇重合，P7-2 PRD 已显式预留 P7-3 → `--force` 成立） |

**按需 Skill：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-payments` | ✅ | ✅ 已读 | Journal 门禁 = `Post.postable?(fact)` = CONFIRMED + **entry_type 已激活** + 可解析 txn + amount/currency；`PostRefund` 模式 = Resolve → 门禁 → Post，返回 `success({entry:, fact:, skipped:, reason:})`，**不创建/更新业务实体**（只读边界 FR-4P3-09） |
| `pallastrade-testing` | ✅ | ✅ 已读 | `bundle exec rspec <file>` / `:line` 单测；本项目容器内执行 `docker exec pallastrade-web-1 bash -lc "cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec <files>"` |
| `pallastrade-events-webhooks` | ✅ | ✅ 已读（会话内已咨询） | subscriber 一律 `PallasTrade::Subscriber` 子类 + async（`SubscriberJob`）+ rescue 记录；**禁止 `after_save` 回调**（AP-004）→ 接线用 after_commit 事件 + subscriber |
| `pallastrade-api-v3` | ⬜ 否 | — | 本切片无 API 变更 |
| `pallastrade-storefront` | ⬜ 否 | — | 客户侧不感知账本 |

---

## 需求标题

DSP-P7-3：争议退款资金事实**入账**（`PostDispute`）与**只读对账**（`ReconcileDispute`）。

## 任务类型

新功能（1 个 migration，0 API/UI）。

## 需求描述

把 P7-2 冻结的争议资金事实（`DISPUTE_FUNDS_WITHDRAWN` / `DISPUTE_FUNDS_REINSTATED`）激活进不可变 Journal，
使「争议扣款/返还」具有可追溯账行；同时提供只读对账分类，为 P7-5/P7-6 提供输入。范围与 AC 见关联 PRD §3/§5。

**范围外**：Evidence 取证（P7-4）、Sweeper 补记（P7-5）、收敛动作（P7-6）、Admin Console（P7-7）、多 provider（P7-8）、历史 backfill。

## 验证方案（AC ↔ 命令）

| AC | 命令/证据 |
|---|---|
| AC-P73-01/02/03/07/08 | `docker exec pallastrade-web-1 bash -lc "cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/services/pallastrade/financial_ledger/post_dispute_spec.rb"` |
| AC-P73-04/05/06 | `... rspec spec/services/pallastrade/financial_facts/resolve_dispute_spec.rb` |
| AC-P73-09 | `... rspec spec/subscribers/pallastrade/financial_ledger/dispute_funds_subscriber_spec.rb` |
| AC-P73-10 | `... rspec spec/services/pallastrade/reconciliations/reconcile_dispute_spec.rb` |
| AC-P73-11 | `harness check --profile full`（含 migration 场景）+ FIN-P4/P7-1/P7-2 回归 |
| AC-P73-12 | `harness generated:check` + `harness doc-impact --base origin/dev` + `harness sync-check --id PRD-20260912-payments-dsp-p7-3-dispute-posting-and-reconcile` |

证据类型：`test`（rspec）+ `review`（只读边界/金额方向人审）+ `approval`（用户确认）+ `knowledge`（skill/scenario 同步）。

## 用户确认

| 项 | 状态 |
|---|---|
| PRD 已呈现 | ✅ 2026-09-12 已呈现（摘要 + 三项关键设计决定 + 范围外） |
| 用户确认 | ✅ **已确认**（2026-09-12 问答工具选择『确认实施 P7-3』）；批准证据 EVD-20260912070944-41b2e32a86 |
