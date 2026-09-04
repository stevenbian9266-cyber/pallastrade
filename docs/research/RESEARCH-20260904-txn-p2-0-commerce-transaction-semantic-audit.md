# RESEARCH-20260904-txn-p2-0 — Commerce Transaction Semantic Audit（TXN-P2-0）

> 日期：2026-09-04 ｜ 来源：`豆包梳理业务需求/P2 — Commerce Transaction Orchestration & Recovery.md`（TXN-P2，用户定稿）
> Task：`TASK-20260904052307-f932822b`；Gate：`GATE-2026-09-04T05-23-21`（audit）
> 分支：dev ｜ 性质：**只读语义审计 — 无 Coding / 无 migration / 未创建任何模型**
> 状态：**DRAFT — 等待架构评审**（评审通过前禁止 TXN-P2-1 的 migration / 建表）

---

## 0. TL;DR

1. P2 源文档的前置判断全部得到代码验证：P0/P1 已落地；**当前不存在任何 durable Transaction 编排层**（全仓无 `CommerceTransaction`/`Transactions`，`transaction_id` 仅 PSP/Refund 语义）；单订单 canonical 路径存在"PSP 成功 + 本地完成失败 → 卡 pending 无恢复"的真实缺口（`session.completed?` 短路）。
2. P2 要引入的 `CommerceTransaction + TransactionOrder × N`（而非 `OrderTransaction belongs_to order`）与现状多订单事实（组合支付、父子单、补付）匹配，**同意**。
3. 本审计冻结 4 项核心决策（§5）+ 输出 14 项产物（§6），**全部为"建议决策"，等待用户/架构评审**。
4. 重要发现（审计过程中修正的既有认知）：
   - 组合支付前端现行实现是 **`PaymentCheckoutModal` 收银台弹窗**（单笔→订单会话；多笔→ `PaymentCombination` + PaymentElement）；`CombinedPaymentCheckout` 组件已不存在，仅注释 / Skill / 文档残留引用（**文档需清理**）。
   - 组合成员订单完成走 **legacy `Checkout::Complete`（`next`-until-complete）**，与 canonical `Carts::Complete`（pay!+finalize!）是两套 primitive；组合收银台（账户补付场景）成员为 standard-flow `pending` 订单时能否被 legacy primitive 完成 **需运行时验证（列为最高风险审计项）**。
   - 库存预留 **不是"未来 P3 从零做"**：`StockReservation + StockReservations::{Reserve,Release}` 已存在并接入完成路径（`stock_reservation_strategy` order/payment 双模式）；P2/P3 的 Inventory Transaction Port 是对现有原语的 saga 化/语义补全（缺 RESERVED/COMMITTED/RELEASED/EXPIRED 显式生命周期）。

---

## 1. 现状核实摘要（代码证据）

| P2 源文档基础 | 核实结论 | 证据 |
|---|---|---|
| P1: Cart→Submit→Order→CheckoutView→version/price_version/expiration→readiness→CheckoutSnapshot/fingerprint→Payment Start Gate | ✅ 已落地（CHK-P1-1A/1B/2/3/5） | `core/services/pallastrade/order_checkout/{view,snapshot,readiness,refresh,recalculate,expiration}.rb`；`orders.checkout_version/price_version/checkout_expires_at`（migration 20260903140000/150000） |
| P0: PaymentSessions::Start（reuse/operation_key/provider 幂等）→ PaymentSession→Payment→Webhook Event Store→Carts::Complete | ✅ 已落地（P0-0..7） | `core/services/pallastrade/payment_sessions/start.rb`；`payments/{handle_webhook,webhook_event_store}.rb`；`carts/complete.rb`；P0 报告 `docs/payment/PAYMENT_P0_COMPLETION_REPORT.md` |
| Transaction 层缺失 | ✅ 确认缺失 | 全仓无 `CommerceTransaction`/`Transactions`；`transaction_id` 仅 `Payment#response_code` 别名与 `Refund#transaction_id`（PSP 层） |
| 单订单 recovery 缺口（钱成功+本地失败） | ✅ 确认为真实缺口 | `orders/payment_sessions_controller#complete`：`session.completed?` → 直接 return；`Payments::HandleWebhook#handle_success` 对 completed session 提前返回 → 无第二驱动点 |
| `CombinationSettleJob` = 现成"先入账后完成+补偿"原型 | ✅ | `payments/payment_combinations/{create,complete}.rb` + `jobs/payments/combination_settle_job.rb`（组合域） |
| 父子单结构 + AutoSplit + Splitter | ✅ 能力层存在，**默认关闭** | `orders/splitter.rb`、`carts/auto_split.rb`（`auto_split_orders` 默认 `[]`）、Order `parent/children/split_from` |
| 库存预留已存在 | ✅（文档 §36-38 假设需更新） | `stock_reservations/{reserve,release}.rb`、`stock_reservation_strategy`（默认 `'order'`）、`Carts::Complete` 内 Reserve/Release 接线 |

---

## 2. 术语冲突说明（审计必读，防后续文档错乱）

项目内部存在**两套不同的 P 编号**，切勿混用：

| 编号 | 含义 | 出处 |
|---|---|---|
| P0 / P1 / P2（本文） | Payment Foundation / Order-centric Checkout / **Commerce Transaction OTS** | 豆包系列文档（支付系统优化 → Checkout Domain Consolidation → 本 TXN-P2） |
| 内部 P1..P8 | 订单生命周期各阶段（P1 父子结构、P2 拆单引擎、P4 组合支付服务层、P5 自动拆单、P6 手动拆单、P7 售后、P8 风控/锁存） | `ai/skills/pallastrade-checkout|payments/SKILL.md`（2026-08-26~28 PRD） |

→ TXN-P2-1 起的文档/代码注释必须写 **TXN-P2-x** 或带"Commerce Transaction"，避免与内部 `P2 拆单引擎` 混淆（REQ/PRD 命名同样适用）。

---

## 3. TXN-P2-0 必查场景 → CURRENT_STATE（代码事实）

| 场景 | CURRENT_STATE（证据） | 关键事实 |
|---|---|---|
| 普通 Order（canonical） | `Carts::Submit`→`pending`→支付会话→`Carts::Complete`（pay!+finalize!） | 1 Order : 多 session attempts（active 1）: ≤1 completed Payment；完成=Order 自身 |
| digital Order | `Order::Digital` 模块；Readiness 免 shipping_address；checkout 状态机自动跳过 delivery | 完成语义同普通单 |
| 多 PaymentSession attempts | `PaymentSessions::Start` reuse（30min 窗口）+ operation_key attempt-N + 二次锁 | declined/failed 会话 terminal 后可再建；**无 PaymentAttempt**（正确） |
| parent/child orders + 自动拆单 | `Orders::Splitter` + `Carts::AutoSplit`（**flag 默认关闭**）；拆单在支付完成后执行；源订单=父容器 | 拆单时源订单有 completed 支付 → 按行分摊建 `PaymentSplit`（`payment_combination` 空） |
| 手动拆单（P6 flag 关闭） | `Orders::ManualSplit`：源 completed 时子订单 `update_columns(state: 'complete', completed_at:)` 补 completed | 已显式确认子单完成语义的一种（绕过状态机） |
| PaymentCombination / PaymentSplit | `PaymentCombinations::{Create,Complete}` + `PaymentSplit` + `CombinationSettleJob`；1 组合:1 session(挂 primary):1 Payment(order_id=nil):N splits | **阶段 2 成员完成用 `Checkout::Complete`（legacy）**；失败 balance_due + job |
| 组合支付前端（现行） | 账户订单 `OrderCombinedPay`：1 笔→`/checkout/[id]`（or_ OrderPaymentContent）；2+ 笔→`PaymentCheckoutModal`（POST /payment_combinations → PaymentElement → combination complete → `/payment-result/[id]`（pcom_）） | `CombinedPaymentCheckout` 组件已删；注释/Skill 残留引用 |
| balance collection / 账户补付 | completed 但仍有余额订单可在 checkout 支付页补付（`orders_controller` 注释：completed-but-unpaid）；`payment_setup_sessions` 为钱包/账户保存卡 | Order 可能 >1 Transaction（源购买 + 补收） |
| legacy provider completion | Express（CartDrawer `express-checkout-flow`，cart 域 session）、legacy cart 域 `carts/payment_sessions`、Stripe `CompleteOrderFromSessionJob`/`CompleteOrder`/`confirm_payments`（redirect） | P0-7 只兼容不删 |
| inventory strategy | `stock_reservation_strategy` `'order'`（默认：cart 操作 Reserve）/ `'payment'`（cart 只校验，`Carts::Complete` 内 Reserve→Release） | 有真实 reservation 行 + TTL；无显式 COMMITTED/RELEASED/EXPIRED 生命周期 |
| Carts::Complete | 幂等；standard 分支 pay!+finalize!；legacy 分支 advance_to_complete!；Preflight/库存/拆单钩子 | canonical finalization primitive（单订单） |
| Checkout::Complete（legacy） | `next` until complete | 组合成员完成在用；**两套 primitive 并存** |

---

## 4. P2 源文档 §49 十个关键问题 → 建议决策

| # | 问题 | 建议决策（待评审） | 依据 |
|---|---|---|---|
| 1 | 普通订单 Transaction 边界 | **1 次商业交易 = 1 Transaction**；一个 `payment_pending`→`completed` 生命周期 | canonical 已完成"1 checkout/1 amount/1 payment"语义 |
| 2 | 一个 Transaction 是否允许多个 Order | **允许（组合支付 = 1 Transaction : N Order）**；用 `TransactionOrder` 表达 | PaymentCombination 现状已支持 N 订单 |
| 3 | 一个 Order 是否允许多个 Transaction | **允许（时间上串行）**：初始购买 + balance_collection 各自独立 Transaction | 补付/多笔支付意图已存在 |
| 4 | 父子单是不是资金边界 | **默认不是**：`fulfillment split ≠ payment split`；拆单仍属同一交易（除非产品明确"each child separately payable"） | Splitter 后子单金额从父支付分摊（PaymentSplit），无独立收款 |
| 5 | PaymentCombination ↔ Transaction 映射 | **1 组合交易 = 1 Transaction**；组合作为 strategy/adapter 挂到 Transaction 下（非 core） | P2 源 §32 |
| 6 | balance collection 是否独立 Transaction | **是**（purpose=BALANCE_COLLECTION） | P2 源 §7/§16 |
| 7 | Snapshot 冻结时刻 | **StartTransaction 提交点**（quote consent 通过后、建 session 前），JSONB immutable evidence | P2 源 §9/§10 |
| 8 | Start 后 Checkout Refresh 是否允许继续 | **交易已冻结期间禁止静默吞掉商业变化**：Start 前 expired→Refresh→compare（见 QUOTE_CONSENT_POLICY）；Start 成功后、`payment_pending` 期间若 quote 过期 → 进入"需重新确认或取消/超时"（推荐给 transaction 加 quote_expires_at 派生，不做无限续期）；`payment_confirmed` 后不可逆 | P2 源 §11/§12 + INV-06/07 |
| 9 | 已付款订单最终 canonical Finalizer | **`Transactions::Finalize`**：standard→`Carts::Complete`（canonical primitive）；组合→现有组合完成链；legacy 兼容→`Checkout::Complete`（标 COMPATIBILITY ADAPTER，逐步 strangler 收敛） | P2 源 §23-25 |
| 10 | Inventory 与 Transaction 生命周期对齐 | **P2 只建 Port 契约 + 现原语 adapter，不重写**；真实生命周期补全归 P3 | P2 源 §36-38 |

---

## 5. 四个冻结决策（P2 源 §47）— 建议值（待评审冻结）

### 5.1 TRANSACTION_IDENTITY

- Transaction 代表"**同一用户同一商业意图的一次执行**"。
- 判定"同一 active transaction"的确定性查找键（用于 Start 幂等）：
  ```
  [store_id, customer_token/guest_identity, purpose, participant order set(normalized), active 状态集合]
  ```
  - 单订单：`order_id + purpose`，且存在 state ∈ {created, payment_pending} 的记录即复用；
  - 组合：`参与订单集合 + purpose`（集合规范化排序）复用同一 active Transaction；
  - **checkout_version/price_version/fingerprint 不进入 identity**——它们属于"该次执行所依据的商业报价"，Refresh 会自增 → 放进 identity 会破坏幂等（refresh 后同意图变成新 transaction）。它们作为 snapshot 证据绑定。
- 参考 P0 经验：复用窗口内"同意图→同 active 记录"，窗口外/终态后再新建（对照 `REUSE_WINDOW=30.min` 精神）。

### 5.2 TRANSACTION_CARDINALITY

- `CommerceTransaction 1 ── N TransactionOrder（role: primary|participant）`
- `CommerceTransaction 1 ── N PaymentSession（attempts；session.transaction_id 可空 FK）`
- `CommerceTransaction 1 ── 0..1 PaymentCombination（组合支付时）`
- `Order 1 ── N Transaction（时间串行：purchase / balance_collection；业务上无并发活跃交易）`
- `PaymentSession 1 ── 1 Payment`（保留，不引入 PaymentAttempt）
- 父子拆单：**默认并入同一 Transaction**（订单完成前拆分 = 参与者在 finalize 时展开；完成后的拆单属售后/履约域，另行处理——需要与 AutoSplit 时序审计对齐，见 RISK-02）。

### 5.3 TRANSACTION_SNAPSHOT_POLICY

- 落库字段：`snapshot_data`（JSONB，immutable，含完整报价证据）+ `checkout_version/price_version/snapshot_fingerprint/amount/currency/generated_at`。
- 冻结时刻：Start 提交点（consent 通过后）。事务内 `transactions.create!` + snapshot 同事务写。
- 内容：按 P2 源 §10——participants（order_id/number/allocated_amount/currency）、items、addresses、shipping、discounts、tax、amount、currency。
- **不是 pricing source**：任何重新报价回到 `OrderCheckout`（INV-09）。
- 组合：`participant_orders[]` 含各单分摊（与 `PaymentSplit` 记账口径一致——snapshot 的 allocated_amount 应引用启动时各单 `amount_due`）。

### 5.4 TRANSACTION_FINALIZATION_POLICY

- canonical = `Transactions::Finalize`：
  - standard participant → `Carts::Complete`（幂等 primitive）；
  - legacy participant → `Checkout::Complete`（标 COMPATIBILITY ADAPTER）；
  - 组合资金 → 保留 `PaymentCombinations::Complete` 阶段 1（入账）为"资金事实确认"，阶段 2 成员完成逐步迁到 `Transactions::Finalize`。
- 规则：`payment_confirmed → finalizing → completed`；任何 per-participant 失败 → 该 participant `completion_status=failed` + Transaction → `recovery_required`（不回滚资金，对照 CombinationSettleJob 原则）。
- `session.completed?` 短路**不得阻断** paid-order recovery（改造见 FINALIZATION_PRIMITIVE_MATRIX / TXN-P2-5）。

---

## 6. 审计产物

### 6.1 TRANSACTION_SCOPE_MATRIX

| 场景 | 商业交易边界 | Payment 边界 | Completion 边界 | Transaction 映射（建议） |
|---|---|---|---|---|
| 普通标准订单 | Order | PaymentSession（1 active / 多 attempts） | Order（Carts::Complete） | 1 Transaction : 1 Order |
| legacy cart 订单（存量） | Order（state=cart） | cart 域 session（委托 Start） | Order（Carts::Complete legacy 分支） | 1 Transaction : 1 Order（**迁移期**：存量可暂不建 transaction，strangler） |
| digital 订单 | Order | session | Order | 同普通单 |
| 多 session attempts（换卡重试） | Order（同一意图） | 多 PaymentSession（串行 terminal） | Order 一次 | **1 Transaction**，sessions 挂在 transaction 下 |
| 组合支付 | 多 Order 一次收款 | PaymentCombination（1 session/1 payment） | 逐成员 Order（先 legacy Checkout::Complete） | 1 Transaction : N Order（role=participant） |
| 拆单（自动/手动，flag 关闭） | 源订单一次交易 | 源订单支付/分摊 | 父容器 + children | 默认 1 Transaction（P2-0 建议）；若"each child payable"另行 |
| balance collection / 补付 | Order 第二次收款 | 新 session | Order（已完成则只补余额） | 新 Transaction（purpose=BALANCE_COLLECTION） |
| Express / 一页式（legacy） | Order | cart 域 session | Carts::Complete | 存量保持兼容；迁移期不强制建 transaction |

### 6.2 TRANSACTION_CARDINALITY_DECISION

见 §5.2。附加约束：
- 同一 Order 不允许两个 **active**（created/payment_pending）transaction 并存（保证 resume 唯一）；并发 Start 用订单锁/唯一约束收敛（见 IMPLEMENTATION_PLAN TXN-P2-2）。
- 组合场景 primary order 与其它成员在同一 active transaction 内；组合支付完成后组合内订单完成顺序由 Finalize 逐个驱动。

### 6.3 TRANSACTION_PARTICIPANT_MODEL

```
transaction_orders
- transaction_id   FK → transactions
- order_id         FK → orders
- role             string   # 首版最小集：primary | participant（fulfillment_child/balance_target 延后）
- amount_snapshot  decimal  # 启动时该单 amount_due（证据，非计算源）
- completion_status string  # pending | completed | failed（TXN-P2-5 用）
- 唯一索引 [transaction_id, order_id]
- 索引 order_id（resume/反查当前活跃交易）
```

### 6.4 TRANSACTION_SNAPSHOT_POLICY

见 §5.3。补充：`snapshot_data` 由 `OrderCheckout::Snapshot`（动态 VO）+ 订单完整 quote（items/addresses/shipping/discounts/tax）在 Start 时序列化；`snapshot_fingerprint` 建议沿用 P1 fingerprint 算法并固化在 transaction 行（列），避免只存 JSON 里查询不便。

### 6.5 QUOTE_CONSENT_POLICY

- Start 时：gate 复用 `PaymentSessions::Start#ensure_fresh_quote` 同款三段（gate_active? → expired? → readiness → conflict）：
  1. expired → `OrderCheckout::Refresh`（自动续期重算，不替用户同意新条件）；
  2. refresh 后 **compare commercial facts**（金额/币种/行项目指纹/运费/promo/tax 相对旧 quote）：
     - 无变化 → **transparent refresh** → 继续（record `quote_refreshed: true`）；
     - 有变化 → **409 `QUOTE_CHANGED`**（携带 latest_checkout_version/latest_price_version/latest_fingerprint/latest_amount/latest_currency），要求用户确认；
  3. readiness 缺项 → `checkout_not_ready`。
- 与 P1-5 `checkout_version_conflict` 关系：P1-5 是"客户端期望版本比对"，保留给**已有交易/页面上的 session 重试**；Start Transaction 场景以**服务端权威 quote**（snapshot 冻结值）为准，两者并存不冲突。错误码建议：Start 场景用 `QUOTE_CHANGED`（新码），P1-5 保持 `checkout_version_conflict`——**交由架构评审定夺是否合并**。
- INV-07 满足路径：任何商业事实变化在未获用户确认前不得进入新 Transaction snapshot。

### 6.6 PAYMENT_SESSION_RELATIONSHIP

- `payment_sessions.transaction_id` 可空 FK（legacy/历史数据为 NULL）。
- 语义：session = transaction 的支付 attempt（P0 多 attempt 模型保留）；不新增 PaymentAttempt。
- Start Transaction → 状态允许（created/payment_pending）→ 调 `PaymentSessions::Start`（复用其 gate/reuse/operation_key/二次锁）→ 绑定 transaction_id。
- Payment Start Policy（P2 源 §31）：`payment_confirmed/finalizing/recovery_required/completed/manual_review` 禁止新 session。
- 迁移：不回溯历史数据建 transaction；仅新路径写入。

### 6.7 PAYMENT_FACT_RESOLUTION_POLICY

- 判定顺序（权威性从高到低）：
  1. 本地 Payment（transaction 关联 sessions 的 payments 或组合 payment）`completed` → **PAID**（若与 PSP 侧一致）；
  2. 本地无 completed 但存在"成功类" webhook 事件未落账 → 以事件驱动一次 reconciliation → 再判；
  3. 仍不明确 → **Provider read-only status query**（新增 contract `fetch_payment_status`，Stripe v1 = PaymentIntent retrieve → status/amount/currency/reference）→ PAID/UNPAID；
  4. 网络失败/未知 → **AMBIGUOUS** → `manual_review`（不猜）。
- 单订单与组合统一：组合的 Payment(order_id=nil) completed = 该 Transaction PAID。
- 输出常量：`UNPAID / PAID / AMBIGUOUS`（对齐 P2 源 §19）。

### 6.8 FINALIZATION_PRIMITIVE_MATRIX

| participant 类型 | 现行完成 primitive | P2 定位 | 收敛动作 |
|---|---|---|---|
| standard 单订单 | `Carts::Complete`（pay!+finalize!） | canonical finalization primitive | `Transactions::Finalize` 调用（原样复用） |
| legacy cart 订单 | `Carts::Complete` legacy 分支 | canonical（兼容分支） | 同上 |
| 组合成员订单 | `PaymentCombinations::Complete` 阶段2 → `Checkout::Complete` | 资金入账保留；成员完成 → 标 COMPATIBILITY ADAPTER → strangler 迁到 Finalize | 运行时验证 standard 成员能否被 legacy primitive 完成（RISK-01） |
| `session.completed?` 短路 | 完成端点提前 return | **改造点**：短路只防"重复完成动作"，不得阻止"已付款订单的 recovery finalize" | TXN-P2-5：短路改为查 Transaction/PaymentFact 后再决定 |

### 6.9 INVENTORY_TRANSACTION_MATRIX

| 能力 | 现状 | P2 动作 |
|---|---|---|
| `StockReservation` 行 + TTL | ✅ 存在 | 保留（low-level primitive） |
| `StockReservations::Reserve`（validate_only 支持） | ✅ | `InventoryReservationPort#reserve` adapter |
| `StockReservations::Release` | ✅ | `#release` adapter；**语义需审计**（当前 Release 在 Carts::Complete 后触发 ≈ 消费/释放？） |
| commit/consume 显式状态 | ❌ 缺 RESERVED/COMMITTED/RELEASED/EXPIRED | P2 只定义 Port contract + 语义缺口记录；真实生命周期补全归 P3 |
| 策略 order/payment | ✅ flag | 不改变；`payment` 策略下 Transaction `payment_confirmed` 是 Reserve 触发点（对齐 P2 源 §39 愿景） |

### 6.10 LEGACY_ADAPTER_MATRIX

| legacy 入口 | 现状 | P2 定位 |
|---|---|---|
| cart 域 `carts/payment_sessions`（Express/一页式/redirect 返回） | P0-3 委托 Start | 兼容保留；不新增能力 |
| `Checkout::Complete` | 组合成员完成在用 | COMPATIBILITY ADAPTER（P2 源 §25） |
| `CombinedPaymentCheckout`（组件） | **已删**（4C4 前后）；残留注释/Skill | 文档清理项（非代码） |
| `PaymentCheckoutModal`（收银台弹窗）+ `OrderCombinedPay` | 现行组合入口 | 保留；TXN-P2-6 前不迁移，P2-5 后走 Transaction handler |
| Stripe `CompleteOrderFromSessionJob` / `CompleteOrder` / `confirm_payments`（redirect） | webhook/redirect 完成 | 三路收敛到统一 handler（P2 源 §21-22） |
| `payment_result` 页 pcom_/or_ | 展示层 | 不变 |

### 6.11 DB_MODEL_PROPOSAL（仅提案——评审前禁止 migration）

```
transactions（前缀 txn_）
  id, store_id FK, customer_id FK(可空,guest), 
  state            # created|payment_pending|payment_confirmed|finalizing|completed|canceled|recovery_required|manual_review
  purpose          # purchase|balance_collection|combined_payment（首版最小）
  checkout_version, price_version, snapshot_fingerprint
  snapshot_data    jsonb（immutable evidence）
  amount, currency
  payment_combination_id FK 可空（组合支付时 1:1 绑定）
  started_at, payment_confirmed_at, finalizing_at, completed_at, recovery_required_at, canceled_at
  recovery_attempts int, last_error_code/class/message
  created_at, updated_at, lock_version（乐观锁/二次锁）

transaction_orders（见 6.3）

payment_sessions + transaction_id FK（可空，TXN-P2-2 迁移）
```

审计事件：复用 `audit_logs`（P0-6）+ `request_id`；事件名按 P2 源 §41（transaction.created / payment_started / payment_confirmed / finalization_started / completed / recovery_required / recovery_started / recovery_completed / manual_review / canceled），不新建 Audit Engine。

### 6.12 API_PROPOSAL（仅提案）

```
POST /api/v3/store/orders/:order_id/transactions      # 单订单 Start（expected_* + payment_method）
     → 201 { transaction: {id,state,purpose,participants,amount,currency}, payment_execution: {...} }
     → 409 QUOTE_CHANGED（latest quote）| checkout_not_ready
POST /api/v3/store/transactions                       # 组合 Start（order_ids[]）——cardinality 冻结后定
GET  /api/v3/store/transactions/:id                   # Resume 视图：state/participants/payment summary/recovery/completion
     （或 orders/:id/transactions/:id；按 P2 源 §43/44 与 cardinality 定，TXN-P2-2 前冻结）
```

迁移期：`payment_sessions` 端点**保持原样**；Storefront BFF `/api/checkout/start` 在 TXN-P2-6 才切 transaction-first（strangler）。SDK：`orders.transactions.*` / `transactions.*` 类型随包新增。

### 6.13 RISK_LIST

| # | 风险 | 等级 | 缓解 |
|---|---|---|---|
| RISK-01 | 组合成员为 standard-flow 订单时 legacy `Checkout::Complete`（next-until-complete）能否完成（pending 无 legacy 迁移路径） | 🔴 高（**已验证**：不能完成 → 现行潜在缺陷） | **2026-09-04 运行时验证结论**：不能。legacy `next` 迁移表无 `from: pending`；对 standard pending 单 `order.next`→false（"State cannot transition via next"），`Checkout::Complete`→failure、订单停留 pending。组合阶段 2 对该成员标 balance_due → `CombinationSettleJob` 永久重试失败 → **钱已入账、订单永不完成**。影响现行账户 2+ 单合并收银台（PaymentCheckoutModal）对 standard `or_` 待支付单。建议独立 bugfix（见 §10）或 TXN-P2-5 优先收敛 |
| RISK-02 | 父子拆单时序：AutoSplit 在支付完成**之后**拆（源已 completed）→ Transaction 参与者在 finalize 时不存在；拆单后子单归属与金额分摊口径 | 🔴 高 | P2-0 默认"拆单并入父交易"需与 Splitter/PaymentSplit 分摊时序核对；把"拆分时点"作为架构评审项 |
| RISK-03 | Start 幂等键若含 fingerprint 会被 Refresh 自增破坏 → 双开 transaction | 🟠 中 | identity 不含版本（§5.1）；用 order+目的+active 状态 + 行锁/唯一约束 |
| RISK-04 | `session.completed?` 短路改造若过度放开 → 重复 finalize | 🟠 中 | 依赖 Transaction state guard + PaymentFactResolver + Finalize 幂等（INV-08） |
| RISK-05 | 报价 consent 语义与 P1-3"过期自动 Refresh 续期"既有行为冲突，用户可见金额变化时机变化 | 🟠 中 | QUOTE_CONSENT_POLICY 显式化 + 前端 409 UI（复用 P1-4B 模式） |
| RISK-06 | Entry Gate 未满足（P0/P1 未提交/未收口）就开发 P2 → 基线漂移 | 🟠 中 | 见 §8；先收口再 TXN-P2-1 |
| RISK-07 | 术语双 P 编号混用 → 文档/REQ 混乱 | 🟢 低 | §2 规范 + 命名 TXN-P2-x |
| RISK-08 | recovery 无限重试/无 stuck 可见性 | 🟠 中 | recovery_attempts + last_error + sweeper（TXN-P2-4/7） |
| RISK-09 | 库存 Release 语义歧义（消费 vs 释放）带入 transaction | 🟠 中 | P2 只建 Port + 记录语义缺口；P3 补生命周期 |

### 6.14 IMPLEMENTATION_PLAN（评审通过后执行；**本轮不实施**）

| 包 | 内容 | 前置 | 验证 |
|---|---|---|---|
| TXN-P2-1 Transaction Core | `transactions` + `transaction_orders` 模型 + state machine + snapshot 写入 + 审计事件；**不接支付流** | 本审计评审通过 + Entry Gate 满足 | migration + model/state machine/snapshot specs |
| TXN-P2-2 Start/Resume | `Transactions::Start/Resume` + 业务幂等 + QUOTE_CONSENT + `PaymentSessions::Start` 集成 + session.transaction_id 迁移 | TXN-P2-1 | start/resume 幂等 spec；409 QUOTE_CHANGED request spec |
| TXN-P2-3 Payment Fact Resolver | `PaymentFactResolver` + provider `fetch_payment_status`（Stripe v1） | TXN-P2-1 | resolver 单元 + Stripe contract spec |
| TXN-P2-4 Recovery | `recovery_required` + `Transactions::Recover` + Recovery Job + manual + audit + state guard | TXN-P2-2/3 | 幂等 recover spec（AC-2011/2012/2013/2014） |
| TXN-P2-5 Unified Finalization | `Transactions::Finalize`（strangler：standard→Carts::Complete；legacy→adapter；组合成员收敛）+ `session.completed?` 短路改造 | TXN-P2-4 + RISK-01 结论 | finalize 幂等 + 三路/多入口收敛 spec（AC-2015） |
| TXN-P2-6 Storefront/API Migration | UnifiedCheckout / OrderPaymentContent / `/api/checkout/start` / SDK 切 transaction-first（Provider UI 不变） | TXN-P2-2~5 | storefront typecheck/biome/e2e 回归 |
| TXN-P2-7 Operational Hardening | trace/metrics/admin transaction 检查页/stuck sweeper/manual tooling/docs | TXN-P2-4/5 | 文档 + e2e/操作演练 |
| 收尾 | `TXN_P2_COMPLETION_REPORT`（按 P2 源 §65） | 全部 | regression matrix + rollback plan |

回归基线：每包对照 P2 源 AC-2001~2020 与 INV-01~10；P0/P1 baseline（AC-2016/2017）逐包绿。

---

## 7. AC / Invariant 可行性对照（P2 源 §59/§60）

- AC-2001（READY+同意→可启动）✅ 依赖 QUOTE_CONSENT_POLICY + P1 gate。
- AC-2002（同意图单 active Transaction）✅ §5.1 identity + TXN-P2-2 锁。
- AC-2003/2004（N Order / 1 Order N Transaction）✅ TransactionOrder 模型 + purpose。
- AC-2005（冻结版本/snapshot/amount/currency）✅ §5.3。
- AC-2006（session=attempts，不新增 PaymentAttempt）✅ 现状已满足 + transaction_id FK。
- AC-2007（重复支付请求受 P0 幂等）✅ 复用 PaymentSessions::Start。
- AC-2008（decline→session failed，transaction 保持 payment_pending）✅ 状态机设计（session 独立失败态）。
- AC-2009/2010/2011（PSP success→payment_confirmed；confirmed 后禁新 attempt；成功+未完成→recovery_required）✅ PaymentFactResolver + 状态机 + Payment Start Policy。
- AC-2012/2013/2014（recovery 完成/幂等/AMBIGUOUS→manual_review）✅ TXN-P2-4。
- AC-2015（入口收敛统一 handler）✅ TXN-P2-5（strangler，多入口清单见 §6.8/6.10）。
- AC-2016/2017（P0/P1 baseline 全绿）⚠️ Entry Gate（§8）。
- AC-2018（组合可用但不成为 core）✅ 定位为 strategy/adapter。
- AC-2019（StockReservation 不破坏）✅ 只加 Port adapter。
- AC-2020（未新增 PaymentAttempt/CheckoutSession/Router/Registry）✅ scope lock。
- INV-01..10 全部可直接写入 PRD；INV-09/10（snapshot 非价格源；transaction 是 orchestration aggregate 非 payment aggregate）在数据模型层面已保证。

---

## 8. Entry Gate 现状与本审计限制

| Entry Gate 项（P2 源 §45） | 现状 | 结论 |
|---|---|---|
| P0 baseline green | P0 报告收尾，coverage-gate 归 CI | ⚠️ 未完全收口 |
| P1 baseline green | CHK-P1-1A..5/4C4 已实施 | ⚠️ 全部在 dev **工作树未提交** |
| P0/P1 migrations settled | 是（无未决 migration） | ✅ |
| P0/P1 PRD status closed/accepted | 部分 draft 标记残留 | ⚠️ 需正式收口 |
| working tree/branch 可审计 | dev 有大量未提交文件 + 多个 open task | ⚠️ 需先收口 |

**本审计限制**：
- 只读；未改任何代码/migration/模型；产物仅本文档。
- 行为断言以 dev 工作树代码（含未提交的 P0/P1）为准；commit 前如需复验可对照 `git diff` 复核。
- 未做运行时验证（RISK-01/02 需在 TXN-P2-1 前补运行时证据，非本审计范围）。
  - **更新（2026-09-04）**：RISK-01 运行时验证已补充于 §10（结论：legacy primitive 无法完成 standard pending 成员 → 现行潜在缺陷）；RISK-02 仍未验证（flag 默认关闭）。

---

## 9. 下一步（停止点）

1. **本审计文档提交架构评审**（用户/架构师）。评审重点：§5 四项冻结决策、§6.11 DB 提案、§6.12 API 提案、RISK-01/02 处置。
2. 评审通过后，先完成 **P0/P1 收口提交（Entry Gate）**，再开 TXN-P2-1 gate。
3. **RISK-01 已于 2026-09-04 完成运行时验证（结论见 §10）**：legacy `Checkout::Complete` 无法完成 standard pending 成员，且为现行潜在缺陷。建议在其进入 P2-5 前先以独立 bugfix（账户 2+ 单合并收银台 standard 成员完成）处置，或由 TXN-P2-5 优先收敛。RISK-02（拆单时点与分摊口径）仍待验证（flag 默认关闭，可延后）。
4. 期间文档清理项：Skill/注释中 `CombinedPaymentCheckout` 残留引用、术语 P 编号规范（§2）。

---

## 10. 运行时验证补充（2026-09-04）— RISK-01 结论

> Gate：`GATE-2026-09-04T05-51-23`（docs）｜ 方式：dev 容器 rails runner 只读/受限探测（不落库、不改代码）

### 10.1 验证目标

RISK-01：组合成员为 **standard-flow（state=pending）订单**时，legacy `Checkout::Complete`（next-until-complete）能否完成该成员？

### 10.2 验证方法（带超时保护，不持久化）

对 dev 库现存 standard pending 订单（id=13，`or_2KY5XM6frI`，R891788516）执行：

```ruby
o = PallasTrade::Order.find(13); o.reload
trans = PallasTrade::Order.next_event_transitions      # 全部 :next 迁移
Timeout.timeout(5) { o.next }                            # 单次 next 尝试
Timeout.timeout(5) { PallasTrade::Checkout::Complete.call(order: o.reload) }
```

### 10.3 运行时输出（原文）

```text
state=pending standard=true completed_at= amount_due=0.0
next_event_transitions=[{cart: :address}, {address: :delivery, if: ...}, {address: :payment, if: ...}, ...]   # 仅 legacy cart 链，无 from: pending
next_result=false state_after=pending errors=["State cannot transition via \"next\""]
checkout_complete=false state=pending
```

### 10.4 结论（RISK-01 已定论）

1. `Order.next_event_transitions` 仅覆盖 legacy checkout 状态（cart→address→…→complete），**不存在 `from: pending`**。
2. 对 standard pending 订单：`order.next` → `false`（无迁移，记录错误 "State cannot transition via next"）；`Checkout::Complete` → **failure，订单停留 pending**（不会挂起——errors 会终止循环，返回失败）。
3. 因此组合支付 `PaymentCombinations::Complete` 阶段 2 若成员为 standard pending 单：成员完成失败 → 标 `balance_due` → `CombinationSettleJob` 入队 → **每次重试同样失败** → 资金已在组合层入账（succeeded + Payment completed），成员订单**永不完成**。
4. 覆盖缺口佐证：`payment_combinations_complete_spec.rb` 的成员全部被强制为 legacy `cart` 态（`order.update_columns(state: 'cart')`），**无任何 standard 成员用例**——现行验证矩阵未覆盖该路径。
5. 可达性：现行账户多选收银台 `OrderCombinedPay` + `PaymentCheckoutModal`（2+ 笔 → 组合）对 **standard `or_` 待支付单**（`payment_status=balance_due` 且非子订单）开放 → **现行潜在缺陷**（"钱成功、单没完成"的真实实例，独立于 P2 也存在）。
6. 不变量确认：单笔账户支付走订单域 session（or_ → `Carts::Complete` standard 分支）不受影响；缺陷仅限 **2+ 笔组合路径对 standard 成员**。

### 10.5 处置建议（供决策）

- **短期**（P0/P1 收口后优先）：独立 bugfix——`PaymentCombinations::Complete` 阶段 2 对 standard 成员改用 `Carts::Complete`（其 `complete_standard_order!` 已支持"payment_splits captured>0 即放行"），legacy 成员维持 `Checkout::Complete`；补 standard 成员 spec。
- **中期**（P2）：即 §5.4 / TXN-P2-5 `Transactions::Finalize` 的 strangler 收敛目标——该 bugfix 与 P2-5 方向一致，建议 bugfix 先行并作为 P2-5 的基线用例。
- 影响面核对：组合"先入账后完成/失败补偿"原则（P4 教训）不受影响，仅成员完成 primitive 需要按 `standard_flow?` 分流。
