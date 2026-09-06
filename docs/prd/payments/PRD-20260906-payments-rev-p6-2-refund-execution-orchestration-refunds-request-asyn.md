# PRD-20260906-payments-rev-p6-2-refund-execution-orchestration-refunds-request-asyn

| 元数据 | 值 |
|---|---|
| 状态 | verifying |
| 创建日期 | 2026-09-06 |
| 来源 | 需求：REV-P6-2 Refund Execution Orchestration（Refunds::Request + async ExecuteJob，provider I/O 彻底移出 DB tx） |
| 分类 | payments（自动判定，关键词：退款/refund） |
| 关联 Skill | `pallastrade-payments`、`pallastrade-data-model`、`pallastrade-events-webhooks`（job/subscriber 接线） |
| 关联 REQ | REQ-20260906-rev-p6-2-refund-execution.md（实施时回填） |
| 关联 PRD | PRD-20260906-payments-rev-p6-1-durable-refund-lifecycle-foundation-退款-durable-生命周期（REV-P6-1，done） |
| 需求类型 | 优化迭代（新功能增量，feature gate） |

> 🔁 **查重回写**：`harness prd new` 自动查重通过。REV-P6-1（done）已交付 durable 底座 + v1 同步执行器；本 PRD = REV-P6-2（源文档 REV-P6 §57），把执行主路径 async 化。
> ⚠️ **编号**：REV-P6 与内部拆单域 P5/P6/P7 为两套编号（沿用 FROZEN-4）。

---

## 0. 来源与范围界定

- **源规格**：`豆包梳理业务需求/P6 — Refund, Cancellation & Dispute Orchestration.md` REV-P6 §57（REV-P6-2）。
- **本 PRD 范围**：`Refunds::Request`（durable requested + enqueue）→ `Refunds::ExecuteJob`（async 执行 `Refunds::Execute`）→ 三个现有退款入口切到「Request → 后台执行」→ 知识收尾（skill/anti-pattern/scenarios/镜像说明）。
- **明确不做**：ReverseTransaction（REV-INV 冻结）；CommerceTransaction 倒退；Dispute（P7）；Cancellation Orchestrator（REV-P6-4）；Return Inspection/Restock（REV-P6-5）；`Refunds::Recover`/Sweeper/ReverseCommerce::Recover（REV-P6-6）；Refund Financial Convergence（REV-P6-7）；Admin Ops UI（REV-P6-8）。
- **REV-P6-1 已交付并被本包复用**：Refund 状态机（requested/processing/succeeded/failed/ambiguous/manual_review/canceled）、`Refunds::Execute`（claim→provider I/O→三态）、`Payment#refundable_capacity`、`provider_idempotency_key`、`refund.succeeded → PostRefund`。

---

## 1. 背景与目标

### 1.1 一句话需求原文

> 需求：REV-P6-2 Refund Execution Orchestration（Refunds::Request + async ExecuteJob，provider I/O 彻底移出 DB tx）

### 1.2 背景

REV-P6-1 移除了 `after_create :perform!` 并引入显式 `Refunds::Execute`，但**执行仍是同步的**，遗留两处与 REV-INV-03（provider I/O 不得位于长期 DB lock/transaction）的偏差：

1. **gateway `cancel` 自动退款**：Stripe/Adyen/PayPal `cancel` 在各自调用上下文里 `save(requested) → Execute(raise_on_failure)`——若该上下文处在外层事务（Payment#cancel!/order cancel 链）内，provider I/O 仍在其事务内；失败 raise 还可能回滚整条取消链。
2. **reimbursement 退货退款链**：`create_refund` 在 `Reimbursement#perform!` 外层事务内 `save → Execute`，同样链内同步 PSP。
3. **Admin API**：REV-P6-1 为同步执行（请求内等网关），对慢 PSP/超时场景让运营请求挂起；且「资金副作用未在 durable 提交后由独立执行单元承载」的恢复语义仍不完整（真正的恢复 owner = 后台执行单元 + 未来的 Recover/Sweeper，REV-P6-6）。

REV-P6-2 的目标 = **把「退款意图 durable 落库」与「资金执行」彻底解耦**：任何入口只做 `Refunds::Request`（校验 + 建 requested 行 + 提交）然后 enqueue `Refunds::ExecuteJob`；provider I/O 只发生在后台 Job（不在任何 request/业务事务内）。这同时完成源 §12（创建必须先于 PSP）、§13（I/O 不占锁）、§43（Reimbursement 不再是资金执行者）。

### 1.3 目标

1. 新增 `Refunds::Request`：唯一「发起退款」入口（校验 capacity/ownership → durable requested → enqueue）。
2. 新增 `Refunds::ExecuteJob`（Sidekiq）：async 执行 `Refunds::Execute`；claim 幂等（仅 requested 可执行，processing/succeeded/failed/ambiguous/manual_review/canceled 不重复）；乐观锁/状态守卫防并发双执行。
3. 三个入口全部切到 Request + enqueue：
   - Admin API `POST /orders/:id/refunds` → 201 + `state=requested`（异步执行，取消同步等待）。
   - Stripe/Adyen/PayPal `cancel`（completed payment 自动退款）→ Request + enqueue（不再链内同步 PSP）。
   - `reimbursement_type/reimbursement_helpers#create_refund` → Request + enqueue（Reimbursement「reimbursed」= 退款已发起，资金事实由 Refund state/Journal 表达）。
4. processing/ambiguous 行可通过 `GET /orders/:id/refunds` 观察（serializer 已含 state，REV-P6-1 交付）；完整恢复=sweeper 属 REV-P6-6。
5. 知识收尾：data-model/api-v3/events-webhooks skill 补 REV-P6-2；anti-pattern「create 即资金副作用」入库；scenarios 增 GS-060；记录 platform/payments 镜像说明。

### 1.4 成功指标

- 全仓不再存在「在 request/业务事务内同步调用 gateway.credit」的退款路径（grep `Refunds::Execute.call` 的生产调用点仅剩 Job）。
- provider I/O 后本地失败：refund 行 durable 停留 processing/ambiguous（可被 REV-P6-6 收敛），不因调用方事务回滚消失。
- Admin create 响应 201 + state=requested；`GET /orders/:id/refunds` 可观测终态。
- backend-rspec 全量 verifier 绿；P0-P5 baseline 绿（AC-6030~6035）。

---

## 2. 用户故事 / 场景

- 作为 **Admin 运营**，我希望创建退款后立即返回（不用等网关），并可稍后查询 Refund state/失败原因。
- 作为 **取消流程（domain）**，我希望 gateway `cancel` 只登记退款请求并立即返回，资金在后台可靠退回，退款失败不再回滚整条取消。
- 作为 **系统（后台执行）**，我希望每笔 durable Refund 有独立 Job 执行且幂等（重启/重试不产生第二笔 PSP 退款）。

**场景**
- N1 Admin 创建退款 → 201 state=requested → Job 执行 → succeeded → REFUND_SUCCEEDED journal。
- N2 网关 `cancel`（completed payment）→ Request + enqueue → 取消立即完成，退款后台执行。
- N3 reimbursement 发起 → 每笔 Refund 独立 Job；资金按 split 目标回退。
- B1 Job 执行时 refund 已是 processing（另一 Worker 在跑）→ 幂等跳过。
- B2 创建 requested 后进程崩溃 → Job 未跑，行停留 requested（容量占用）→ REV-P6-6 sweeper/Admin 可收敛。
- E1 provider 拒绝/超时 → failed/ambiguous durable（复用 REV-P6-1 语义）。

---

## 3. 功能需求（FR）

### 3.1 Refunds::Request（发起入口）

- **FR-R62-101**：新增 `PallasTrade::Refunds::Request`（`services/pallastrade/refunds/request.rb`）。职责：capacity 校验（复用 create validation + `payment.refundable_capacity`）→ 构建 durable `Refund(requested)` + ownership 冻结（payment / commerce_transaction(可证明) / target_order / payment_split）→ `save!`（提交）→ enqueue `Refunds::ExecuteJob`。返回 Result(value=refund)。
- **FR-R62-102**：Request 幂等/并发：`payment.refunds` create 校验（amount ≤ capacity，含 in-flight）沿用；重复调用创建多笔是业务允许（多笔 partial），不额外去重。
- **FR-R62-103**：Request 不得调用 gateway / 不得在自身事务内执行 PSP（REV-INV-03）。
- **FR-R62-104**：`Refunds::ExecuteJob` 入队参数 = `refund_id`（raw id）+ `provider_idempotency_key` 不传（Execute 内部生成/读取）；Job 幂等守卫在 Execute.claim。

### 3.2 Refunds::ExecuteJob（async 执行）

- **FR-R62-201**：新增 `PallasTrade::Refunds::ExecuteJob < ApplicationJob`（core `app/jobs/` 或已有 job 目录），`queue_as :default`（与 payment 类 job 一致）；`perform(refund_id)`：load refund（`find_by`），nil → 返回；调 `Refunds::Execute.call(refund:, raise_on_failure: false)`（**不 raise**，失败以 refund state 表达）。
- **FR-R62-202**：Job 重试策略：sidekiq retry 有限（如 5）；`Refunds::Execute` claim 幂等（仅 requested→processing）→ 重试不重复 PSP；ambiguous 结果不自动重试退款（REV-INV-04）——Job 只执行一次 provider 调用，结果即终态（失败/ambiguous 由 REV-P6-6 恢复）。
- **FR-R62-203**：注册/命名与 sidekiq 配置对齐（参照 `payment`/`transactions` 域 job 的 queue 与 schedule 约定）；不新增 cron（sweeper 属 REV-P6-6）。
- **FR-R62-204**：Execute 内异常兜底：Execute 内部已 rescue 为标准 error→ambiguous；ExecuteJob 顶层 rescue → Rails.logger + refund 停留当前态（不吞不重复）。

### 3.3 入口迁移（三处）

- **FR-R62-301（Admin API）**：`refunds#create` 改为 `Refunds::Request.call(payment:, amount:, reason:, ...)` → 201 + `state=requested`（不再同步 Execute）。审计保留。**契约变更**：不再保证响应即终态；前端用 `GET /orders/:id/refunds` 轮询 state。
- **FR-R62-302（gateway cancel）**：Stripe/Adyen/PayPal `cancel`（`payment.completed?` 分支）由「save+同步 Execute」改为「`Refunds::Request` + enqueue」→ 立即返回 `success(payment.response_code, {})`。不再引用 `refund.response`（同步产物）。失败语义：不 raise 回滚取消链；退款失败以 durable Refund state 记录。
- **FR-R62-303（reimbursement）**：`reimbursement_type/reimbursement_helpers#create_refund` 非 simulate 分支改为 `Refunds::Request`（enqueue）。`Reimbursement#perform!`/`reimbursed` 语义 = 「退款已发起」（资金事实由 Refund.state + Journal 表达）；仅当 Request 创建失败（容量/校验）才走报销 errored。适配 `original_payment_child_spec` 等。
- **FR-R62-304**：迁移后全仓生产代码**无** `Refunds::Execute.call` 直接调用点（仅 ExecuteJob）——grep 校验。

### 3.4 可见性/恢复底座（不做 sweeper）

- **FR-R62-401**：Refund `processing` 超龄可见性由既有 Admin serializer 字段（state/timestamps）满足；REV-P6-2 不新增 API。
- **FR-R62-402**：文档/注释明确：`requested/processing/ambiguous` 滞留行的收敛 owner = REV-P6-6 `Refunds::Recover`/Sweeper（本包只保证 durable + 可观测）。

### 3.5 知识收尾

- **FR-R62-501**：`ai/skills/pallastrade-data-model/SKILL.md` 补 refunds 生命周期列说明；`pallastrade-api-v3/SKILL.md` 补 Admin refunds create async 契约；`pallastrade-events-webhooks/SKILL.md` 补 `refund.succeeded/failed/ambiguous` 事件；`pallastrade-payments/SKILL.md` 补 REV-P6-2（Request/Job）。
- **FR-R62-502**：anti-pattern 入库：`harness/policies/anti-patterns.json` + AGENTS.md §5 + copilot-instructions 增「AP：after_create :perform! / request 事务内同步 PSP（create 即资金副作用）」。
- **FR-R62-503**：`harness/scenarios/scenarios.json` 增 GS-060（REV-P6-2 async refund execution）。
- **FR-R62-504**：README 说明：`platform/payments/*` 为 standalone engine 副本（自带 CI），backend 运行时以 `backend/pallastrade_gems/*` 为准；镜像同步为仓库治理决策，本包不改动 platform/payments 副本。

---

## 4. 非功能需求（NFR）

- 幂等：ExecuteJob 重试/并发不重复 PSP；同 Refund 稳定 `provider_idempotency_key`。
- 兼容：取消/报销流程不再因退款失败整体回滚（行为变更已声明）；P0-P5 baseline 全绿。
- 安全：退款仍敏感操作（权限+Audit 保留）；异步 Job 不引入未授权执行面。
- 可观测：Admin serializer state/timestamps/last_error 已覆盖；Job 日志带 refund prefixed id。
- 可靠：durable-first（行先于任何 PSP）；失败/未知以 durable 行表达（不 raise 丢行）。

---

## 5. 验收标准（AC）

> 编号 AC-R62-xxx；「源」列引用 REV-P6 源 AC-60xx。标注 (REV-P6-6) 的 AC 不在本包关闭。

| AC | 源 | 验收条件 | 覆盖 FR |
|---|---|---|---|
| AC-R62-01 | AC-6001 | 任何 PSP 副作用前本地有 durable Refund row（Request 提交后 Job 才执行） | FR-R62-101/103 |
| AC-R62-02 | AC-6002 | Request 创建失败（容量/校验）→ 不 enqueue、不调 PSP | FR-R62-101/303 |
| AC-R62-03 | AC-6003 | 生产全仓无「业务事务/request 内同步 PSP」退款路径（仅 ExecuteJob 调 Execute） | FR-R62-104/201/304 |
| AC-R62-04 | AC-6004 | 同 Refund 所有执行（Job 重试/Recovery）用同一 provider_idempotency_key | FR-R62-104/202 |
| AC-R62-05 | AC-6006 (REV-P6-6) | PSP success + 本地失败 → durable processing/ambiguous 可恢复（Recover/Sweeper 属 REV-P6-6） | FR-R62-204/402 |
| AC-R62-06 | — | ExecuteJob 幂等：已 processing/succeeded/failed/ambiguous/manual_review/canceled 的 Refund 不重复执行 PSP | FR-R62-201/202 |
| AC-R62-07 | — | Admin create 返回 201 + state=requested；GET /orders/:id/refunds 可观测终态/失败 | FR-R62-301 |
| AC-R62-08 | — | gateway cancel（completed）创建 durable requested + enqueue 并立即成功返回；取消链不被退款失败回滚 | FR-R62-302 |
| AC-R62-09 | — | reimbursement 每笔 Refund 独立 Request+Job；reimbursed 语义=已发起（适配既有 spec） | FR-R62-303 |
| AC-R62-10 | AC-6030~6035 | P0-P5 baseline 全绿 + backend-rspec 全量 | 全部 |
| AC-R62-11 | — | 知识收尾完成（skill×3、anti-pattern、GS-060、README 镜像说明） | FR-R62-501~504 |

---

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | refund / execute | 无宿主 override | 否——改框架层 |
| Core | `pallastrade_gems/pallastrade_core/app/` | Refund / Execute / jobs | `models/.../refund.rb`、`services/refunds/execute.rb`（REV-P6-1）、`jobs/`（payment/transactions 域 job 先例） | 部分——Request/ExecuteJob 需新建 |
| API | `pallastrade_gems/pallastrade_api/app/` | refunds | `admin/orders/refunds_controller.rb`（REV-P6-1 同步执行版，需改 async） | 部分——create 改 Request |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | refunds | legacy controllers | 本包不动 |
| Storefront | `storefront/src/` | refund | 无 | 否 |
| Platform | `platform/packages/` | refund | admin-sdk 类型（OpenAPI 生成） | admin.yaml 更新后同步 |

**结论**：核心新增 = `Refunds::Request` + `Refunds::ExecuteJob`；改造 = admin refunds_controller（async 契约）+ 三 gateway cancel + reimbursement helpers + Job 注册；其余（state/serializer/capacity/Execute）REV-P6-1 已交付。无重复能力：全仓无 async refund job。

---

## 7. 技术影响

- Core 新增：`services/pallastrade/refunds/request.rb`、`jobs/pallastrade/refunds/execute_job.rb`。
- Core 改造：`reimbursement_type/reimbursement_helpers.rb`（Request 化）。
- Provider 改造：stripe/adyen/paypal `gateway.rb` cancel（Request 化，去掉同步 Execute 与 refund.response 依赖）。
- API 改造：`admin/orders/refunds_controller.rb`（Request + 201 state=requested）；`backend/public/api-docs/admin.yaml` + `platform/docs/api-reference/admin.yaml`（create 契约：async + state=requested）。
- Sidekiq：queue 配置对齐（无新 cron）。
- 测试：新增 request/execute_job spec；适配 refunds_controller/gateway cancel/original_payment_child spec（大量依赖同步成功→终态断言需改 async：改为「create 后行 requested + Job 执行后 succeeded」或 stub job 内联执行）。
- 文档：admin.yaml、skills（data-model/api-v3/events/payments）、anti-patterns.json + AGENTS.md §5 + copilot-instructions、scenarios GS-060、README（镜像说明）。

**风险**
- Admin create 同步→异步契约变更：确认无阻塞消费方（Admin SDK 调用点核验）。
- reimbursement「reimbursed=已发起」语义变更：影响 RA/CR 链 spec 与运营预期——列为设计决策需确认。
- gateway cancel 异步化：取消立即成功但退款后台失败——需 durable row + 未来 P6-6；行为变更需 review。
- Job 并发：依赖 Execute.claim 状态守卫（已建）+ 乐观锁（lock_version 已加列，REV-P6-1）。

---

## 8. 测试计划

**新增**
- `backend/spec/services/pallastrade/refunds/request_spec.rb`：durable+enqueue、失败不 enqueue（AC-R62-01/02）。
- `backend/spec/jobs/pallastrade/refunds/execute_job_spec.rb`：执行成功/终态幂等/nil refund 安全（AC-R62-04/06）。
- `backend/spec/requests/api/v3/admin/orders/refunds_controller_spec.rb`（新建或补）：201 + state=requested；job 执行后 succeeded（AC-R62-07）。

**更新**
- stripe/adyen/paypal `gateway_spec` cancel 分支：断言 durable requested + enqueue（stub job 内联或 `assert_enqueued`）→ AC-R62-08。
- `original_payment_child_spec` / reimbursement 相关：reimbursed=已发起语义 → AC-R62-09。
- `refund_spec`/REV-P6-1 既有 spec：同步 Execute 调用点（如有）改 job。
- 每 spec 头部标注 `# PRD-REV-P6-2 AC-R62-xx`。

---

## 9. 文档同步清单（知识同步门）

- [ ] API 文档：`backend/public/api-docs/admin.yaml` + `platform/docs/api-reference/admin.yaml`（refunds create async 契约）
- [ ] Skill：`pallastrade-payments`（REV-P6-2）、`pallastrade-data-model`（refunds 列）、`pallastrade-api-v3`（async 契约）、`pallastrade-events-webhooks`（refund.* 事件）
- [ ] 反模式：`harness/policies/anti-patterns.json` + AGENTS.md §5 + `.github/copilot-instructions.md`（create 即资金副作用）
- [ ] 场景库：`harness/scenarios/scenarios.json`（GS-060）
- [ ] 镜像说明：README（platform/payments standalone 副本说明）
- [ ] 本 PRD 状态 + `docs/prd/README.md` 索引 + `harness doc-impact`

---

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-06 | 0.1 | 初稿（依据 REV-P6 §57 + REV-P6-1 实施现状） | AI |
| 2026-09-06 | 0.2 | 实施：Refunds::Request + ExecuteJob；Admin/gateway cancel ×3 改 async（201 state=requested / 立即成功）；**范围偏差（记录）**：reimbursement 退货链在实现中发现引擎重复构建/容量误伤，本包保留 REV-P6-1 同步语义（create_refund + Execute raise_on_failure），完整 async 编排归 REV-P6-5；admin.yaml ×2 async 契约；payments skill / GS-060 / anti-pattern AP-010 / AGENTS §5 同步；新增 request/execute_job spec（60 例回归 0 failures） | AI |

