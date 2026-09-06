# PRD-20260906-payments-rev-p6-1-durable-refund-lifecycle-foundation-退款-durable-生命周期

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-06 |
| 来源 | 需求：REV-P6-1 Durable Refund Lifecycle Foundation（退款 durable 生命周期基础，闭合 orphan PSP refund） |
| 分类 | payments（自动判定，关键词：退款/refund） |
| 关联 Skill | `pallastrade-payments`、`pallastrade-data-model`、`pallastrade-security`（退款敏感操作） |
| 关联 REQ | REQ-20260906-rev-p6-1-durable-refund-lifecycle.md |
| 关联 PRD | N/A（源规格：`豆包梳理业务需求/P6 — Refund, Cancellation & Dispute Orchestration.md`（REV-P6，非 docs/prd PRD）） |
| 需求类型 | 新功能（资金安全重构，基于现有 Refund 模型升级） |

> 🔁 **查重回写**：`harness prd new` 自动查重通过（>0.3 无命中）。本 PRD 与既有 P4 资金账本系列（FIN-P4-1~8）无重复——P4 负责 Refund→Journal 接线，本 PRD 负责 Refund 本体 durable 生命周期。
> ⚠️ **编号体系**：源文档 REV-P6 与项目内部 P5/P6/P7（自动拆单/手动拆单/售后父子单化）为**两套编号**（P5 审计 FROZEN-4）。本文一律使用代码名与 REV-P6 编号，避免混淆。

---

## 0. 来源与范围界定

- **源文档**：`豆包梳理业务需求/P6 — Refund, Cancellation & Dispute Orchestration.md`（2026-09-07 更新版，REV-P6）。
- **本 PRD 范围 = REV-P6-1 — Durable Refund Lifecycle Foundation**（源 §56），并内置 REV-P6-0 语义冻结（源 §54-55）。
- **明确不做（本 PRD 边界）**：不建 `ReverseTransaction` 表；不回退 `CommerceTransaction`（不加 refund 事件）；不做 Dispute/Chargeback（源 §64 顺延 P7）；不做 Cancellation Orchestrator（REV-P6-4）；不做 Return Inspection/Restock 重构（REV-P6-5）；不做 async Job/Sweeper/ReverseCommerce::Recover（REV-P6-2/6）；不做 Admin 完整 Ops UI（REV-P6-8）。
- **后续包（各自独立 PRD）**：REV-P6-2 Refund Execution Orchestration（async Request/Execute/ApplySuccess Job 化）→ REV-P6-3 Partial/Combination Allocation → REV-P6-4 Cancellation → REV-P6-5 Return/Restock → REV-P6-6 Reverse Recovery → REV-P6-7 Financial Convergence → REV-P6-8 Admin/Ops。
- 本 PRD 仅覆盖源 AC-6001~6035 中 P6-1 可实现子集；其余 AC 标注「后续包」，不在本 PRD 关闭。

---

## 1. 背景与目标

### 1.1 一句话需求原文

> 需求：REV-P6-1 Durable Refund Lifecycle Foundation（退款 durable 生命周期基础，闭合 orphan PSP refund）

### 1.2 背景（为什么做）

现有 `PallasTrade::Refund` 是 **successful-refund-only row**，存在三个结构性缺陷（2026-09-07 六层代码审计确认）：

1. **事故模型（RISK-REV-01，最高风险）**：`Refund` 通过 `after_create :perform!`（`refund.rb:30`）在 **DB 创建事务内同步调用 PSP**；网关成功后本地更新失败 → 整个 create 事务 rollback → **Refund 行消失**，形成 `PSP 已退钱 / Local 无 Refund / 无 provider reference / 无 Journal / 无 Recovery owner` 的 **orphan PSP refund**。
2. **失败不留痕**：`perform!` 内任何失败（超限/网关拒绝/连接错误）均 raise（`refund.rb:94-135`）→ 创建回滚，**无失败记录**，无法区分「明确失败」与「未知结果」。
3. **无生命周期/无 capacity 语义**：无 state；`Payment#credit_allowed`（`payment.rb:203-206`）只扣成功退款之和，无法表达 in-flight 退款占用 capacity → provider I/O 移出锁后（REV-P6-2 目标）会重现 double refund（RISK-REV-02/03）。

P0-P5 已就绪的复用基础：`refund.created` → `FinancialLedger::PostRefund`（P4，仅成功行可解析）；`FinancialFacts::ResolveRefund`；`ReconcileRefund`/`ReconcileSweeper`（cron `*/10`）；Stripe `fetch_refund_details`；`PaymentSplit.refunded_amount` 唯一写点 `Refund#update_order`（与创建同事务）；`Payment.with_lock` 并发防护。

### 1.3 REV-P6-0 语义冻结（本 PRD 依据，正式采纳）

| # | 冻结项 | 内容 |
|---|---|---|
| F-1 | REFUND_EXECUTION_AUTHORITY | `Refund` = Durable Refund Execution Aggregate；不新建 RefundRequest 表；FinancialFact 独立表达退款金融事实 |
| F-2 | PSP 副作用时序 | Provider side effect 只能在 durable Refund row 提交**之后**发生（AC-6001/6002） |
| F-3 | Refund Capacity | `requested / processing / ambiguous` 状态均占用 refundable capacity（AC-6007/6008/6009） |
| F-4 | Journal 语义 | 正常 Refund = `REFUND_SUCCEEDED` posting；`FinancialLedger::Reverse` 仅用于 Journal 记录纠错，**不是业务退款工具**（AC-6013/6014） |
| F-5 | 不回退原始事实 | 原始 `CommerceTransaction completed` 与 `Payment completed` 不因 Refund 倒退（AC-6015/6016）；COMMITTED Reservation 为终态（AC-6020） |
| F-6 | NO ReverseTransaction | 用 ReverseCommerce Application Layer 编排现有领域对象 |
| F-7 | Refund ≠ Cancellation ≠ Restock | 三事实分离，各自独立恢复（AC-6017~6026 由后续包逐步闭合） |

### 1.4 目标

1. `PallasTrade::Refund` 升级为带显式状态机的 **Durable Refund Execution Aggregate**：失败/未知结果持久化留痕，不再静默回滚。
2. 引入 **refund capacity reservation** 语义（active=requested/processing/ambiguous 占用额度），为 REV-P6-2 把 PSP I/O 移出 DB lock 铺路，杜绝并发双退。
3. 删除 `after_create :perform!`「create 即资金副作用」反模式；所有现有退款入口统一走「**先 durable 落库（requested）→ 显式 Execute**」。
4. 资金侧守卫：仅 `SUCCEEDED` 的 Refund 触发 `REFUND_SUCCEEDED` Journal posting；FAILED/requested/processing/ambiguous 不误入账。
5. 历史数据安全 backfill（state=succeeded），不伪造无法证明的 ownership（AC-6029）。
6. P0-P5 baseline 全绿（AC-6030~6035）。

### 1.5 成功指标

- `Refund` 任何失败路径都留有 durable 行（state ∈ {failed, ambiguous}），**orphan PSP refund 的「无本地 owner」分支消灭**。
- 现有退款相关 spec（gateway cancel 自动退款、Admin API create、reimbursement、P4 posting、reconciliation）全绿。
- Payment/Refund capacity 在并发 partial refund 下不超付（新增并发 spec 覆盖）。
- Admin API `POST /orders/:id/refunds` 响应携带 `state` 等生命周期字段。

---

## 2. 用户故事 / 场景

### 2.1 用户故事

- 作为 **Admin 运营**，我希望退款失败/超时后仍能看到 durable 记录与原因，以便不重复退款、正确人工介入。
- 作为 **系统（Refund orchestration）**，我希望每笔退款有稳定状态机与幂等键，以便 REV-P6-2/6 的 Job/Recovery 可在不产生第二笔退款的前提下收敛。
- 作为 **财务对账**，我希望只有真实成功的退款进入 Journal（REFUND_SUCCEEDED），失败/未知不污染资金事实。

### 2.2 场景

**正常流**
- N1 Admin 全退/部分退款成功：`requested → processing → succeeded`（transaction_id 持久化 → split/order 投影 → refund.succeeded → Journal）。
- N2 网关明确拒绝（余额不足/卡片关闭等）：`processing → failed`（留 last_error，释放 capacity，无 Journal）。
- N3 多次 partial refund：每笔独立 row/独立 PSP identity/独立 fact/独立 Journal entry（源 §26）。

**边界流**
- B1 同一 Payment 并发两笔退款合计超可退额：后到者在 capacity 校验被拒（create 校验 + Execute claim 锁内重校验）。
- B2 组合支付（`PaymentCombination`）：退款只更新目标 `PaymentSplit`/目标 Order，兄弟 split 不变（沿用 P7 逻辑，本包保持 succeeded-only split 语义，active 占用只在 Payment 级表达——REV-P6-3 深化）。
- B3 reimbursement 退货退款链（RA→CR→Reimb→Refund）：本包保留其外层事务内同步执行（见 FR-402 边界注记），仅确保失败持久化不 raise 吞掉报销 errored 语义。

**异常流**
- E1 网关成功但本地投影异常：Refund 停留在 processing/ambiguous（durable），本包保证 row 不消失 + 提供 `Refunds::Execute` 幂等重试入口（完整 Recovery=Sweeper 在 REV-P6-6）。
- E2 网关超时（结果未知）：→ `ambiguous`，**不得自动创建第二笔 Refund**（AC-6005 语义由状态机+capacity 保证，自动重试属 REV-P6-2/6）。
- E3 创建失败（超限/缺 payment）：不调用 PSP，不产生行（AC-6002）。

---

## 3. 功能需求（FR）

### 3.1 DB Schema（Migration 1：pallastrade_refunds）

- **FR-R61-101**：新增 `state` string，NOT NULL，default `'requested'`；白名单校验 ∈ REV_REFUND_STATES（见 FR-R61-201）。
- **FR-R61-102**：新增 ownership 可空列：`commerce_transaction_id`（FK `pallastrade_commerce_transactions`）、`target_order_id`（FK orders）、`payment_split_id`（FK `pallastrade_payment_splits`）。仅创建时可证明才填充（源 §24/25）；不允许事后猜填。
- **FR-R61-103**：新增 `provider_idempotency_key` string 可空 + **partial unique index**（`WHERE provider_idempotency_key IS NOT NULL`）。生成规则：`refund:{refund.prefixed_id}:execute`（创建即写，源 §17）。
- **FR-R61-104**：新增生命周期时间戳（可空 datetime）：`requested_at / processing_at / succeeded_at / failed_at / ambiguous_at`（各状态进入时写对应列）。
- **FR-R61-105**：新增 `last_error_code` / `last_error_message`（string，可空）、`attempt_count` integer NOT NULL default 0、`lock_version` integer NOT NULL default 0（乐观锁，供 REV-P6-2 并发 Execute 使用）。
- **FR-R61-106**：新增索引：`index_refunds_on_payment_id_and_state`（payment+state，capacity/scope 查询）、`index_refunds_on_state`。
- **FR-R61-107**：现有 `transaction_id`（provider refund reference，`re_`/provider ref）**兼容保留**为 succeeded 的唯一证据；新代码不新增对该模糊命名的依赖（注释迁移到 `provider_refund_reference` 语义）。

### 3.2 状态机与语义（Refund 模型）

- **FR-R61-201**：状态集合冻结 = `requested / processing / succeeded / failed / ambiguous / manual_review`（+ `canceled`，仅 requested 可取消）。常量 `PallasTrade::Refund::STATES` / `TERMINAL_STATES`（succeeded/failed/manual_review/canceled）/ `ACTIVE_STATES`（requested/processing/ambiguous，占用 capacity）。
- **FR-R61-202**：合法迁移（源 §9 图）：`requested → processing|canceled`；`processing → succeeded|failed|ambiguous`；`ambiguous → processing|succeeded|failed|manual_review`；`succeeded/failed/manual_review/canceled` 为终态。非法迁移 raise/validate 拒绝。
- **FR-R61-203**：scope：`active`（ACTIVE_STATES）、`succeeded`、`failed`、`ambiguous`、`needs_attention`（ambiguous|processing 超时由后续包扩展）。
- **FR-R61-204**：**删除 `after_create :perform!`**（源 §56/§13、REV-INV-03）；create 不再隐含 PSP 副作用。新增显式执行服务 `PallasTrade::Refunds::Execute`（FR-R61-301 起）。
- **FR-R61-205**：状态迁移发布生命周期事件（`publishes_lifecycle_events` 扩展）：`refund.succeeded` / `refund.failed` / `refund.ambiguous`（创建仍发布 `refund.created` 供审计）；事件在 **state transition commit 后** 发布（与现有 after_commit 机制一致）。

### 3.3 Refund Capacity（并发防双退）

- **FR-R61-301**：`Payment#refundable_capacity`（新）与 `Payment#credit_allowed` 语义升级：
  `amount − offsets_total.abs − Σ succeeded refunds − Σ active refunds(requested/processing/ambiguous)`。
  `failed / canceled / manual_review` **不占用** capacity（源 §14/15、AC-6007/6009）。
  `manual_review` 是否占用按 REV-P6-6 决策——本包先**不占用**（避免 deadlock，记录决策待 P6-6 复核）。
- **FR-R61-302**：`Refund` create 校验（`amount ≤ payment.refundable_capacity`）基于新语义；`amount_is_less_than_or_equal_to_allowed_amount` 迁移到新方法。
- **FR-R61-303**：`Refunds::Execute` claim 阶段 `payment.with_lock` 锁内**重校验 capacity**（排除自身），防止两笔并发都通过 create 校验（源 §15 canonical guard）。校验通过才 `requested→processing` 并 commit（锁内只做 claim，不做 provider I/O）。
- **FR-R61-304**：reimbursement 域的 `payment_credit_limits`（`reimbursement_type/reimbursement_helpers.rb:5-19`）语义保留（按 split/订单限定上限），但其读取的 `payment.credit_allowed` 自动获得 active-capacity 语义（P7 组合拆分逻辑不变；split 级 active 表达属 REV-P6-3）。

### 3.4 执行兼容策略（本 PRD 关键设计决策，需用户确认）

> **背景**：REV-P6-1 删除 after_create perform! 后必须有替代执行路径，否则 Admin 退款、gateway cancel 自动退款、reimbursement 退款全部失效。REV-P6-2 才引入 async Request/Execute/ApplySuccess + Job。本 PRD 提供 **v1 同步显式执行器**（同一 request 内完成，provider I/O 移出 DB lock），保证功能不破、durable 语义成立，为 P6-2 平滑升级。

- **FR-R61-401**：新增 `PallasTrade::Refunds::Execute`（幂等：仅 `requested` 可 claim；已 processing/succeeded 直接返回现状，不重复执行）。流程：`claim(requested→processing, tx) → commit → provider I/O（DB lock 外，携带 provider_idempotency_key）→ outcome apply`。
- **FR-R61-402**：迁移三个现有退款创建入口到「save(requested, commit) → Refunds::Execute」：
  1. Admin API `POST /api/v3/admin/orders/:id/refunds`（`refunds_controller.rb:16-27`）；
  2. Stripe/Adyen/PayPal gateway `cancel` 内对 completed payment 的自动退款（`stripe/gateway.rb:197`、`adyen/gateway.rb:84`、`paypal_checkout/gateway.rb:168`）；
  3. reimbursement 退货退款链（`reimbursement_type/original_payment.rb` + `reimbursement_helpers.rb`）。
  > **边界注记（需确认）**：入口 1/2 无外层事务，可实现「先落库后执行」的完整语义；入口 3 在 `Reimbursement#perform!` 外层事务内批量建多笔 refund，本包**保留链内同步执行**（Execute 在链内调用），provider I/O 仍在链事务内（AC-6003 对入口 3 暂不满足，标注 deferred → REV-P6-4/5 拆链时收口）。若确认不可接受，备选：入口 3 本包不动（保留 after_create），与 F-2 冲突，不推荐。
- **FR-R61-403**：provider I/O 调用携带稳定 idempotency：Stripe `Stripe::Refund.create(..., { idempotency_key: refund.provider_idempotency_key })`（Stripe 原生支持，幂等键全局唯一且含 refund id）；Bogus 实现确定性替身；Adyen/PayPal 不支持时记录键并跳过（能力不对称如实表达，源 §50）。
- **FR-R61-404**：结果持久化三态：
  - success → `ApplySuccess`（本地单事务）：state→succeeded + `transaction_id`=provider reference + `succeeded_at` + `PaymentSplit.refunded_amount`（组合场景，唯一写点 `Refund#update_order` 保留）+ Order updater + 审计 + 发布 `refund.succeeded`。
  - definite failure（网关明确拒绝）→ state→failed + `last_error_*` + `failed_at` + 释放 capacity + 发布 `refund.failed`；**不 raise 回滚**。
  - unknown/timeout/连接错误 → state→ambiguous + `last_error_*` + `ambiguous_at` + 发布 `refund.ambiguous`；**不释放 capacity、不自动重退**（源 §16/49）。
- **FR-R61-405**：`ApplySuccess` 独立可重入（幂等）：provider 已成功但本地投影失败的场景，重跑 ApplySuccess 不重复投影（split/order/journal 各幂等键/守卫）；本包以「state 仍 processing/ambiguous + transaction_id 存在 → 允许重放 ApplySuccess」实现（完整 Recover 服务 = REV-P6-6）。
- **FR-R61-406**：Admin API 契约调整：create 成功（durable requested）后同步执行，响应返回 Refund 终态字段（`state`/`transaction_id`/`last_error_message`）；执行失败不再表现为「无响应体 500」，而返回明确 state（failed/ambiguous）供前端/审计使用。**这是对现有调用方的行为变更，列入 §6 API 影响与 §8 测试。**

### 3.5 Financial Fact / Journal 守卫

- **FR-R61-501**：新增/调整 subscriber：`refund.succeeded` → `FinancialLedger::PostRefund`（替换现 `refund_created_subscriber` 依赖 create==success 的假设——当前 `refund_created_subscriber.rb:5-8` 注释「创建提交=perform! 成功」不再成立）；`refund.created` 仅审计，不再触发 posting。
- **FR-R61-502**：`FinancialFacts::ResolveRefund` 升级 state→fact 映射（源 §21）：`succeeded`→`REFUND_SUCCEEDED/CONFIRMED`（transaction_id 必在）；`requested/processing`→pending 语义（不 posting）；`failed`→failed（不 posting）；`ambiguous`→ambiguous（不 posting，待 P6-6 裁决）。只读边界不变。
- **FR-R61-503**：防呆 invariant：任何非 `succeeded` 的 Refund 不得产生 `REFUND_SUCCEEDED` FinancialLedgerEntry（补 spec 断言；Post 层 postable? 门禁作为第二道防线，复用 P4）。

### 3.6 历史数据 Backfill（Migration 2 / 数据迁移）

- **FR-R61-601**：历史 Refund 行 backfill `state='succeeded'`：判据 = `transaction_id IS NOT NULL`（当前持久化 Refund 必有 transaction_id——after_create 成功即 update_columns，失败即回滚；`validates :transaction_id on: :update` 兜底）。`transaction_id IS NULL` 的例外行（若有）→ `state='manual_review'` + 审计告警，**不猜 succeeded**（AC-6029）。
- **FR-R61-602**：ownership backfill：`commerce_transaction_id` 仅当可证明时填充（`payment → payment_session → commerce_transaction` 或 `payment → payment_combination → commerce_transaction`，源 §24）；不可证明 → 保持 NULL。**不填 target_order_id/payment_split_id**（组合场景经 reimbursement 链的推导属运行时 legacy fallback，本包不固化为列值以防猜错）。
- **FR-R61-603**：migration 前 dry-run 计数（总数/待 backfill/异常行）；backfill 语句幂等可重跑。

### 3.7 API / Serializer 最小暴露

- **FR-R61-701**：v3 `RefundSerializer` 与 admin `RefundSerializer` 增补字段：`state`、`requested_at/processing_at/succeeded_at/failed_at/ambiguous_at`、`provider_refund_reference`（映射 transaction_id）、`last_error_message`（admin only）。不新增路由（现有 `refunds#create` 语义升级见 FR-R61-406）。
- **FR-R61-702**：Store API 不暴露退款（现状保持）；仅 Admin API 变更。

---

## 4. 非功能需求（NFR）

- **兼容性**：P0-P5 baseline 全绿（AC-6030~6035）；现有正向支付/组合/cancel 链路零回归；reimbursement/returns 链路 spec 全绿。
- **幂等性**：Execute/ApplySuccess 幂等；同 Refund 所有 retry 使用同一 `provider_idempotency_key`（AC-6004）。
- **安全**：退款仍为敏感操作：现有权限（`can :manage, Refund`）+ `PallasTrade::Audit.record`（admin refunds create P0-6 审计）保留并覆盖新状态迁移；`last_error_message` 在 admin-only 序列化器暴露，不泄露 provider 敏感参数。
- **可维护性**：状态迁移集中为显式服务方法 + scope，禁止 controller/UI 内散落状态流转。
- **数据正确性**：Journal append-only 不变；capacity 不变量通过锁 + 应用层校验 + spec 保证（不依赖 DB CHECK——若采纳 P5-6 第一梯队，可另加金额 ≥0 CHECK，本包不强求）。

---

## 5. 验收标准（AC）

> 编号 AC-R61-xxx；「源」列引用 REV-P6 源文档 AC-60xx。**标记 (P6-2+)** 的 AC 不在本 PRD 关闭，仅声明本包为此建立的底座。

| AC | 源 | 验收条件 | 覆盖 FR |
|---|---|---|---|
| AC-R61-01 | AC-6001 | 任何 PSP refund 副作用前，本地必有 durable Refund row（state ∈ active）；Execute 只对已 commit 的 requested 行发起 provider 调用 | FR-R61-204/401 |
| AC-R61-02 | AC-6002 | Refund 创建失败（超限/校验错）→ 不调用 PSP、不产生行 | FR-R61-302 |
| AC-R61-03 | AC-6003 (部分) | 入口 1/2 的 provider I/O 不在 DB lock / 长事务内（Execute claim 与 PSP 调用分离）；入口 3（reimbursement 链）deferred → REV-P6-4/5 | FR-R61-303/401/402 |
| AC-R61-04 | AC-6004 | 同 Refund 所有 Execute/重试使用同一 `provider_idempotency_key`；create 即生成且不变 | FR-R61-103/403 |
| AC-R61-05 | AC-6005 (P6-2+) | timeout → ambiguous 且不自动新建第二笔 Refund（本包以状态机 + 无自动重试保证；自动 resolve 属 REV-P6-2/6） | FR-R61-202/404 |
| AC-R61-06 | AC-6006 (P6-2+) | PSP success + 本地 ApplySuccess 失败 → durable row 保持 processing/ambiguous 且可重放 ApplySuccess，不重复退款（Recovery 服务闭环属 REV-P6-6） | FR-R61-405 |
| AC-R61-07 | AC-6007 | requested/processing/ambiguous 均占用 `Payment#refundable_capacity` | FR-R61-301 |
| AC-R61-08 | AC-6008 | 并发 partial refund 总额 ≤ Payment refundable amount（create 校验 + claim 锁内重校验） | FR-R61-301/303 |
| AC-R61-09 | AC-6009 | FAILED 释放 capacity；canceled 释放 | FR-R61-301/404 |
| AC-R61-10 | AC-6010 | 一个 Payment 支持多笔成功 partial refund（每笔独立 row/state/fact） | FR-R61-301/404 |
| AC-R61-11 | AC-6013 | 正常 Refund（succeeded）产生 `REFUND_SUCCEEDED` Journal entry，不 Reverse 原 Payment entry | FR-R61-501/502/503 |
| AC-R61-12 | AC-6014 | 重复 post/重放 ApplySuccess 不产生重复 `REFUND_SUCCEEDED` entry（idempotency key + Post 幂等） | FR-R61-405/503 |
| AC-R61-13 | AC-6015 | Payment success 不因 Refund failure/ambiguous 被改写 | FR-R61-201 终态 + spec |
| AC-R61-14 | AC-6016 | CommerceTransaction 无 refund 事件、不倒退（回归断言） | F-5 |
| AC-R61-15 | AC-6029 | 历史 backfill：transaction_id 存在→succeeded；NULL 例外→manual_review + 告警，不伪造 | FR-R61-601/602 |
| AC-R61-16 | AC-6030~6035 | P0-P5 baseline 全绿（p0-payment-rspec / p1 / p2 / p3 / p4 / p5 verifier） | 全部 |
| AC-R61-17 | （本包新增） | 失败路径留痕：制造网关失败/超时后 Refund 行存在且 state ∈ {failed, ambiguous}，含 last_error | FR-R61-404 |
| AC-R61-18 | （本包新增） | Admin API create 响应含生命周期字段（state 等）；执行失败返回明确 state 而非无响应体 | FR-R61-406/701 |
| AC-R61-19 | （本包新增） | 非 succeeded Refund 不产生 REFUND_SUCCEEDED ledger entry（含 FAILED 场景 spec） | FR-R61-503 |
| AC-R61-20 | （本包新增） | 状态非法迁移被拒绝（如 succeeded→processing） | FR-R61-202 |

---

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | refund / reimbursement / return | 无宿主 override（审计确认宿主零 PSP/Refund 直连） | 否——本包改框架层 |
| Core | `pallastrade_gems/pallastrade_core/app/` | Refund / Payment / PaymentSplit / CommerceTransaction / ResolveRefund / PostRefund / OrderCancellation | `models/.../refund.rb`、`payment.rb`（credit_allowed）、`payment_split.rb`、`reimbursement_type/{original_payment,reimbursement_helpers}.rb`、`services/financial_facts/resolve_refund.rb`、`services/financial_ledger/post_refund.rb`、`subscribers/financial_ledger/refund_created_subscriber.rb`、`gateway/{bogus,stripe?}` | 部分——Refund 本体/资金接线已存在，需升级；`Refunds::Execute` 等**需新建** |
| API | `pallastrade_gems/pallastrade_api/app/` | refunds | `controllers/.../admin/orders/refunds_controller.rb`（index/create）、`serializers/.../refund_serializer.rb`、`admin/refund_serializer.rb` | 部分——create 入口与 serializer 需升级 state；无 Store 售后端点（保持） |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | refunds / reimbursements / returns | `refunds_controller.rb`、`reimbursements_controller.rb`、`customer_returns_controller.rb`（legacy 手动 fire） | 否——本包不动 legacy Admin 触发逻辑（行为由 Refund 层统一），完整 Ops UI = REV-P6-8 |
| Storefront | `storefront/src/` | refund / return | 无售后/退款 UI（仅取消文案 `FulfillmentBlock.tsx:82`） | 否——无影响 |
| Platform | `platform/packages/` | refund / refunds | admin-sdk 类型（经 OpenAPI 生成，无业务逻辑） | 部分——admin.yaml 更新后需同步生成类型 |

**结论**：能力集中在 Core（Refund/Payment/资金链）与 API（admin refunds create/serializer）。**需新建**：`PallasTrade::Refunds::Execute`（含 claim/apply）、state 迁移方法、`refund.succeeded` subscriber、migration。**无重复能力**：全仓不存在 durable refund lifecycle / capacity reservation / 显式执行器；`FinancialLedger::Reverse` 未接线且本包明确不使用（F-4）。

---

## 7. 技术影响

**涉及组件/文件（预计）**
- Core 模型：`refund.rb`（状态机/删除 after_create perform!/scope/ownership/ApplySuccess 投影）、`payment.rb`（refundable_capacity/credit_allowed）、`payment_combination.rb`/`payment_split.rb`（仅读取语义确认）。
- Core 服务（新建）：`services/pallastrade/refunds/execute.rb`（+ 内部 apply/claim）；subscriber：`subscribers/financial_ledger/refund_succeeded_subscriber.rb`（新建，替换 `refund_created_subscriber.rb` posting 职责）。
- Core 服务（更新）：`financial_facts/resolve_refund.rb`（state 映射）、`financial_ledger/post_refund.rb`（门禁复核，预计微调）。
- Provider gateway：`pallastrade_stripe/gateway.rb`、`pallastrade_adyen/gateway.rb`、`pallastrade_paypal_checkout/gateway.rb` 的 `cancel` 自动退款分支（改调 Execute）、Bogus。
- API：`admin/orders/refunds_controller.rb`（save 后 Execute + 契约）、`serializers/.../refund_serializer.rb`、`admin/refund_serializer.rb`。
- 数据：2 个 migration（schema + backfill）；`backend/db/schema.rb` 自动更新。
- 文档：`backend/public/api-docs/admin.yaml`（refunds create 响应 + state 字段）；`platform/docs/api-reference/admin.yaml`。

**影响面**：`harness affected --base origin/dev`（实施时运行并回填）。预计影响：core refund/payment 相关 spec、stripe/adyen/paypal gateway spec、api refunds request spec、P4 ledger/reconcile spec、reimbursement/returns spec（约数十个，见 §8）。

**风险（对齐源 §69）**
- RISK-REV-02/03（并发/ambiguous 双退）：由 FR-R61-301/303/404 在本包建立 capacity 底座，完整闭环 REV-P6-2。
- RISK-REV-05（组合 ownership）：本包不固化猜测值（FR-R61-602），REV-P6-3 处理 split active reservation。
- RISK-REV-07（Adyen/PayPal 能力）：如实不对称（FR-R61-403），ambiguous → manual_review 语义保留给 P6-6。

---

## 8. 测试计划

**新增测试文件**
- `backend/spec/models/pallastrade/refund_lifecycle_spec.rb`（新建，状态机迁移/scope/终态/非法迁移）→ AC-R61-05/13/14/20
- `backend/spec/services/pallastrade/refunds/execute_spec.rb`（新建：claim 幂等/capacity 重校验/三态结果/ApplySuccess 重放）→ AC-R61-01/03/06/08/17
- `backend/spec/subscribers/pallastrade/financial_ledger/refund_succeeded_subscriber_spec.rb`（新建：仅 succeeded posting）→ AC-R61-11/19
- `backend/spec/models/pallastrade/payment_refund_capacity_spec.rb`（新建：capacity 语义含 active/failed）→ AC-R61-07/09/10

**更新测试文件**
- `backend/spec/models/pallastrade/refund_spec.rb`：移除对 after_create perform! 的隐含依赖，改显式 Execute 断言 → AC-R61-02/10
- `backend/spec/models/pallastrade/payment_spec.rb`：credit_allowed 新语义
- `backend/spec/services/pallastrade/financial_facts/resolve_refund_spec.rb`：state 映射
- `backend/spec/requests/api/v3/admin/orders/refunds_controller_spec.rb`：契约（state 字段/失败态）→ AC-R61-18
- `backend/pallastrade_gems/pallastrade_{stripe,adyen,paypal_checkout}/spec/models/gateway_spec.rb` 等：cancel 自动退款分支改显式 Execute 后的断言；reimbursement/returns 相关 spec
- `backend/spec/models/pallastrade/reimbursement_type/original_payment_spec.rb`（若有）：limit/credit 语义
- P4 ledger/reconcile spec：refund posting 时序（succeeded 事件）适配

**覆盖的 AC 映射**
- 每 spec 头部标注 `# PRD-REV-P6-1 AC-R61-xx`；source AC 引用同注。
- Baseline：运行 `p0-payment-rspec`/`p1`/`p2`/`p3`/`p4`/`p5` verifier（AC-R61-16）。

---

## 9. 文档同步清单（知识同步门）

- [ ] API 文档：`backend/public/api-docs/admin.yaml` + `platform/docs/api-reference/admin.yaml`（refunds create 响应 state/生命周期字段；无新路由）
- [ ] SDK 类型：`pnpm --filter @pallastrade/admin-sdk generate:types`（若响应 schema 变更）
- [ ] Skill：`ai/skills/pallastrade-payments/SKILL.md`（Refund 生命周期/Execute/capacity 语义）；`ai/skills/pallastrade-data-model/SKILL.md`（refunds 表新列）
- [ ] 反模式库：`harness/policies/anti-patterns.json` + AGENTS.md §5 + copilot-instructions（新增反模式：「after_create 即资金副作用 / create 内同步 PSP」→ 对应 FR-R61-204）
- [ ] 场景库：`harness/scenarios/scenarios.json`（新增 Eval Scenario：durable refund lifecycle + orphan PSP refund 防回归）
- [ ] 本 PRD 状态更新 + `docs/prd/README.md` 索引
- [ ] `harness doc-impact --base origin/dev`（实施后校验）
- [ ] 编号体系说明（REV-P6 vs 内部 P5/P6/P7）如需登记至 AGENTS.md §0.2 或相关 skill

---

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-06 | 0.1 | 初稿（依据 REV-P6 源文档 §54-56 + 2026-09-07 六层代码审计） | AI |
| 2026-09-06 | 0.2 | 实施：migration+backfill、Refund 状态机/ownership/scope、Refunds::Execute、Payment capacity、三 gateway cancel 与 Admin/reimbursement 入口切显式 Execute、refund.succeeded subscriber、serializer、admin.yaml、GS-059、payments skill 同步；新增 lifecycle/capacity/execute/subscriber spec（21 新例 + 回归 35/33/81/33 全绿） | AI |
