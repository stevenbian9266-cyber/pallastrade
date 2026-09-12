# REQ-20260912-dsp-p7-6-dispute-recovery

> 关联 PRD：`docs/prd/payments/PRD-20260912-payments-dsp-p7-6-dispute-recovery.md`
> 任务：`TASK-20260912161945-6f02f907` ｜ Gate：`GATE-2026-09-12T16-20-07`（feature，branch `dev`）

---

## Step 0：跨层搜索（强制执行）

关键词：`dispute` / `chargeback` / `attention_reason` / `Recover` / `manual_review` / `reconcile`

| 层 | 搜索路径 | 找到的文件 | 是否满足需求？ |
|---|---|---|---|
| App | `backend/app/` | 无 dispute 命中；仅 Devise `:recoverable`（`user.rb` / `admin_user.rb`）与 CommerceTransaction 的 `recovery_attempts`（**不同域**） | ❌ 无既有收敛能力 |
| Core Gem — services/jobs | `.../pallastrade_core/app/services/pallastrade/disputes/`、`.../app/jobs/pallastrade/disputes/` | `resolve_fact.rb`（裁决）/ `handle_provider_event.rb`（落库）/ `build_evidence_snapshot.rb`（P7-4）/ `scan_deadlines.rb`（P7-5）/ `deadline_sweeper_job.rb`（sweeper 先例） | ⚠️ 输入齐备；**收敛编排缺失** |
| Core Gem — 复用原语 | `.../financial_ledger/post_dispute.rb`、`.../reconciliations/reconcile_dispute.rb`、`.../financial_facts/resolve_dispute.rb`、`models/pallastrade/dispute.rb` | 幂等入账（`skip_reason_for` 封闭枚举）/ 只读对账（5 分类）/ 事实映射（事件作用域 `fact_type`）/ 状态机 `transition_to!` + `attention_reason` | ⚠️ 全部可复用，**不新建事实来源** |
| API / Admin | `pallastrade_api/app/`、`pallastrade_admin/app/` | 无命中 | ❌ 本切片无 API/UI（归 P7-7 Console） |
| Storefront / Platform | `storefront/src/`、`platform/packages/` | storefront 无命中；platform 仅 `docs/dist/integrations/payments/adyen.md` 文本提及 chargeback | ❌ 不适用 / 无 SDK 变更 |

### 搜索结论

- dispute **收敛编排**（Recover / 候选扫描 / sweeper）6 层均不存在 → **新增**；落点 = core gem
  （`Disputes::Recover`、`Disputes::ScanRecoveryCandidates`、`Disputes::RecoverSweeperJob`）
  + 宿主 `backend/config/sidekiq_schedule.rb`（调度登记，复用 P7-5 机制）。
- **防重复判定（AP-SEARCH-1/2/3）**：不新建 provider 判定（复用 `Disputes::ResolveFact`）、
  不新建对账（复用 `Reconciliations::ReconcileDispute`）、不新建入账（复用 `FinancialLedger::PostDispute`）、
  不新建状态机（复用 `Dispute#transition_to!`）——本切片**只做编排**。
- **零 schema 变更**：`attention_reason` 为 `string` 列、迁移中**无 CHECK 约束** → 扩展
  `ATTENTION_REASONS`（`provider_conflict` / `journal_gap` / `funds_evidence_missing`）**零 DDL**；
  审计痕迹复用既有 `private_metadata` jsonb。
- 既有复合索引 `index_pallastrade_disputes_on_state_and_evidence_due_at` 与
  `financial_ledger_entries.dispute_id` 支撑候选预筛 SQL。

---

## Step 1：Skill 文件咨询（强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树第 8 级（框架自研产品线：直接改 Gem 并标 `# PALLAS-CUSTOM:`）；行为型副作用走 **Subscriber**（非 `after_save`，AP-004）；调度属宿主 config（非 gem 内部）→ 两层各改一处 |
| `ai/skills/pallastrade-data-model/SKILL.md` | ✅ 已读 | §Disputes：10 态**单向**状态机（`manual_review` 为人工态）、`evidence_due_at` 一等列、`attention_reason` 当前 3 值「marks rows needing a human」→ 本切片把该通道**接上 writer**（枚举扩展，无 DDL）；`CommerceTransaction` 恒 `completed`，dispute 不改原交易状态 |
| `ai/skills/harness-prd/SKILL.md` | ✅ 已读 | P7-0 FR-006 + P7-5 PRD 已预留收敛切片 → `prd new` 成立（未触发 >0.3 查重）；阶段 2 要求 `supervise plan` + 阶段 3/4 证据与知识同步门 |

**按需 Skill：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-payments` | ✅ | ✅ 已读 | 争议域 P7-1..5 边界：只读契约（`fetch_dispute_details`）、`fact_type` **事件作用域**提示（终态 `won`/`lost` 不吞 funds 事件）、append-only Journal（不改写既有账行）；源计划 §49/§50「不重扣、不自动退款」= 本切片铁律 |
| `pallastrade-events-webhooks` | ✅ | ✅ 已读 | `Events.publish` 出站事件目录（`dispute.funds_*` 先例）；subscriber 默认 async；payload 用 prefixed id → 新增 `dispute.recovery_*` 事件须同步事件目录 |
| `pallastrade-testing` | ✅ | ✅ 已读 | 「Test behavior, not implementation」+ 「Real factories, not stubs，除非被 stub 的是外部（HTTP/Stripe）」→ provider 快照打桩合法、DB 断言用真实行；「What NOT to test」排除标准 Rails 校验 |

---

## 需求标题

DSP-P7-6：争议**收敛动作 Recovery** —— provider 权威状态单调收敛 + 账行幂等补记 + 冲突交人工（永不自动退款/重扣款）。

## 任务类型

新功能（收敛服务 + 批量 job + 调度；0 migration、0 API/UI）。

## 需求描述

以 **Facts** 为输入（本地 Dispute + provider 只读快照 + FinancialFact + Journal + Reconciliation）做单条收敛决策：
①仅 `stale_local` 单调前进状态到 provider 权威状态；②`journal_missing` 经 `PostDispute` 幂等补记（恰好一次）；
③冲突/孤儿账行/资金时间戳缺失 → 标 `attention_reason` + `manual_review`；④降级（无契约/网络错误）零写；
⑤批量 sweeper（本地预筛零 provider I/O + `limit` 有界）每日 01:30 运行。范围与 AC 见 PRD §3/§5。

**范围外**：Admin Console 展现（P7-7）、多 provider 与证据提交（P7-8）、自动退款/重扣款/新建 Payment（**永不**）、
历史 backfill、账行改写（append-only）。

## 已确认的产品决策（2026-09-12）

| # | 决策 | 取值 |
|---|---|---|
| 1 | 实施范围 | 全量实施（Recover + 候选扫描 + Sweeper + attention 扩展） |
| 2 | sweeper 调度 | **默认启用**：每日 01:30（`30 1 * * *`），`limit: 50`，`verify_after_hours: 24` |
| 3 | 人工复核 | 标 `attention_reason` **且**置 `state = 'manual_review'`（人工通道显式打开） |

## 验证方案（AC ↔ 命令）

| AC | 命令/证据 |
|---|---|
| AC-P76-01..14 | `docker exec pallastrade-web-1 bash -lc "cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/services/pallastrade/disputes/recover_spec.rb"` |
| AC-P76-15/16 | `... rspec spec/services/pallastrade/disputes/scan_recovery_candidates_spec.rb` |
| AC-P76-17/18 | `... rspec spec/jobs/pallastrade/disputes/recover_sweeper_job_spec.rb` |
| AC-P76-19 | 注册 verifier `backend-rspec`（全量）+ `harness generated:check` + `doc-impact` |

## 用户确认

| 项 | 状态 |
|---|---|
| PRD 已呈现 | ✅ 2026-09-12 已呈现（范围 + 铁律 + 19 条 AC + 2 个决策点） |
| 用户确认 | ✅ **已确认**（2026-09-12 问答工具：「确认，按 PRD 全量实施」+ sweeper 默认启用 + 置 `manual_review`） |

## 实施记录（2026-09-12）

- 新增：`Disputes::Recover`、`Disputes::ScanRecoveryCandidates`、`Disputes::RecoverSweeperJob`；
  `PallasTrade::Dispute::ATTENTION_REASONS` +3；`config/sidekiq_schedule.rb` 新增 `dispute_recovery_sweep`。
- 加法式扩展（默认行为不变）：`FinancialFacts::ResolveDispute` / `FinancialLedger::PostDispute` /
  `Reconciliations::ReconcileDispute` 新增可选 `dispute_fact:` —— 收敛编排复用**同一份**权威快照
  （避免重复 provider 只读调用；且不依赖本地元数据，否则缺元数据时会漏补账）。
- 新增测试：`spec/services/pallastrade/disputes/recover_spec.rb`（AC-P76-01..14）、
  `.../scan_recovery_candidates_spec.rb`（AC-P76-15/16）、`spec/jobs/pallastrade/disputes/recover_sweeper_job_spec.rb`（AC-P76-17/18）。
- 测试事实：定向 27 examples 全绿；争议域 + 对账 + 账本 + 事实层 273 examples 0 failures；rubocop 本次触碰 11 文件 0 违规。
