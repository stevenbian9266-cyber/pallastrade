# PRD-20260908-payments-rev-p6-8f-combination-level-cancel-orchestration

| 元数据 | 值 |
|---|---|
| 状态 | done（8f 1.0 + REV-P6-8k 1.1，见文末 §11） |
| 创建日期 | 2026-09-08 |
| 来源 | 需求：REV-P6-8f OrderCancellation 组合级取消编排（split-aware 取消退款 + CombinationCancel 编排器 + Admin API） |
| 分类 | payments（语义归属；组合资金/取消编排） |
| 关联 Skill | pallastrade-payments / pallastrade-api-v3 / pallastrade-customization |
| 关联 REQ | REQ-20260908-rev-p6-8f-combination-level-cancel.md |
| 关联 PRD | REV-P6-4（Cancellation Orchestrator，FR-R64-106 边界「完整组合取消编排延后」）；REV-P6-3（组合 split 冻结退款）；REV-P6-8a~8e（done） |
| 需求类型 | 优化迭代（组合资金语义收敛，feature gate） |

> 源：`豆包…/P6` §30-35（Cancellation Boundary / Paid Cancellation / Intent durable）+ §27-28（Combination
> Refund 按 split）+ §45（编排消费事实）。**本包 = OrderCancellation 组合级取消编排**：修复 PAID 组合成员
> 取消**零退款**（资金滞留）缺口 + 新增 succeeded 组合的**整组/子集取消编排** + Admin API 入口。不改
> CommerceTransaction/PaymentCombination 状态机（PAID 不走 cancel 态）；资金一律 durable
> `Refunds::Request(enqueue:false)` + 提交后 `ExecuteJob`（AP-010）。

## 1. 背景与目标

REV-P6-4 后 `Orders::Cancel`（=Cancellation Orchestrator）对 PAID 订单在事务内建 durable Refund(requested)。
但**组合支付成员订单的资金不在本地 payment 行**（组合 Payment 挂 combo、`order_id=nil`，成员经
`PaymentSplit` 记账，settlement 已回填 `split.payment_id`）——`Orders::Cancel#completed_refundable_payments`
=`Payment.where(order_id:)` → 成员返回空 → **PAID 成员被取消时即使 refund_payments:true 也不建任何 Refund**
（G1：资金滞留 + 库存已 restock 的"白取消"）。同时 succeeded 组合**无任何组合级取消入口**（combo/txn 的
`cancel` 事件只覆盖 pending/processing；FR-R64-106 边界注释明示组合级取消编排延后）→ G2。

目标：
1. **G1 修复**：取消决策 split-aware——PAID 组合成员的可退资金权威源=冻结 `PaymentSplit`（组合 Payment +
   `payment_split_id`/`target_order_id` ownership），经 `Orders::Cancel` 单一路径建 durable 退款；
2. **G2**：新增组合级取消编排服务 `Orders::CombinationCancel`（succeeded 组合整组/子集取消，逐成员复用
   `Orders::Cancel`，聚合 Result，幂等/单成员失败不中断）；
3. **G3**：Admin API v3 组合取消端点（current_store 作用域 + prefixed id + `{data:{…}}`）。

成功指标：PAID 组合成员经任何取消入口（单订单 API/Rails Admin/编排器）取消都产生正确 split durable 退款；
succeeded 组合可一次编排整组取消且不重复建 Refund；组合逐成员已退/取消可视化聚合；全量绿。

## 2/3. FR

- FR-R68F-101（split-aware 取消退款）：`Orders::Cancel` 增加组合成员识别——订单无可退本地 PSP payment 但
  存在 `settled_combination_split(order)`（`PaymentSplit`：挂 succeeded `PaymentCombination` 且
  `payment_id` 非空且 `credit_allowed > 0`）时，该 split 视为单一可退源：
  - auto（refund_payments nil）→ 有可退源即退（成员默认全额退 split.credit_allowed）；
  - `refund_amount` 仅限单可退源（本地单笔 PSP 或单 split），金额 = `min(refund_amount, split.credit_allowed)`；
  - 建单经 `Refunds::Request(payment: split.payment, payment_split: split, target_order: order,
    amount:, reason: order_canceled_reason, enqueue: false)`（冻结 ownership + split 上限校验
    `amount_within_frozen_split_limit` + 组合 Payment capacity 校验）；事务提交后统一 ExecuteJob。
  - 不触碰本地 payment 行 / 不改 after_cancel store-credit credit-back 语义。
- FR-R68F-102（组合级编排器）：`Orders::CombinationCancel.call(combination:, canceler:, member_ids: nil,
  reason:, note:, restock_items:, refund_payments:, notify_customer:)` → `Result`：
  - 前置守卫：组合非 succeeded → failure（不编排）；`member_ids`（可空）经 prefixed 解码并过滤到组合成员；
  - 逐成员：已 canceled → skip(`already_canceled`)；`allow_cancel?` false → skip(`not_cancellable`)；
    否则 `Orders::Cancel.call(...)`（含 FR-101 split-aware）；success → canceled 列表 / failure →
    failed 列表（错误信息聚合，**不中断其他成员**，镜像 8e 单条 rescue 哲学）；
  - 输出聚合 `{ combination_id, members: { total, canceled, skipped, failed },
    canceled: [{order_id, order_number}], skipped: [{order_id, reason}], failed: [{order_id, error}] }`；
    不 raise；重复调用幂等（已取消 skip → 不重复 Refund）。
- FR-R68F-103（Admin API）：`POST /api/v3/admin/payment_combinations/:id/cancel`
  - body：`member_ids?`（prefixed order ids 数组，缺省=全部未取消成员）/ `reason` / `note` /
    `refund_payments`(三态) / `restock_items` / `notify_customer`；
  - `PaymentCombination.accessible_by(current_ability, :cancel).where(store_id: current_store.id)`
    + `find_by_prefix_id!`（`pcom_`）；authorize `:cancel`；
  - 响应 `{ data: { id: 'pcom_…', type: 'payment_combination', attributes: { status, members:
    {total,canceled,skipped,failed}, … } } }`（编排结果聚合；退款终态经既有 refunds 端点观测）；
    非法 id → 404 / 无权限 → 403 / 非 succeeded → 422。
- FR-R68F-104（能力规则）：`order_management` permission set 增加
  `can :cancel, PallasTrade::PaymentCombination, &:succeeded?`（super_user manage 天然覆盖）；
  组合控制器在 admin 命名空间下新增 `resources :payment_combinations, only: [] { member { post :cancel } }`。
- 边界（记录不实施）：CommerceTransaction/PaymentCombination 状态机不加 PAID cancel 态；Rails Admin 组合
  可视化与退款/取消聚合展示（G6，与 REV-P6-8a 归并规划）；OrderCancellation 状态机化与取消意图恢复
  （§34/recover.rb:16 边界）；组合级 `payment_combination.*` 取消事件（订阅者暂缺，先复用每成员
  order.canceled）。

## 4. NFR
资金 I/O 只走 ExecuteJob（AP-010）；durable requested 先于任何资金副作用；冻结 split ownership 不可事后猜；
单成员失败不中断整组合（聚合可观测）；重复/并发取消幂等（allow_cancel?/canceled? 兜底，split credit 上限二道
防线）；不改 combo/txn 状态机与 pre-payment cancel 语义；只读为主 + 既有写通道复用。

## 5. AC
| AC | 条件 | FR |
|---|---|---|
| AC-R68F-01 | PAID 组合成员经 Orders::Cancel（auto）取消 → 建 1 笔 durable Refund(requested) 于组合 Payment + 冻结该成员 PaymentSplit/target_order，金额=split.credit_allowed；订单 canceled；事务提交后 enqueue ExecuteJob | 101 |
| AC-R68F-02 | refund_payments:false → 不建 Refund；refund_amount 在 split credit 内生效，超限建单失败 → 取消整体回滚 | 101 |
| AC-R68F-03 | CombinationCancel(succeeded combo, 2 个可取消 PAID 成员) → 两成员 canceled + 2 笔 split Refund(requested)，聚合 canceled=2 | 102 |
| AC-R68F-04 | 已 canceled 成员 skip(already_canceled)；不可取消成员（shipped/processing）skip(not_cancellable) 不中断其他成员 | 102 |
| AC-R68F-05 | 非 succeeded 组合 → failure 不编排；member_ids 子集只取消指定成员；member_ids 无有效匹配 → failure | 102 |
| AC-R68F-06 | 重复调用 CombinationCancel/端点 → 幂等，不重复建 Refund | 102 |
| AC-R68F-07 | Admin API POST /admin/payment_combinations/:id/cancel → 200 {data} 聚合；current_store 作用域 + pcom_ id；无权限 403 / 不存在 404 / 非 succeeded 422 | 103 |
| AC-R68F-08 | 单成员取消异常 rescue → failed 聚合，不中断整组合 | 102 |
| AC-R68F-09 | 回归：单订单（非组合）取消行为不变；pending/processing 组合 cancel 语义不变；全量 backend-rspec ×2 + quick check + doc-impact | 全部 |

## 6. 跨层搜索（节选；每层独立）
- backend/app：无 orders/cancel override（仅 ai_controller）；无组合取消宿主代码。
- core：`Orders::Cancel`（决策矩阵/durable refund，REV-P6-4）；`Refunds::Request`（enqueue:false +
  ownership 冻结）；`Refund`（amount_within_frozen_split_limit/split 上限/update_order 唯一写点）；
  `PaymentCombination`（succeeded/cancel 仅 pending/processing/orders through payment_splits）；
  `PaymentSplit`（credit_allowed = captured − refunded，payment 回填）；`CommerceTransaction` cancel 仅
  pre-payment。**无组合级取消编排者（缺口 G1/G2）**。
- api：Admin `orders/:id/cancel`（REV-P6-4 透传）；admin routes 无 combo 资源（缺口 G3）；store 有
  payment_combinations create/show（客户侧无取消，符合语义）。
- admin：Rails Admin 无 PaymentCombination 管理页（G6 另列）；TransactionsController 无涉。
- storefront：无取消 UI（账户多选合并支付 OrderCombinedPay 只创建组合）；webhook 仅邮件。
- platform：SDK/Admin-SDK 无组合取消方法（随 admin.yaml 同步判定）。

## 7. 技术影响
- core：`services/pallastrade/orders/cancel.rb`（+split-aware 源识别与建单）；`services/pallastrade/orders/
  combination_cancel.rb`（新）；`models/pallastrade/permission_sets/order_management.rb`（+can :cancel
  PaymentCombination）。无 migration（payment_split_id/target_order_id 已存在）。
- api：`config/routes.rb`（admin + resources :payment_combinations member cancel）；`controllers/.../v3/admin/
  payment_combinations_controller.rb`（新）。
- 接口文档：`backend/public/api-docs/admin.yaml`（+POST /admin/payment_combinations/{id}/cancel）；
  按 `generated:check` 结果同步 SDK。
- specs：orders cancel split-aware（真组合 fixture）、combination_cancel（2 成员/子集/skip/幂等/非 succeeded）、
  request spec（admin cancel 端点）。
- 无 migration / 无 sidekiq 新任务 / 无 UI。

## 8. 测试计划
组合 fixture：直接构建 succeeded PaymentCombination + 每成员 PaymentSplit(captured/refunded=0, payment 回填
组合 payment completed) + 成员订单 state=paid/status=placed（镜像既有 combo settlement spec 模式，避免全链路
settlement 成本）；断言行级 + enqueue（assert_enqueued_with ExecuteJob）。回归：orders cancellation 既有
spec、refund/request/8a-8e、reconcile、quick check + 全量 ×2 + doc-impact + generated:check。

## 9. 文档同步清单
- [x] payments skill（REV-P6-8f 节：split-aware 取消 + CombinationCancel + API）；scenarios GS-073；api-v3 skill 端点节；
  PRD/REQ/README；admin.yaml（接口变更）+ generated:check；doc-impact。
- [x] 边界记录：状态机不加 PAID cancel 态、Rails Admin 组合可视化、OrderCancellation 状态机化、组合事件 →
  后续。

## 10. 变更记录
| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-08 | 0.1 | 初稿（依据跨层调研：G1 零退款 + G2 无入口 + G3 无 API；FR-R64-106 边界落地） | AI |
| 2026-09-08 | 1.0 | done：实施完成（commit 7347234）——split-aware Orders::Cancel + CombinationCancel + Admin API + admin.yaml；spec 14/14、回归 68 例、全量 backend-rspec ×2 绿、quick check/generated:check/doc-impact 过 | AI |
| 2026-09-09 | 1.1 | REV-P6-8k（8f 边界落地）初稿：组合级取消编排事件 `payment_combination.cancel_orchestrated` + 审计/metrics 订阅者（见 §11；task TASK-20260909032549-ef07c9b7） | AI |
| 2026-09-09 | 1.2 | REV-P6-8k done：实施完成（需求 commit 78e3476，task finished）——事件发布（canceled>0）+ CombinationCancelSubscriber（Audit+OperationalMetrics）+ engine 注册；spec 16 绿+回归 26 绿+全量 ×2 绿+quick 干净+doc-impact 过；GS-078；payments skill 8k 节 | AI |

---

## 11. REV-P6-8k —— 组合级取消编排事件 + 审计/metrics 订阅者（8f 边界落地）

> 8f §2/3 边界「组合级 `payment_combination.*` 取消事件（订阅者暂缺，先复用每成员 order.canceled）」落地。
> 任务：需求：REV-P6-8k（task TASK-20260909032549-ef07c9b7；引擎判定 risk critical → manual-only recovery plan + 四类 evidence）。

### 11.1 背景与语义决策

8f 编排器 `Orders::CombinationCancel` 逐成员复用 `Orders::Cancel`，每个成员发自己的 `order.canceled`；
组合这一层**没有任何聚合事件**——想对「整组合被取消/部分取消」做联动（组合级审计、运营计数、未来 ERP/通知）
无钩子。

**命名决策**：`PaymentCombination` 状态机已有 `cancel` 事件（pending/processing→canceled，发布
`payment_combination.canceled`，当前零消费者、无 payload）——那是 **pre-payment 组合自身终态取消**；而
8k 编排事件发生在 **succeeded 组合被成员取消编排**（组合状态仍 succeeded，不变）。两者语义不同，若共用
`payment_combination.canceled` 会使消费者无法区分。故 8k 采用**独立事件名**
`payment_combination.cancel_orchestrated`（payload 带成员结果聚合），状态机 canceled 事件保持不变（不合并）。

### 11.2 FR
- FR-R68K-101（编排事件）：`Orders::CombinationCancel#call` 编排结束且 `canceled > 0` → 调
  `combination.publish_event('payment_combination.cancel_orchestrated', payload)`。payload 含
  `{ id: combination.prefixed_id, status: combination.status('succeeded'), members:{total,canceled,skipped,failed},
  canceled_order_ids: [prefixed], skipped_order_ids: [prefixed], failed_order_ids: [prefixed], canceled_by: (canceler 标识或 'system') }`。
  全部 skip/失败（canceled==0）不发（无实质取消，避免噪音）；幂等：重跑仅影响仍可取消成员，每次实际取消发一次。
- FR-R68K-102（订阅者）：`PallasTrade::Orders::CombinationCancelSubscriber < PallasTrade::Subscriber`，
  `subscribes_to 'payment_combination.cancel_orchestrated'`（默认 async → SubscriberJob）：
  - payload id 支持 prefixed（pcom_）或 raw 双模（镜像 FinancialLedger succeeded 订阅者）；combination 缺失 no-op；
  - `PallasTrade::Audit.record(actor: payload[:canceled_by] || 'system', action: 'payment_combination_cancel_orchestrated',
    resource: combination, after: { members:…, canceled_order_ids:… })`（敏感资金操作审计，镜像 8a refund Audit）；
  - `PallasTrade::OperationalMetrics.count('payment_combination.cancel_orchestrated', combination_id:…, canceled:…, skipped:…, failed:…)`；
  - rescue StandardError → Rails.logger.error 不 raise（不阻断事件流；审计可重放）。
- FR-R68K-103（注册）：core engine.rb 订阅者数组 += `PallasTrade::Orders::CombinationCancelSubscriber`
  （镜像 L391 PaymentCombinationSucceededSubscriber 注册位）。
- 边界（记录不实施）：状态机 `payment_combination.canceled`（pre-payment）事件加消费者/加 payload；
  webhook 出站（组合取消通知）；组合「全部成员取消后组合自动转 canceled/closed」语义（改组合状态机——超出）。

### 11.3 AC
| AC | 条件 | FR |
|---|---|---|
| AC-R68K-01 | CombinationCancel 成功取消 ≥1 成员 → 发布 `payment_combination.cancel_orchestrated`，payload 含 prefixed combination id + members 聚合 + canceled_by | 101 |
| AC-R68K-02 | canceled==0（全 skip/失败）→ 不发布 | 101 |
| AC-R68K-03 | 订阅者收到事件 → Audit.record（action=payment_combination_cancel_orchestrated）+ OperationalMetrics.count；combination 缺失 no-op | 102 |
| AC-R68K-04 | 订阅者异常 rescue 不 raise（log）；注册项存在于 engine.rb | 102/103 |
| AC-R68K-05 | 回归：8f 编排 spec 全绿 + 状态机 `payment_combination.canceled` 语义不变 + 全量 backend-rspec ×2 + quick check + doc-impact | — |

### 11.4 技术影响 / 测试
- core：`services/orders/combination_cancel.rb`（+事件发布）；`subscribers/pallastrade/orders/combination_cancel_subscriber.rb`（新）；`lib/pallastrade/core/engine.rb`（+注册）。无 migration / 无 API / 无 UI。
- specs：combination_cancel_spec 增发布断言（事件发布 or 订阅者副作用，视 stub 能力）；新 subscriber spec（审计+metrics 副作用、payload 双模、异常隔离）；回归 8f/8a-8j 相关组。
- 知识同步：payments skill 8k 节；scenarios GS-078；events-webhooks skill 若涉新事件名需补（本包订阅者模式既有，复查无改则记录）。

## 回写记录（harness prd update）

| 日期 | 来源 | 操作者 |
|---|---|---|
| 2026-09-09 | REV-P6-8k（8f 边界落地）：组合级 payment_combination.canceled 事件 + 审计/metrics 订阅者 | AI |
