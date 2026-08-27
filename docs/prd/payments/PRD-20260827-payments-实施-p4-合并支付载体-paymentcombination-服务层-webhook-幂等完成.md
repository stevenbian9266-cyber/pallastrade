# PRD-20260827-payments-实施-p4-合并支付载体-paymentcombination-服务层-webhook-幂等完成

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-08-27 |
| 来源 | 需求：实施 P4 合并支付载体（PaymentCombination 服务层 + Webhook 幂等完成） |
| 分类 | payments（自动判定） |
| 关联 Skill | pallastrade-payments、pallastrade-events-webhooks、pallastrade-checkout、pallastrade-testing |
| 关联 REQ | REQ-20260827-order-lifecycle-p4.md（实施时回填） |
| 关联 PRD | N/A（全新阶段，承接 PRD-20260827-payments-实施-p3） |
| 需求类型 | 新功能（能力层服务，默认关闭，P5 接线） |

---

## 1. 背景与目标

- **一句话需求原文**：需求：实施 P4 合并支付载体（PaymentCombination 服务层 + Webhook 幂等完成）
- **背景**：
  - P1 已落地数据层：`PaymentCombination`（`pcom_`，状态机 `pending → processing → succeeded|failed|canceled|expired`，非法迁移抛业务错误）+ `PaymentSplit`（每成员订单一条，唯一索引 `[combination_id, order_id]`）+ `orders/payments/payment_sessions.payment_combination_id` 可空列——**但尚未有任何服务接入**。
  - P2 拆单引擎已会用 `PaymentSplit` 做记账分摊（`payment_combination` 为空）。
  - P3 聚合派生已就绪（`combined_*` / `effective_payment_total`）。
  - P4 实现**服务层闭环**：`PaymentCombinations::Create`（发起合并支付）+ `PaymentCombinations::Complete`（幂等完成，**先入账后完成**，部分失败补偿）+ Webhook 接线 + 补偿队列。**默认关闭、不暴露端点**，P5 才接线 Checkout/收银台。
  - 吸取 2026-08 PaymentGroup 失败教训：session↔payment 保持 1:1；单事务多订单完成导致"钱扣了单没完成"→ 改为先入账支付、逐订单完成、失败进补偿队列。
- **目标**：提供可被 P5 调用的合并支付服务层：组合创建/完成、跨订单资金记账（PaymentSplit）、幂等 Webhook 完成、失败订单补偿。
- **成功指标**：Create/Complete 幂等（重复调用不重复入账）；组合支付只产生 1 个 `PaymentSession` + 1 个 `Payment`；部分订单完成失败时已入账资金不回滚、失败订单 `balance_due` 且入队重试；全部新增 spec 绿 + 既有支付链路零回归。

## 2. 用户故事 / 场景

- 作为 **买家**，我希望把多笔待支付订单（如同一拆单的父/子订单、或历史未付订单）合并成一次支付，以便一次扣款完成多笔订单。
- 作为 **平台**，我希望组合支付成功后资金按订单逐笔入账、失败订单可补偿，以便资金一致性始终 >= 订单状态。
- 场景：
  - **S1（正常流）**：2 笔未支付订单（各 $50/$30）→ Create 组合（金额 $80，服务端计算）→ primary 订单建 Session → 网关扣款成功 → Webhook/回调 → Complete：组合 succeeded、1 个 Payment($80)、2 条 PaymentSplit、2 订单均完成。
  - **S2（幂等）**：Webhook 与前端回调同时到达（或 job 重试）→ Complete 只入账一次、只完成一次。
  - **S3（部分失败）**：组合支付成功后某订单因库存/校验失败 → 已入账资金保留，失败订单 `balance_due` + 入 `CombinationSettleJob` 重试，不整体回滚。
  - **S4（边界）**：传入已支付订单 / 跨 store / 跨用户 / 跨币种 → Create 拒绝。
  - **S5（异常）**：支付失败（网关拒绝）→ 组合 `failed`，成员订单保持未支付、可重试。

## 3. 功能需求（FR）

- **FR-001**：`PallasTrade::Payments::PaymentCombinations::Create`——入参 `(store:, customer:, orders:, payment_method:, primary_order:)`；校验同 store/同用户/同币种、仅未支付（`outstanding_balance > 0`）订单计入；创建组合（`pending`）+ 每成员订单一条 `PaymentSplit`（`payment_combination` 归入组合）+ primary 订单 `PaymentSession`（金额=组合合计，挂组合）；组合 → `processing`。
- **FR-002**：组合金额由**服务端计算**：`amount = Σ 成员订单 amount_due`（未支付订单才计入），客户端金额不作为信任输入。
- **FR-003**：`PallasTrade::Payments::PaymentCombinations::Complete`——幂等完成：组合 → `succeeded`；**先入账支付**（1 个 `Payment` 挂组合 `order_id=nil`、金额=组合合计、completed；各成员 `PaymentSplit#captured_amount` 记账；各订单 `payment_state` 更新）；**再逐个订单完成**（`checkout_complete_service`）。
- **FR-004**：一致性兜底——某订单完成失败时**不回滚已入账支付**，将该订单标记 `balance_due` + 写入异常，入 `PallasTrade::Payments::CombinationSettleJob` 重试（资金始终 >= 订单状态）。
- **FR-005**：Webhook 接线——当 `PaymentSession#payment_combination` 存在时，支付成功走 `PaymentCombinations::Complete`（而非单订单完成路径）；`HandleWebhook`（core）与 Stripe `CompleteOrderFromSessionJob` 两路径都收敛到同一完成服务。
- **FR-006**：幂等——组合已 `succeeded` / session 已 `completed` / 订单已完成 → 直接跳过；重复 webhook、job 重试、双路径（API+webhook）均不重复入账。
- **FR-007**：保持 `session ↔ payment` 1:1——组合支付只允许一个 `PaymentSession`（挂 primary order）+ 一个 `Payment`（挂组合，`order_id=nil`），子订单用 `PaymentSplit` 记账，禁止一个 session 对应多个 payment。
- **FR-008**：`PallasTrade::Payments::CombinationSettleJob`——补偿队列：对失败成员订单重试完成，幂等（已完成跳过），重试耗尽后保留 `balance_due` 供人工介入。

## 4. 非功能需求（NFR）

- **幂等**：Create 对同组订单重复调用不产生重复组合/重复 split（唯一索引 + 状态守卫）；Complete 双路径幂等。
- **一致性**：先入账支付、再逐订单完成；部分失败不回滚已入账资金（`资金 >= 订单状态`），失败订单入队补偿。
- **安全**：金额服务端计算，防客户端篡改。
- **可维护**：沿用现有服务层模式（`ServiceModule::Base`）+ 状态机业务错误（`InvalidTransitionError`），不引入新框架。
- **兼容**：默认关闭、不暴露端点、不动 Storefront/Platform/SDK；既有单订单支付链路零改动。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001 ← FR-001**：Create 传入跨 store / 跨用户 / 跨币种订单 → 返回业务错误，不创建组合。
- **AC-002 ← FR-002**：Create 金额 = Σ 未支付订单 `amount_due`；已支付订单不计入；客户端金额参数被忽略（服务端计算）。
- **AC-003 ← FR-001/FR-007**：Create 成功 → 组合 `pending→processing`；每成员订单一条 `PaymentSplit`（归入组合）；primary 订单一个 `PaymentSession`（金额=组合合计、挂组合）。
- **AC-004 ← FR-006**：Complete 重复调用（webhook + API 双路径 / job 重试）→ 只入账一次（1 个 Payment、splits 不翻倍、订单只完成一次）。
- **AC-005 ← FR-003**：Complete 成功 → 组合 `succeeded`；1 个 `Payment`（`order_id=nil`、金额=组合合计、completed）；各 split `captured_amount` 入账；成员订单全部完成且 `paid`。
- **AC-006 ← FR-004**：一个成员订单完成失败 → 已入账支付保留（组合 succeeded + Payment completed）；失败订单 `balance_due`；`CombinationSettleJob` 入队。
- **AC-007 ← FR-005**：webhook 成功且 session 挂组合 → 走 `PaymentCombinations::Complete`，成员订单全部完成（含 primary + 其他成员）。
- **AC-008 ← FR-007**：组合支付全程只产生 1 个 `PaymentSession` + 1 个 `Payment`（`order_id=nil`）；`session ↔ payment` 保持 1:1。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | payment_combination, PaymentSplit | 无 | 否——P4 工作在 Core 服务层，App 无重复能力 |
| Core | `pallastrade_gems/pallastrade_core/app/` | PaymentCombination, PaymentSplit, PaymentSession, HandleWebhook, Carts::Complete, payment_sessions | `models/pallastrade/payment_combination.rb`（P1 状态机+契约）、`payment_split.rb`、`payment_session.rb`（P1 加 `payment_combination_id`）、`services/pallastrade/payments/handle_webhook.rb`、`jobs/pallastrade/payments/handle_webhook_job.rb`、`services/pallastrade/carts/complete.rb`、`order.rb`（P1 `payment_sessions`/`payment_splits` 关联 + P3 `effective_payment_total`） | **部分**——数据层与 Webhook 骨架已存在，**需新建 Create/Complete 服务 + 组合 Webhook 分支 + 补偿 Job** |
| API | `pallastrade_gems/pallastrade_api/app/` | payment_session, combination | `controllers/.../store/carts/payment_sessions_controller.rb`（现有单订单 session 创建端点） | 否——无组合端点（P5 暴露），P4 不动 API |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | payment_combination | 无 | 否——P4 不动 Admin（P6 手动拆单才涉及） |
| Storefront | `storefront/src/` | payment_combination, 合并支付 | 无 | 否——P4 不动 Storefront（P5 合并支付收银台） |
| Platform | `platform/packages/` | payment_combination | 无 | 否——P4 不动 SDK（P5 加类型） |

**结论**：P4 全部工作集中在 **Core 服务层 + Stripe 网关接线**。数据层（P1）、聚合派生（P3）已就绪，无跨层重复能力需防；API/Admin/Storefront/Platform 均不涉及（P5/P6 接线）。

## 7. 技术影响

- **新增**（Core）：
  - `backend/pallastrade_gems/pallastrade_core/app/services/pallastrade/payments/payment_combinations/create.rb`
  - `backend/pallastrade_gems/pallastrade_core/app/services/pallastrade/payments/payment_combinations/complete.rb`
  - `backend/pallastrade_gems/pallastrade_core/app/jobs/pallastrade/payments/combination_settle_job.rb`
- **修改**（Core Webhook 接线）：
  - `services/pallastrade/payments/handle_webhook.rb`——`handle_success` 增加组合分支（session 挂组合 → 调 `PaymentCombinations::Complete`）
- **修改**（Stripe 网关）：
  - `backend/pallastrade_gems/pallastrade_stripe/app/jobs/pallastrade_stripe/complete_order_from_session_job.rb` 或 `complete_order.rb`——session 挂组合时走组合完成
- **依赖**：P1 数据层（`payment_combination_id`、`PaymentSplit`）；P3 `effective_payment_total`；现有 `checkout_complete_service`（`PallasTrade::Dependencies`）
- **数据库**：无新迁移（P1 已建表/列）
- **影响面**：Core 服务层 + Stripe 接线，默认关闭；`harness affected --base origin/main` 实施时确认

## 8. 测试计划

- **新增**：
  - `backend/spec/services/pallastrade/payments/payment_combinations_create_spec.rb`（AC-001/002/003）
  - `backend/spec/services/pallastrade/payments/payment_combinations_complete_spec.rb`（AC-004/005/006/008）
  - `backend/spec/jobs/pallastrade/payments/combination_settle_job_spec.rb`（AC-006）
  - `backend/spec/services/pallastrade/payments/handle_webhook_combination_spec.rb`（AC-007）
- **更新**：`backend/spec/models/pallastrade/payment_combination_spec.rb`（如需补充组合服务相关守卫）
- **覆盖映射**：AC-001~003 → create_spec；AC-004~006/008 → complete_spec + settle_job_spec；AC-007 → handle_webhook_combination_spec
- **运行**：`harness check --profile quick` + 相关 rspec（docker exec pallastrade-web-1）

## 9. 文档同步清单（知识同步门）

- [x] 本 PRD 状态更新 + `docs/prd/README.md` 索引（P4 已建索引，状态随提交更新）
- [x] `ai/skills/pallastrade-payments/SKILL.md`（新增「合并支付服务层（P4）」：Create/Complete/幂等/补偿/Webhook 分支/数据配套）
- [x] `ai/skills/pallastrade-data-model/SKILL.md`（新增「合并支付数据配套（P4）」：payment_id 可空 + Payment#order optional + payments 关联 + OrderUpdater split 分支）
- [x] `ai/skills/pallastrade-checkout/SKILL.md`（新增「组合支付订单完成（P4）」：状态机放行 + 完成入口）
- [x] `ai/skills/pallastrade-events-webhooks/SKILL.md`（新增「组合支付 Webhook 分支（P4）」）
- [x] API 文档：P4 无新端点，`backend/public/api-docs/{store,admin}.yaml` 已评估无需变更（P5 暴露组合端点时同步）
- [x] 升级方案 `docs/research/RESEARCH-20260826-order-lifecycle-upgrade-plan.md`（P4 段标记完成）
- [x] 其他 sync-check 命中项（addresses_controller / CheckoutPageContent / deploy 等历史变更）已评估，与 P4 无关无需更新

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-27 | 0.1 | 初稿：P4 合并支付载体服务层（Create/Complete/Webhook 接线/补偿队列） | AI |
| 2026-08-27 | 0.2 | 实施完成：PaymentCombinations::Create/Complete（先入账后完成/幂等/失败补偿）+ CombinationSettleJob + HandleWebhook/Stripe 组合分支 + Payment/OrderUpdater/checkout 状态机配套；15 新 spec + 39 回归全绿；gate GATE-2026-08-27T14-02-37 关闭；同步 4 个 Skill + 升级方案 | AI |
