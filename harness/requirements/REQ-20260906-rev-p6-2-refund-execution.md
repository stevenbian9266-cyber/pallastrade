# REQ-20260906-rev-p6-2 — Refund Execution Orchestration（Request + async ExecuteJob）

> 关联 PRD：`docs/prd/payments/PRD-20260906-payments-rev-p6-2-refund-execution-orchestration-refunds-request-asyn.md`（approved）
> 源规格：`豆包梳理业务需求/P6 — Refund, Cancellation & Dispute Orchestration.md`（REV-P6 §57）
> Task：`TASK-20260906191259-5cb39588`；Gate：`GATE-2026-09-06T19-13-19`（feature，risk=critical）
> 分支：dev @ 0d26b9d（前置 REV-P6-1 done 已合入）

---

## Step 0：跨层搜索（六层，gate 强制）

| 层 | 搜索路径 | 关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | refund / execute / job | 无宿主 override | 否——改框架层 |
| Core services/jobs | `pallastrade_gems/pallastrade_core/app/{services,jobs}/` | refund / execute / recover | `services/refunds/execute.rb`（REV-P6-1）、`jobs/pallastrade/transactions/*`（job 先例） | 部分——Request/ExecuteJob 需新建 |
| API | `pallastrade_gems/pallastrade_api/app/` | refunds | `admin/orders/refunds_controller.rb`（REV-P6-1 同步执行版） | 部分——create 改 Request（async） |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | refunds | legacy controllers | 本包不动 |
| Storefront | `storefront/src/` | refund | 无 | 否 |
| Platform | `platform/packages/` | refund | admin-sdk 类型（OpenAPI 生成） | admin.yaml 更新后同步 |

### 搜索结论

- 已存在（REV-P6-1）：Refund durable 状态机、`Refunds::Execute`（claim/三态）、capacity、`provider_idempotency_key`、refund.succeeded subscriber。
- 需新建：`Refunds::Request`、`Refunds::ExecuteJob`。
- 需改造：Admin refunds#create（async 契约）、Stripe/Adyen/PayPal cancel 自动退款分支、reimbursement `create_refund`、admin.yaml（contract）。
- 防重复：全仓无 async refund job / Request 服务。
- 明确不做：Recover/Sweeper（REV-P6-6）、Cancellation Orchestrator（REV-P6-4）、Return/Restock（REV-P6-5）、Dispute（P7）。

---

## Step 1：Skill 文件咨询

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读（REV-P6-1 会话） | 事件/Job 接线用 subscriber + 服务编排；自持 gem 内直接改 |
| `ai/skills/pallastrade-payments/SKILL.md` | ✅ 已读（REV-P6-1 会话 + 本会话更新） | REV-P6-1 章节：Execute 为 v1 同步执行器；REV-P6-2 升级 Request+Job；PostRefund 语义 |
| `ai/skills/harness-prd/SKILL.md` | ✅ 已读 | gate → REQ → 实施 → 测试 → 知识同步 |
| `pallastrade-events-webhooks` | 待实施时读 | subscriber/job 注册约定 |
| `pallastrade-api-v3` | 待实施时读 | Admin refunds create 契约文档 |
| `pallastrade-testing` | 待实施时读 | job/controller spec 位置 |

---

## 需求标题

REV-P6-2 Refund Execution Orchestration：`Refunds::Request`（durable requested + enqueue）+ `Refunds::ExecuteJob`（async 执行），三个退款入口全部异步化，provider I/O 彻底移出任何 request/业务事务。

## 任务类型

新功能（资金安全增量，feature gate，risk=critical）

## 需求描述

REV-P6-1 已把退款升级为 durable 生命周期并拆出显式同步 `Refunds::Execute`，但 gateway cancel 与 reimbursement 仍可能在各自外层事务内同步执行 PSP（REV-INV-03 未完全满足），Admin API 同步等网关。本包：
1. `Refunds::Request`：唯一发起入口（capacity 校验 → durable requested 落库 → enqueue ExecuteJob）；自身不调 PSP。
2. `Refunds::ExecuteJob`（Sidekiq）：async 执行 `Refunds::Execute`；claim 幂等，重试不重复退款；ambiguous 不自动重退。
3. 入口迁移：Admin `refunds#create` → 201 + state=requested（异步）；Stripe/Adyen/PayPal `cancel`（completed）→ Request+enqueue；reimbursement `create_refund` → Request+enqueue（reimbursed=已发起）。
4. 可见性：processing/ambiguous 经既有 serializer 观测；Recover/Sweeper 明确归 REV-P6-6。
5. 知识收尾：skills（data-model/api-v3/events/payments）、anti-pattern「create 即资金副作用」、scenarios GS-060、README 镜像说明。

## 影响范围

- Core：新增 `services/pallastrade/refunds/request.rb`、`jobs/pallastrade/refunds/execute_job.rb`；改 `reimbursement_type/reimbursement_helpers.rb`。
- Provider：stripe/adyen/paypal `gateway.rb` cancel（Request 化，去同步 Execute / refund.response 依赖）。
- API：admin `refunds_controller.rb`（async）+ serializers（已含 state）+ admin.yaml（backend/platform）。
- 测试：新增 request/execute_job/controller spec；适配 gateway cancel / reimbursement / REV-P6-1 spec（同步→async）。
- 知识：skills×4、anti-patterns.json + AGENTS.md §5 + copilot-instructions、scenarios GS-060、README。

## 技术方案（初步）

- `Refunds::Request`：build Refund(requested)（含 ownership 冻结）→ create 校验（capacity）→ save! → `Refunds::ExecuteJob.perform_later(refund.id)` → 返回 Result(value=refund)。
- `Refunds::ExecuteJob`：`perform(refund_id)` → load → `Refunds::Execute.call(refund:, raise_on_failure: false)`；Execute 本身幂等（终态短路/claim 状态守卫）。
- Admin create：`with_order_lock` 内建 requested（审计）→ 锁外 `Refunds::Request`（含 enqueue）→ 201。
- gateway cancel：completed 分支 `Refunds::Request.call(payment:, amount: payment.credit_allowed, reason: order_canceled)` → success。
- reimbursement：`create_refund` 非 simulate → `Refunds::Request`（enqueue）；报销 errored 仅在 Request 失败时。
- Job 重试走 sidekiq 默认；`provider_idempotency_key` 稳定（Execute 内生成/读取）。

## 风险点

- Admin create 同步→异步契约变更（确认无阻塞消费方）。
- gateway cancel 异步化：取消立即成功、退款后台失败——依赖 durable row + REV-P6-6。
- reimbursement「reimbursed=已发起」语义变更（用户已确认）。
- Job 并发：Execute.claim 状态守卫 + lock_version（已建）。
- 回滚：无 migration；代码回滚 = git revert；已入队 Job 执行幂等安全。

## 决策节点（用户已确认 2026-09-07「确认」）

1. Admin create → 201 + state=requested（异步），GET list 观测终态。
2. gateway cancel 自动退款异步化，失败不回滚取消链。
3. reimbursement reimbursed = 已发起退款（资金事实由 Refund.state/Journal 表达）。

---

## 阶段③：实施后验证（不可跳过）

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| Ruby 服务/Job | `request.rb`/`execute_job.rb` | request/execute_job spec（docker rspec） | 新增 7 例通过 | ✅ |
| Provider/API 入口 | gateway cancel ×3 + admin controller | 受影响回归（60 例含 request/execute_job/execute/refund/original_payment_child/lifecycle/capacity/subscriber/resolve_refund/post_refund/reconcile_refund） | 60 examples 0 failures | ✅ |
| Reimbursement | `reimbursement_helpers.rb`（本包保留同步，范围偏差已记录） | original_payment_child spec | 通过（含于 60 例） | ✅ |
| 全量 | — | `backend-rspec` verifier + P0-P5 baseline + doc-impact | 见 evidence | ⬜ |

### 验证结论

REV-P6-2 新增 request/execute_job spec + 受影响回归 60 例 0 failures；reimbursement 链范围偏差（保留 REV-P6-1 同步）已记录于 PRD §10；全量 backend-rspec 走 harness evidence。
