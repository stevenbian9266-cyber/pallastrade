# REQ-20260912-dsp-p7-5-dispute-deadline-sweep

> 关联 PRD：`docs/prd/payments/PRD-20260912-payments-dsp-p7-5-dispute-deadline-sweep.md`
> 任务：`TASK-20260912135249-b3245c51` ｜ Gate：`GATE-2026-09-12T13-53-09`（feature，branch `dev`）

---

## Step 0：跨层搜索（强制执行）

关键词：`deadline` / `sweeper` / `evidence_due_at` / `sidekiq-cron` / `Dispute`

| 层 | 搜索路径 | 找到的文件 | 是否满足需求？ |
|---|---|---|---|
| App — models/controllers | `backend/app/` | 无 dispute/deadline 命中；**调度配置在宿主层**（`config/sidekiq_schedule.rb`、`config/initializers/pallastrade_sidekiq_cron.rb`） | ⚠️ 需登记调度条目（机制已有） |
| App — config | `backend/config/` | `sidekiq_schedule.rb`（`PALLAS_CART_SCHEDULE`：弃购/交易恢复/库存到期/核销到期） | ⚠️ 追加一条即接入 |
| Core Gem — jobs | `.../pallastrade_core/app/jobs/` | `reconciliations/reconcile_sweeper_job.rb`（同类 sweeper 先例） | ⚠️ 模式可复用，争议 sweeper 不存在 |
| Core Gem — services/models | `.../pallastrade_core/app/` | `services/pallastrade/disputes/*`（P7-1..4）、`models/pallastrade/dispute.rb`（`evidence_due_at`、`TERMINAL_STATES`、`active` scope） | ⚠️ 输入齐备；**扫描/告警缺失** |
| API / Admin | `pallastrade_api/app/`、`pallastrade_admin/app/` | 无命中 | ❌ 本切片无 API/UI（归 P7-7） |
| Storefront / Platform | `storefront/src/`、`platform/packages/` | 无命中 | ❌ 不适用 |

### 搜索结论

- 扫描与告警能力 6 层均无 → **新增**；落点 = core gem（服务 + job）+ 宿主 config（调度登记，先例 `PALLAS_CART_SCHEDULE`）。
- 零 schema 变更：`evidence_due_at` 与 `state` 已有一等列 + 复合索引 `index_pallastrade_disputes_on_state_and_evidence_due_at`。
- 复用输入：P7-4 `BuildEvidenceSnapshot` 的 `missing_evidence[]`（让告警可行动）。

---

## Step 1：Skill 文件咨询（强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树第 8 级（框架自研产品线直接改 Gem）；调度属宿主 config（非 gem 内部）→ 两层各改一处 |
| `ai/skills/pallastrade-data-model/SKILL.md` | ✅ 已读 | §Disputes：`evidence_due_at`/`evidence_submitted_at` 已为列；`TERMINAL_STATES` 定义明确 → **无需迁移** |
| `ai/skills/harness-prd/SKILL.md` | ✅ 已读 | P7-4 PRD 已预留 Sweeper 切片 → `prd new --force` 成立；PRD 完整扩充后待用户确认 |

**按需 Skill：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-payments` | ✅ | ✅ 已读 | 争议域 P7-1..4 只读边界与命名纪律；本切片延续「只提示不决策」 |
| `pallastrade-events-webhooks` | ✅ | ✅ 已读 | 事件发布/订阅：subscriber async、禁 `after_save`；本切片只 `publish_event` + 结构化日志 |
| `pallastrade-testing` | ✅ | ✅ 已读 | 断言型用例（含负向断言）优于注释 → 零业务动作用负向断言落实 |

---

## 需求标题

DSP-P7-5：争议**证据期限扫描 + 告警**（只提示、不决策；每日一次；提示里带缺口清单）。

## 任务类型

新功能（周期 job + 只读扫描；0 migration、0 API/UI）。

## 需求描述

扫描未终态且有 `evidence_due_at` 的争议，按 `overdue / due_soon(window)` 分桶，逐条发布事件并输出结构化日志，
附 P7-4 的 `missing_evidence` 让提醒可行动；job 绝不做任何业务动作。范围与 AC 见 PRD §3/§5。

**范围外**：证据提交（P7-8）、收敛/恢复动作（P7-6）、Admin 展现（P7-7）、自动接受争议/退款（永不）。

## 验证方案（AC ↔ 命令）

| AC | 命令/证据 |
|---|---|
| AC-P75-01..05、10 | `docker exec pallastrade-web-1 bash -lc "cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/services/pallastrade/disputes/scan_deadlines_spec.rb"` |
| AC-P75-06..09 | `... rspec spec/jobs/pallastrade/disputes/deadline_sweeper_job_spec.rb` |
| AC-P75-11 | 注册 verifier `backend-rspec`（全量）+ `harness generated:check` + `doc-impact` |

## 用户确认

| 项 | 状态 |
|---|---|
| PRD 已呈现 | ✅ 2026-09-12 已呈现（只提示不决策 / 不猜 / 不造噪音 三条边界 + 交付物 + 规模） |
| 用户确认 | ✅ **已确认**（2026-09-12 问答工具『确认实施 P7-5』）；批准证据 EVD-20260912135616-7783b0b23d |
