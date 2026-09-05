# PRD-20260904-payments-txn-p2-7-operational-hardening-backend-slice

| 元数据 | 值 |
|---|---|
| 状态 | approved |
| 创建日期 | 2026-09-05 |
| 来源 | P2 源文档 §58（TXN-P2-7 Operational Hardening）——slice1 后端切片已完成；**slice2（2026-09-05 回写）：Admin transaction inspection UI + 保守自动 stuck sweeper + 最小 metrics/alerts**（用户选「完整资源页/保守 sweeper/最小集」） |
| 分类 | payments（交易运维域） |
| 关联 REQ | REQ-20260905-txn-p2-7.md（slice1）；REQ-20260905-txn-p2-7-admin-sweeper.md（slice2） |
| 需求类型 | 新功能（Admin 资源 + 定时 sweeper） |

## 1. 背景与目标

- **一句话需求原文**：继续 P2 → TXN-P2-7 Operational Hardening 后端切片。
- **背景**：TXN-P2-2..5 已交付 transaction 全生命周期；运维需要：交易 trace（时间戳/尝试/错误聚合）、stuck/needs-attention 可见性（payment_confirmed/finalizing 超龄 + recovery_required/manual_review）、manual recovery tooling（不依赖 Admin UI）、ops runbook。Admin transaction inspection UI、metrics/alerts 需 Admin resource 基建/可观测组件，独立后续。
- **目标**：
  1. `CommerceTransaction.needs_attention` scope + `trace` 读模型（§58 transaction trace / stuck visibility）。
  2. rake `pallastrade:transactions:{list_needs_attention,recover[id]}`（manual recovery tooling，ops 直用）。
  3. `docs/operations/transaction-recovery-runbook.md`（inspection/recover 操作手册）。
- **成功指标**：scope/trace spec 绿；rake 可执行；新增文件 rubocop 0；回归绿。

## 2. 场景

- 运维 A：列出全部需关注交易（recovery_required/manual_review 或 payment_confirmed/finalizing 超 1h）。
- 运维 B：对单笔交易执行 manual recover（rake），输出 action/终态；失败给出 last_error。
- 运维 C：详情 trace 聚合（启动/确认/finalize/完成/恢复时间戳、attempts、last_error、参与者与会话数、快照指纹）。

## 3. FR/AC

### FR-701：needs_attention scope（stuck visibility）
- 语义：state ∈ recovery_required/manual_review（任何时长）∪ state ∈ payment_confirmed/finalizing 且 updated_at 早于阈值（默认 1h，参数 stuck_after）。
- AC-701：recovery_required/manual_review 恒被包含。
- AC-702：payment_confirmed 超龄（updated_at < now-1h）被包含；新鲜（<阈值）不包含。
- AC-703：completed/payment_pending/canceled/created 不含；参数 stuck_after 生效。

### FR-702：trace 读模型
- `transaction.trace` → Hash：state/purpose/amount/currency/snapshot_fingerprint + started_at/payment_confirmed_at/finalizing_at/completed_at/recovery_required_at/manual_review_at/canceled_at + recovery_attempts/last_error_{class,code,message} + participants（role/count/已完成数）+ sessions（count/状态分布）。
- 只读、零副作用。
- AC-711：trace 含时间戳/attempts/error/participant/session 摘要（关键键存在且值正确）。

### FR-703：manual recovery rake（tooling）
- `rake pallastrade:transactions:list_needs_attention`（stdout count + tsv 行）。
- `rake pallastrade:transactions:recover[txn_xxx]` → `Transactions::Recover.call`；成功打印 action+终态；失败打印 error（exit 1）。
- AC-721：recover[id] 对 recovery_required 交易执行并输出终态（rake 内调用 Recover 语义同 P2-4 spec）。

### FR-704：范围边界
- Admin UI/metrics/alerts/自动 sweeper：延后（REQ 记录）；不新增迁移/API/SDK；无状态机改动。

---

# Slice 2 — Admin transaction inspection UI + 保守 sweeper（2026-09-05 回写）

## S2 背景
slice1 已交付 scope/trace/rake/runbook。slice2 落地 §58 剩余：Admin transaction inspection UI、自动 stuck sweeper、最小 metrics/alerts。设计决策（用户确认）：**保守 sweeper**（仅 recovery_required 自动；manual_review/stuck 只列示+日志）；**完整 Admin 资源页**（sidebar 菜单 + index 汇总卡 + show trace + recover 按钮 + 权限 + 双语）；**最小 metrics/alerts**（index 汇总卡计数 + sweeper 结构化日志；不新建通知通道）。

## S2 FR/AC

### FR-711：Admin transactions 资源页（镜像 email_logs/contact_messages）
- `PallasTrade::Admin::TransactionsController < ResourceController`：model_class=CommerceTransaction；store 作用域；index（汇总卡 + render_table）+ show（trace + page_actions）+ 成员动作 `recover`（POST，enqueue `Transactions::RecoverJob` 后 flash+redirect）。
- 路由 `resources :transactions, only: [:index, :show] do member { post :recover } end`；sidebar Orders 组子项；tables 注册（link_to_action: :show）；PermissionRegistry `:transactions`（read/update，store_id）；双语 nav label/flash。
- AC-711：GET /admin/transactions 渲染当前 store 交易列表（含汇总卡计数）。
- AC-712：GET /admin/transactions/:txn 渲染 trace（时间戳/attempts/error/participants/sessions）。
- AC-713：POST recover：仅 recovery_required/finalizing 显示按钮并 enqueue RecoverJob（异步）；非可恢复态不显示按钮；manual_review 无按钮。
- AC-714：非 SuperUser 经 PermissionRegistry read/update 授权可读/恢复（store 数据域）。

### FR-712：保守自动 stuck sweeper（sidekiq-cron）
- `PallasTrade::Transactions::RecoverSweeperJob`：每 store 扫 `recovery_required` → enqueue RecoverJob；`manual_review` + stuck（payment_confirmed/finalizing > 阈值）只计数 + 结构化日志（metrics）；不自动处理（INV-04/AC-2014）。
- host `config/sidekiq_schedule.rb` 增 cron 条目（*/5，可调）。
- AC-721：recovery_required 交易被 enqueue RecoverJob。
- AC-722：manual_review 与 stuck 交易不被自动 recover，仅计入日志。
- AC-723：跑多次幂等（Recover 幂等 + enqueue 不重复处理）。

### FR-713：最小 metrics/alerts
- Admin index 顶部汇总卡：recovery_required / manual_review / stuck(payment_confirmed|finalizing>1h) 计数（按当前 store）。
- sweeper 每次运行 Rails logger 结构化行（counts by category + store）。
- AC-731：汇总卡计数正确；sweeper 日志含类别计数。

## S2 测试计划
- `backend/spec/jobs/pallastrade/transactions/recover_sweeper_job_spec.rb`（AC-721/722/723）
- `backend/spec/requests/pallastrade/admin/transactions_spec.rb`（AC-711/712/713）
- 回归：p0-payment-rspec + chk-p1-5（无支付行为变更，防回归）

## S2 知识同步
- payments SKILL changelog（TXN-P2-7 slice2）；data-model SKILL（Store has_many commerce_transactions 若加）；scenarios.json 新场景；runbook 补 sweeper/Admin 用法。

## 4. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-05 | 0.1 | 定稿 approved（用户选 A 推进 P2-7 后端切片） | AI |
| 2026-09-05 | 0.2 | 实施完成：needs_attention scope + trace + rake list/recover + ops runbook；模型 spec 9 examples 0 failures；rake 注册验证；新增文件 rubocop 0 | AI |
| 2026-09-05 | 0.3 | slice2 回写：Admin transactions 资源页 + 保守 sweeper + 最小 metrics（用户确认三项决策）；REQ-20260905-txn-p2-7-admin-sweeper.md | AI |

## 回写记录（harness prd update）

| 日期 | 来源 | 操作者 |
|---|---|---|
| 2026-09-05 | 需求：TXN-P2-7 完整——Admin transaction inspection UI + 保守自动 stuck sweeper + 最小 metrics（slice 2） | AI |
