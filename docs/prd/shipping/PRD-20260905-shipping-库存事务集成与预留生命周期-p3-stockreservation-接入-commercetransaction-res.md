# PRD-20260905-shipping-库存事务集成与预留生命周期-p3-stockreservation-接入-commercetransaction-res

| 元数据      | 值                                                                                                                                                                                                                                             |
| -------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 状态       | done（v1.1 实施完成，2026-09-05，commit `8a0e8b8`；task `TASK-20260905110600-942c63c2` finished with verified evidence）                                                                                                                                                                                                                             |
| 创建日期     | 2026-09-05                                                                                                                                                                                                                                    |
| 来源       | 优化：库存事务集成与预留生命周期（P3）——StockReservation 接入 CommerceTransaction Reserve→Finalize/Physical Consume→Commit / Release / Expire 生命周期 + Inventory Recovery（`豆包梳理业务需求/P3 — Inventory Transaction Integration & Reservation Lifecycle.md`，工程编号 INV-P3） |
| 分类       | shipping（自动判定，命中"库存/stock"；AI 语义微调说明：跨 checkout/payments/transaction 域，但主体是库存/履约，沿用既有 stock 类 PRD 落位）                                                                                                                                         |
| 关联 Skill | pallastrade-checkout / pallastrade-data-model / pallastrade-events-webhooks / pallastrade-testing / pallastrade-api-v3 / pallastrade-payments（实施时按包读取）                                                                                        |
| 关联 REQ   | REQ-20260905-inv-p3.md（实施时回填）                                                                                                                                                                                                                 |
| 关联 PRD   | N/A（全新需求；查重未命中 >0.3 相似 PRD）                                                                                                                                                                                                                   |
| 需求类型     | 优化迭代（存量库存原语语义补全 + 生命周期状态化 + CommerceTransaction 交易化接入；不重写库存引擎）                                                                                                                                                                                |

> 🔁 **查重回写**：`harness prd new` 已自动查重通过（无相似度 >0.3 的既有 PRD；最近 P2 系列为 payments/checkout 的 CommerceTransaction，本 PRD 为库存域 P3，不重复）。若后续命中相似 PRD，用 `harness prd update --path <原PRD>` 回写，**不得新建重复 PRD**。

---

## 1. 背景与目标

* **一句话需求原文**：根据 `豆包梳理业务需求/P3 — Inventory Transaction Integration & Reservation Lifecycle.md`，结合当前库存真实实现完成 P3 库存事务集成与预留生命周期升级。
* **背景**：

  * P0（Payment Foundation）/ P1（Order-centric Checkout）/ P2（Commerce Transaction Orchestration & Recovery）已落地：`CommerceTransaction`（`txn_`）+ `TransactionOrder` + immutable `snapshot_data` + `PaymentFactResolver` + `Transactions::{Start,Resume,OnPaymentSuccess,Finalize,Recover}` + Recovery Job/Sweeper + Admin Transaction 页。
  * 库存物理权威已存在：`StockItem.count_on_hand` + `StockMovement`；`StockReservation` 不修改 `count_on_hand`，而是通过 `Stock::Quantifier` 的 `available = physical count_on_hand - active reservations` 实现**软占位**。
  * 真正物理减库存发生在 canonical Order Finalization 路径：`Order#finalize! → Shipment/InventoryUnit → StockMovement`。P3 **不得建立第二套物理减库存算法**。
  * 库存域已有 `StockReservation` + `StockReservations::{Reserve,Release,Extend}` + TTL + 悲观锁 + backorder/preorder 豁免 + `stock_reservation_strategy = order | payment` + `ExpireJob`，但仍缺交易级显式生命周期：无 RESERVED/COMMITTED/RELEASED/EXPIRED 状态；Release/Expire 均硬删除；Reservation 与 CommerceTransaction 无关联；标准 Transaction Start 无 Reserve 阶段；Cancel 不可靠释放 Reservation；`ExpireJob` 未注册 sidekiq cron。
  * 当前支付成功后的 legacy `Release` 实际发生在物理库存已由 finalize 扣减之后，本质是**消费完成后清理 reservation 记录**，不是“把库存加回来”；问题在于硬删除导致无法保留 COMMITTED 历史事实。
  * P2 已提供 durable Transaction、PaymentFact、Finalization、Recovery 基础；P3 不新建交易编排体系，只扩展 Inventory Fact 与 Reservation 生命周期。
* **目标**：

  * 不重写库存引擎，将 StockReservation 纳入 CommerceTransaction；
  * 建立 **Reserve → RESERVED → canonical Finalization/StockMovement → COMMITTED** 的正常链；
  * 建立 RESERVED → RELEASED / EXPIRED 的未消费终态；
  * 保证支付前有库存保证、支付后库存/订单异常进入 P2 Recovery；
  * 保留 `StockItem.count_on_hand + StockMovement` 为唯一物理库存权威；
  * Reservation 作为 allocation/evidence，不成为第二套 physical inventory。
* **成功指标**：

  * AC-3001..AC-3028 全部通过测试映射，`harness prd verify` 全绿；
  * RV-I01 Normal Purchase / RV-I02 Stock Race / RV-I03 Paid Finalization Recovery 通过；组合启用时 RV-I04 Combination 通过；涉及长认证时 RV-I05 TTL/3DS 通过；
  * INV-P3-0 产出 20 项审计产物并冻结 7 个策略，审计期间零 migration / 零业务改码；
  * 不发生重复库存扣减；重复 Finalize / Recover 后 `StockMovement` 与 physical count 仍只反映一次真实销售；
  * `payment_confirmed_to_inventory_committed_latency` 可观测；
  * 不新增第二套库存锁、不建重复 Reservation 表、不引入 DB 2PC；P0/P1/P2 baseline 保持全绿。

---

## 2. 用户故事 / 场景

* 作为 **顾客**，我希望支付动作开始前商品库存已经被可靠预留，支付成功后由已有订单履约库存管线真正扣减库存，以避免“付款成功却已经无货”或重复扣库存。
* 作为 **运营/客服**，我希望能看到每笔 CommerceTransaction 的 Inventory Fact、Reservation ID、Reserved/Committed/Released/Expired 时间，以便 PAID + 库存/完成异常能进入 Recovery 而不是形成未知卡单。
* 作为 **系统（Recovery）**，我希望 Payment Fact、Inventory Reservation Fact、Physical Inventory/Order Finalization Fact 可以分别判断，以便进行安全恢复。

场景（正常/边界/异常）：

1. 正常：Transaction Start → Reserve（RESERVED）→ Payment → Payment Fact PAID → canonical Finalize → Shipment/StockMovement 真正减库存 → Reservation COMMITTED → Transaction completed。
2. 边界：两个 Transaction 竞争最后一个库存 → 仅一个 RESERVED，另一个 `INSUFFICIENT_STOCK`，失败方不得创建 PaymentSession。
3. 异常：Payment PAID + Reservation RESERVED + Finalize 失败 → `recovery_required` → Recover（PaymentFact=PAID + InventoryFact=RESERVED）→ retry canonical Finalize → physical consume 成功 → Reservation COMMITTED。
4. 异常：UNPAID + canceled → Release（RELEASED）；PAID 禁止普通 Release。
5. 异常：Reservation TTL 到期且仍 payment_pending → EXPIRED → 禁止使用旧 Reservation 新建/继续新的支付 attempt → re-reserve 成功后才继续；失败 → `INVENTORY_CHANGED`。
6. 异常：组合 Transaction 多订单 → 所有 REQUIRED inventory Reserve 成功后才进入支付；部分 Reserve 失败仅补偿本次 Start attempt 新建的 Reservation。
7. 异常：PAID + Reservation RELEASED / inventory physical fact 不可判定 → `manual_review`，不得重新付款、不得猜测库存状态。
8. 豁免：backorderable / preorder / digital / non-stock-managed → `InventoryRequirement=NOT_REQUIRED`，不创建 Reservation。
9. 售后：COMMITTED 后的 cancel/refund/return/restock 属于售后库存域，通过现有/未来 restock `StockMovement` 处理，**不得把 COMMITTED Reservation 重新 Release**。

---

## 3. 功能需求（FR，按 INV-P3-x 实施包分组）

### INV-P3-0 — Inventory Semantic Freeze（只读，无 Coding / 无 migration）

* FR-001：对 StockReservation 模型、Reserve/Release/Extend、Quantifier、StockItem/StockMovement、cart 增删改、Carts::Submit/Complete、order/payment reservation strategy、Transactions::{Start,Finalize,Recover}、AutoSplit/ManualSplit、PaymentCombination、digital/backorder/preorder、inventory adjustments、order cancellation、expiration job、Shipment/InventoryUnit physical consumption 边界进行只读审计，并输出 20 项正式产物：

  1. CURRENT_INVENTORY_ARCHITECTURE
  2. INVENTORY_AUTHORITY_MATRIX
  3. RESERVE_SEMANTICS
  4. RELEASE_SEMANTICS
  5. PHYSICAL_CONSUMPTION_MATRIX
  6. COMMIT_GAP_ANALYSIS
  7. COMMIT_SEMANTICS
  8. RESERVATION_STATE_MODEL
  9. TRANSACTION_RESERVATION_CARDINALITY
  10. RESERVATION_TIMING_MATRIX
  11. TTL_AND_PAYMENT_WINDOW_MATRIX
  12. COMBINATION_RESERVATION_MATRIX
  13. SPLIT_ORDER_RESERVATION_MATRIX
  14. BACKORDER_PREORDER_MATRIX
  15. INVENTORY_RECOVERY_MATRIX
  16. LEGACY_INVENTORY_PATHS
  17. P3_REUSE_MATRIX
  18. P3_DB_PROPOSAL
  19. P3_RISK_LIST
  20. P3_IMPLEMENTATION_PLAN
* FR-002：回答全部库存关键问题并冻结 7 个策略：

  * `INVENTORY_AUTHORITY`
  * `RESERVATION_IDENTITY`
  * `RESERVATION_LIFECYCLE`
  * `RESERVATION_TIMING`
  * `RESERVATION_TTL_POLICY`
  * `INVENTORY_RECOVERY_POLICY`
  * `COMMIT_SEMANTICS`
* FR-003：P3-0 必须正式确认并记录以下目标语义：

  * `StockItem.count_on_hand + StockMovement` = 唯一 physical inventory authority；
  * Reservation = soft allocation / inventory guarantee；
  * Reserve 不修改 `count_on_hand`；
  * COMMITTED 不执行第二次库存扣减；
  * COMMITTED 只能在 existing canonical finalization/StockMovement physical consumption 成功后确认；
  * Release = 未消费 Reservation 的主动解锁；
  * Expire = TTL 驱动的 Reservation 失效；
  * 售后 Restock ≠ Reservation Release。
* FR-004：明确 `InventoryRequirement` 判定（REQUIRED / NOT_REQUIRED，service/policy，不建表）以及新 transaction-first 路径目标 timing：**Reserve before PaymentSession；physical consume during canonical Finalize；Commit fact after successful physical consumption**。
* FR-005：P3-0 未批准前，禁止 migration、禁止 Reservation schema 修改、禁止接入 Transactions::Start/Finalize/Recover。

### INV-P3-1 — Reservation Lifecycle Foundation

* FR-006：现有 `pallastrade_stock_reservations` 增加显式生命周期，冻结：

  * RESERVED
  * COMMITTED
  * RELEASED
  * EXPIRED
* FR-007：候选新增字段（最终以 P3-0 DB_PROPOSAL 为准）：

  * `state`
  * `reserved_at`
  * `committed_at`
  * `released_at`
  * `expired_at`
  * `release_reason`
  * `commerce_transaction_id`（可空 FK，优先使用明确领域命名，避免与 PSP transaction_id 混淆）
  * `lock_version`（仅在确有并发需要且不与项目既有 locking 约定冲突时）
  * 已有 `expires_at` 保留。
* FR-008：禁止创建第二张 Reservation 表；Reservation 继续关联现有 `order_id / line_item_id / stock_item_id`，`commerce_transaction_id` 用于 transaction ownership/trace；历史/legacy 行允许 transaction FK 为 NULL。
* FR-009：Release/Expire 从硬删除改为状态流转：

  * RESERVED → RELEASED
  * RESERVED → EXPIRED
  * RESERVED → COMMITTED
  * 正常情况下 COMMITTED/RELEASED/EXPIRED 均不得回到 RESERVED。
* FR-010：`Stock::Quantifier#reserved_quantity` 只统计：

  * `state = RESERVED`
  * 且 `expires_at > now`
    的 Reservation。
    COMMITTED / RELEASED / EXPIRED 均不得继续降低 ATS。
* FR-011：现有 active 唯一约束必须适配历史保留模型。目标语义为：同一 `stock_item + line_item` 同时最多一个 RESERVED Reservation；历史 COMMITTED/RELEASED/EXPIRED 允许保留。优先采用 partial unique index 或项目数据库约定下的等价方案。
* FR-012：历史 migration/backfill 策略必须安全：

  * 既有活跃 Reservation 映射 RESERVED；
  * transaction ownership 无法确定则保持 NULL；
  * 不修改已经部署的旧 migration，只新增 migration；
  * migration 必须支持 rollback 或给出不可逆理由。

### INV-P3-2 — Transaction Snapshot V2 + Reserve Integration

* FR-013：Transaction Snapshot 引入 schema version，P3 新创建 Transaction 使用 `snapshot_schema_version = 2`；禁止修改已经冻结的历史 P2 Snapshot。
* FR-014：Snapshot V2 增加 immutable inventory demand evidence，至少包含各 participant：

  * order_id
  * line_item_id
  * variant_id / SKU reference
  * quantity
  * stock_requirement（REQUIRED / NOT_REQUIRED）
  * participant amount/currency 等现有 transaction evidence。
* FR-015：Snapshot 仅是 demand evidence；实时库存可用性仍由 Inventory Domain/StockItem/Quantifier 判定。历史 Snapshot V1 在 Resume/Recovery 时允许从 `TransactionOrder → Order → line_items` compatibility resolve demand，但不得回写旧 snapshot。
* FR-016：引入 `InventoryReservationPort` / `StockReservationAdapter`，目标 contract 至少覆盖：

  * reserve
  * release
  * status
  * extend/refresh（如 TTL 策略需要）
    Commit 可以通过独立 `StockReservations::Commit` / `InventoryCommitCoordinator` 实现，但其语义必须是**physical consumption 成功后的事实确认**，不能成为第二套 physical decrement。
* FR-017：`Transactions::Start` canonical 顺序调整为：

  * Checkout/quote validation
  * Freeze Snapshot V2
  * Resolve InventoryRequirement
  * Reserve all required inventory
  * 所有 REQUIRED item 成功 RESERVED
  * 才允许 `PaymentSessions::Start`
* FR-018：Reserve 失败：

  * 不创建新 PaymentSession；
  * 不产生 PSP side effect；
  * 返回结构化 `INSUFFICIENT_STOCK` / `INVENTORY_CHANGED`；
  * Transaction 保持可安全 Resume/取消的前支付状态。
* FR-019：Reserve 必须幂等；同 `commerce_transaction + line_item + stock_item` 重复 Reserve 不重复累计占用。
* FR-020：两个 Transaction 竞争最后一个库存必须继续复用现有 StockItem 悲观锁，只有一个成功 Reserve；禁止新建第二套库存锁。
* FR-021：组合 Transaction 首版采用 business-level all-or-nothing：

  * 按 participant 执行 Reserve；
  * 全部成功才允许支付；
  * 中途失败只释放**本次 Start attempt 新创建的 Reservation**；
  * 不得释放本次调用前已经存在且被合法复用的 Reservation；
  * 首版不要求重写成跨订单大型 DB 2PC。

### INV-P3-3 — Canonical Finalization / Commit Coordination

* FR-022：明确 P3 normal PAID path：

  ```
  PaymentFact = PAID
  → validate Reservation Guard
  → existing canonical Transactions::Finalize / Carts::Complete
  → Order#finalize! / Shipment / InventoryUnit / StockMovement physical decrement
  → physical consumption success
  → Reservation RESERVED → COMMITTED
  → Transaction completed
  ```

* FR-023：禁止实现：

  ```
  Payment PAID
  → Commit 扣 count_on_hand
  → Finalize 再通过 StockMovement 扣一次
  ```

  P3 不允许任何第二套 physical decrement。

* FR-024：建立 `InventoryCommitCoordinator` 或符合当前项目 convention 的等价 application service，职责：

  * 验证 required Reservations 存在、属于该 Transaction、数量与 demand 一致；
  * 调用/协同现有 canonical finalization primitive；
  * 确认 physical inventory consumption 成功；
  * 之后将对应 Reservation 标 COMMITTED。

* FR-025：COMMITTED 的成立条件不得仅依赖 `Payment=PAID`；必须建立在 physical consumption 成功事实之上。

* FR-026：Commit fact 必须幂等：重复 OnPaymentSuccess / Finalize / Recover 不得产生重复 StockMovement、不得重复减少 count_on_hand、不得创建重复 COMMITTED inventory fact。

* FR-027：若 Payment 已 PAID，但 canonical Finalize/physical consumption 抛异常：

  * Transaction → `recovery_required`
  * 尚未确认消费的 Reservation 保持 RESERVED
  * 不 Release
  * 不把 Payment 降级成 failed
  * 不创建新 Payment。

* FR-028：若 physical consumption 存在部分成功窗口，P3-0/P3-3 必须确认现有 DB transaction boundary；无法确定时 InventoryFactResolver 返回 AMBIGUOUS/manual_review，禁止盲目重试 StockMovement。

* FR-029：`Carts::Complete` 当前 finalize 后硬删除 Reservation 的逻辑必须改造：

  * transaction-aware path：成功 physical consumption 后标 COMMITTED，不硬删除；
  * legacy / transaction_id NULL path：可阶段性保留既有行为作为 `LEGACY INVENTORY ADAPTER`，不得一次性破坏 legacy 主链。

* FR-030：Combination Transaction 所有 participant 的物理消费成功后对应 Reservation 均进入 COMMITTED；任何 participant 未完成则 Transaction 进入 Recovery，而不是回滚已成功的 Payment/StockMovement。

### INV-P3-4 — Release / Expiration / TTL

* FR-031：正常 Release 仅允许：

  * Reservation = RESERVED
  * 且 PaymentFactResolver 确认 UNPAID
  * 且业务明确取消/终止。
* FR-032：PAID Transaction 禁止普通 Release。PAID + RESERVED 必须走 Finalize / Recovery；PAID + RELEASED 属于 critical inconsistency → manual_review。
* FR-033：订单/Transaction pre-payment cancellation 必须可靠执行 RESERVED → RELEASED；当前 `Orders::Cancel` reservation 清理缺口必须补齐。
* FR-034：COMMITTED 后的 cancel/refund/return/restock 不允许重新 Release Reservation；物理加库存继续走售后/履约 Restock/StockMovement 路径，本 P3 不重写售后库存。
* FR-035：ExpireJob 改为：

  * `RESERVED && expires_at <= now → EXPIRED`
  * 不再硬删除；
  * 注册 sidekiq scheduler；
  * 重复执行幂等。
* FR-036：Reservation TTL 到期后不得继续作为支付保证；新 PaymentSession / Resume payment 前必须检查 InventoryFact。
* FR-037：EXPIRED 后 re-reserve 必须重新依据当前 physical inventory/ATS 判断；库存不足 → `INVENTORY_CHANGED`，禁止产生新的支付副作用。
* FR-038：TTL Policy 必须明确：

  * reservation_ttl
  * payment_session_validity
  * transaction_payment_window
    的关系。
* FR-039：核心 TTL invariant：

  ```
  合法 active payment execution
  不得在仍可成功扣款时
  无保护地失去 Reservation guarantee
  ```

  实现可采用 active PaymentSession → `StockReservations::Extend`，或保证 payment execution window 不超过 reservation validity；具体策略由 P3-0 冻结。
* FR-040：Express / Apple Pay / Google Pay 等 provider UX 不得绕过 Transaction Reserve Gate。

### INV-P3-5 — InventoryFactResolver + Recovery

* FR-041：新增 `InventoryFactResolver`，至少输出：

  * NOT_REQUIRED
  * UNRESERVED
  * RESERVED
  * COMMITTED
  * RELEASED
  * EXPIRED
  * AMBIGUOUS
  * 如组合/多 participant 需要，可使用 PARTIAL 或折叠为 AMBIGUOUS。

* FR-042：InventoryFactResolver 不应只看 Reservation.state；COMMITTED 判定应校验 Order/finalization/physical inventory evidence 的一致性。出现“Reservation COMMITTED 但 physical evidence 不一致”时返回 AMBIGUOUS。

* FR-043：`Transactions::Recover` 扩展为：

  ```
  Resolve Payment Fact
  → Resolve Inventory Fact
  → Build Recovery Plan
  → Execute Safe Action
  ```

* FR-044：至少支持以下决策：

  | Payment Fact | Inventory Fact | Order      | 动作                                                      |
  | ------------ | -------------- | ---------- | ------------------------------------------------------- |
  | UNPAID       | RESERVED       | incomplete | 允许继续支付                                                  |
  | UNPAID       | EXPIRED        | incomplete | re-reserve 后才可继续                                        |
  | UNPAID       | RESERVED       | canceled   | Release                                                 |
  | PAID         | RESERVED       | incomplete | retry canonical Finalize → physical consume → COMMITTED |
  | PAID         | COMMITTED      | incomplete | retry business finalization / repair order state        |
  | PAID         | COMMITTED      | complete   | repair Transaction → completed                          |
  | PAID         | EXPIRED        | incomplete | recovery/re-reserve/reconcile；无法安全满足则 manual_review     |
  | PAID         | RELEASED       | incomplete | critical inconsistency → manual_review                  |
  | PAID         | AMBIGUOUS      | 任意         | manual_review                                           |
  | AMBIGUOUS    | 任意             | 任意         | Payment recovery first，不猜                               |

* FR-045：识别并 trace/audit：

  * PAID_BUT_INVENTORY_UNCOMMITTED
  * PAID_BUT_RESERVATION_RELEASED
  * INVENTORY_COMMITTED_BUT_ORDER_INCOMPLETE
  * RESERVATION_EXPIRED_WITH_ACTIVE_PAYMENT
  * RESERVATION_PARTIAL_FOR_COMBINATION
  * PHYSICAL_INVENTORY_FACT_AMBIGUOUS

* FR-046：Recovery 重复执行必须幂等，不创建新 Payment，不重复扣库存。

### INV-P3-6 — Combination / Legacy Convergence + Storefront Error Semantics

* FR-047：`stock_reservation_strategy = order | payment` 继续作为 legacy compatibility flag；新 transaction-first 路径统一走 Start → Reserve，不允许 legacy strategy 决定是否跳过 canonical Transaction Reserve。
* FR-048：Combination/legacy inventory 兼容逻辑集中在 adapter/convergence 层，禁止散落到 Transaction Core。
* FR-049：新增/规范 server error codes：

  * `INSUFFICIENT_STOCK`
  * `INVENTORY_CHANGED`
  * `RESERVATION_EXPIRED`
  * `INVENTORY_RECOVERY_REQUIRED`
* FR-050：Storefront 不推导 Reservation/Inventory Fact；只消费 server authoritative response，并根据错误码刷新 quote/库存或提示用户。
* FR-051：历史 P2 Transaction / legacy checkout / transaction_id NULL Reservation 可继续运行，禁止为了 P3 强制回填全部历史 transaction ownership。

### INV-P3-7 — Operational Hardening

* FR-052：Admin Transaction 页面增加 Inventory 面板：

  * Inventory Fact
  * Reservation IDs
  * Stock Item / Line Item
  * Quantity
  * Reservation State
  * Reserved At
  * Expires At
  * Committed At
  * Released At
  * Expired At
  * Release Reason
  * Inventory Error
  * Recovery Inventory Action

* FR-053：新增审计事件：

  * `inventory.reserve_started`
  * `inventory.reserved`
  * `inventory.reserve_failed`
  * `inventory.extended`
  * `inventory.commit_started`
  * `inventory.committed`
  * `inventory.commit_failed`
  * `inventory.release_started`
  * `inventory.released`
  * `inventory.release_failed`
  * `inventory.expired`
  * `inventory.recovery_started`
  * `inventory.recovery_completed`
  * `inventory.manual_review`

* FR-054：复用现有 `audit_logs + request_id + transaction_id/commerce_transaction_id`，不新建 Audit Engine。

* FR-055：Transaction trace 补完整库存链：

  ```
  CheckoutSnapshot
  → CommerceTransaction
  → Transaction Snapshot V2
  → StockReservation
  → PaymentSession
  → Payment
  → PSP
  → Order Finalization
  → StockMovement
  → Reservation COMMITTED
  → Transaction completed / recovery
  ```

* FR-056：增加最小指标 hook：

  * inventory_reservation_started_total
  * inventory_reservation_failed_total
  * inventory_commit_failed_total
  * inventory_release_failed_total
  * inventory_reservation_expired_total
  * paid_inventory_recovery_required_total
  * payment_confirmed_to_inventory_committed_latency
    不要求 P3 自建 Prometheus/Grafana。

---

## 4. 非功能需求（NFR）

* **性能**：

  * Reserve 继续复用现有 StockItem 悲观锁；
  * 不新增第二套锁；
  * Quantifier 继续保持 SQL 聚合，不允许 N+1；
  * stateful history 后为 active Reservation 查询提供适当索引，重点 `(stock_item_id, state, expires_at)`、transaction/order/line_item lookup。
* **一致性**：

  * `StockItem.count_on_hand + StockMovement` 始终为唯一 physical authority；
  * Reservation state 不得成为第二套库存数量；
  * COMMITTED fact 与 physical consumption 必须顺序一致；
  * Finalize/Recover 重复执行不得重复 StockMovement。
* **安全**：

  * 库存修改权限沿用现有 StockItem/StockMovement 权限；
  * Admin inventory 视图继续受 `can?`/store isolation 约束；
  * 不新增越权库存读取。
* **兼容**：

  * 历史 Reservation 可 transaction FK NULL；
  * backfill 不推断无法证明的 Transaction；
  * legacy checkout / `stock_reservation_strategy` 保留 compatibility；
  * `stock_reservations_enabled=false` 等现有总开关语义保持，是否允许 canonical Transaction 绕过 Reserve 必须在 P3-0 明确，不得静默改变。
* **Snapshot 兼容**：

  * 历史 Snapshot V1 不修改；
  * 新 Transaction 写 V2；
  * Recovery 对 V1 使用 compatibility demand resolver。
* **可维护性**：

  * Reserve / Release / Expire / Commit contract 分离；
  * Commit 不执行 physical decrement；
  * 所有状态流转可审计、可 trace；
  * 不复制 backorder/preorder/digital 既有规则。
* **幂等**：

  * Reserve / Release / Expire / Commit fact / Finalize / Recover 均需定义重复执行行为。
* **Scope Lock**：

  * 不重写 StockItem；
  * 不重写 StockMovement；
  * 不新增第二套 physical quantity；
  * 不重写库存计算器；
  * 不做 ERP/WMS/ATP/Safety Stock/采购预测；
  * 不做 Refund/Return/RMA/Restock 重构；
  * 不做 Inventory Ledger 全面重构；
  * 不做 Payment Router；
  * 不重写 CommerceTransaction；
  * 不引入 DB 2PC / 强制 MQ / 微服务拆分。

---

## 5. 验收标准（AC，与最终 P3 方案一致，测试一一映射）

| AC      | 对应 FR       | 判定条件                                                                            |
| ------- | ----------- | ------------------------------------------------------------------------------- |
| AC-3001 | FR-017      | 需要库存的 Transaction 在 PaymentSession 创建前成功 Reserve                                |
| AC-3002 | FR-018      | Reserve 失败不得创建 PaymentSession / Payment / PSP side effect                       |
| AC-3003 | FR-019      | 同 Transaction 重复 Reserve 不重复占用库存                                                |
| AC-3004 | FR-020      | 两个 Transaction 竞争最后一个库存只有一个成功 Reserve                                           |
| AC-3005 | FR-004      | backorder/preorder/digital/non-stock-managed 等正确跳过                              |
| AC-3006 | FR-007/008  | Reservation 与 CommerceTransaction/Order/LineItem/StockItem 可完整 trace            |
| AC-3007 | FR-013/014  | Transaction Snapshot V2 包含 immutable inventory demand evidence                  |
| AC-3008 | FR-015      | Snapshot 不成为 inventory availability authority                                   |
| AC-3009 | FR-022/023  | Payment confirmed 后仍通过现有 Finalize/StockMovement 完成唯一物理减库存                       |
| AC-3010 | FR-023      | P3 不产生第二套 physical stock decrement                                              |
| AC-3011 | FR-024/025  | Physical consumption 成功后 Reservation 才转 COMMITTED                               |
| AC-3012 | FR-010/025  | COMMITTED Reservation 不再降低 available-to-sell                                    |
| AC-3013 | FR-027      | Payment PAID + Finalize failure → recovery_required；未消费 Reservation 保持 RESERVED |
| AC-3014 | FR-043/044  | Recovery 可 PAID+RESERVED → Finalize → physical consume → COMMITTED → completed  |
| AC-3015 | FR-026/046  | 重复 Finalize/Recover 不重复扣库存                                                      |
| AC-3016 | FR-031/033  | UNPAID + canceled transaction 可安全 RESERVED→RELEASED                             |
| AC-3017 | FR-032      | PAID Transaction 不允许普通 Release                                                  |
| AC-3018 | FR-035      | TTL 到期 RESERVED→EXPIRED，不硬删除                                                    |
| AC-3019 | FR-010/035  | EXPIRED Reservation 不降低 ATS                                                     |
| AC-3020 | FR-039      | 合法 active payment execution 不因 TTL 策略静默失去库存保证                                   |
| AC-3021 | FR-036/037  | Reservation expired 后，新支付动作前必须 re-reserve                                       |
| AC-3022 | FR-021      | 组合 Transaction 全部 REQUIRED Reservation 成功后才能支付                                  |
| AC-3023 | FR-021      | 组合部分 Reserve 失败只补偿本 Start attempt 新创建的 Reservation                              |
| AC-3024 | FR-029      | transaction-aware canonical path 完成后 Reservation 不硬删除而进入 COMMITTED              |
| AC-3025 | FR-033      | Order/Transaction pre-payment cancel 正确释放仍 RESERVED 的 Reservation               |
| AC-3026 | FR-001..005 | INV-P3-0 完成 20 项产物 + 7 策略冻结，期间零 migration/零业务改码                                 |
| AC-3027 | FR-041..046 | InventoryFactResolver / Recovery 对决策矩阵给出安全结果，AMBIGUOUS 不猜                       |
| AC-3028 | FR-（基线）     | P0 Payment / P1 Checkout / P2 Transaction baseline 全绿                           |

**核心 Invariants（实施必须遵守）**：

* INV-I01：`StockItem.count_on_hand + StockMovement` 是唯一 physical inventory authority。
* INV-I02：StockReservation 只是 allocation/reservation fact。
* INV-I03：Reserve 不修改 physical count_on_hand。
* INV-I04：P3 Commit 不建立第二套库存扣减。
* INV-I05：COMMITTED 必须建立在 physical inventory consumption 成功事实之上。
* INV-I06：Reserve 必须幂等。
* INV-I07：Finalization / physical inventory consumption 必须幂等。
* INV-I08：PAID + inventory incomplete = RECOVERY_REQUIRED。
* INV-I09：PAID Transaction 不得普通 Release Reservation。
* INV-I10：只有 RESERVED 且未过期 Reservation 降低 ATS。
* INV-I11：合法 payment execution window 不得长于未被续期的 Reservation validity。
* INV-I12：Snapshot = inventory demand evidence；Inventory Domain = availability authority。
* INV-I13：Combination 必须 business-level all-reserved 后才能产生支付副作用。
* INV-I14：Fulfillment split 不自动形成新的 inventory transaction。
* INV-I15：Reservation Release ≠ physical Restock；COMMITTED 后加库存必须走售后/StockMovement 域。
* INV-I16：`PaymentSession.completed? / Payment=PAID / Reservation=COMMITTED / Order=completed` 是不同事实，不得互相替代。

---

## 6. 跨层搜索记录（6 层，gate 强制）

| 层          | 路径                                                | 搜索关键词                                                                                                                                             | 找到的文件                                                                                                                                                                                                                                                                                                                                     | 是否满足需求                                              |
| ---------- | ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| App        | `backend/app/`                                    | StockReservation / reservation / CommerceTransaction                                                                                              | 宿主层无核心库存/交易实现，主体在 core gem                                                                                                                                                                                                                                                                                                                | 否 → 不在宿主新建重复实现                                      |
| Core       | `backend/pallastrade_gems/pallastrade_core/app/`  | stock_reservation, reserve, release, extend, expire_job, quantifier, StockMovement, Shipment, InventoryUnit, commerce_transaction, transactions/* | `StockReservation`、`StockReservations::{Reserve,Release,Extend}`、ExpireJob、`Stock::{Quantifier,...}`、StockItem/StockMovement、Shipment/InventoryUnit、CommerceTransaction/TransactionOrder、Transactions::{Start,Resume,Recover,PaymentFactResolver,OnPaymentSuccess,Finalize}`、Carts::Complete、Orders::Cancel、legacy cart、split/combination | 部分满足 → 复用现有 authority/primitive，补生命周期与交易编排          |
| API        | `backend/pallastrade_gems/pallastrade_api/app/`   | stock_reservations, transactions, service errors                                                                                                  | admin stock reservation / store transaction controllers / serializers                                                                                                                                                                                                                                                                     | 部分满足 → INV-P3-6/7 只做必要错误码和只读字段                      |
| Admin      | `backend/pallastrade_gems/pallastrade_admin/app/` | transactions / stock                                                                                                                              | Transaction 页面 + stock 系列能力                                                                                                                                                                                                                                                                                                               | 部分满足 → 扩 Inventory panel                            |
| Storefront | `storefront/src/`                                 | insufficient_stock, inventory, reservation                                                                                                        | 当前库存展示主要基于 product.in_stock；Checkout 不直接消费 Reservation                                                                                                                                                                                                                                                                                    | 否 → 只消费 Server authoritative error/status，不新增前端库存规则 |
| Platform   | `platform/packages/`                              | StockReservation / transaction / generated types                                                                                                  | 已有部分 admin StockReservation type 与交易 SDK                                                                                                                                                                                                                                                                                                  | 部分满足 → API schema 变化时同步类型，不手写第二套模型                  |

**结论**：P3 是对 core inventory primitives 的**语义状态化 + CommerceTransaction 接入**。不新建 Reservation 系统、不新建 physical stock authority、不复制 Storefront inventory engine。

---

## 7. 技术影响

* **DB（P3-0 批准后）**：

  * 修改 `pallastrade_stock_reservations`，候选新增 `state`、reserved/committed/released/expired timestamps、release_reason、`commerce_transaction_id` nullable FK；
  * 调整 active uniqueness，使历史终态行可保留；
  * 增加 active Reservation / transaction lookup 索引；
  * 不新建第二张 Reservation 表；
  * 不修改历史 migration。
* **Core Model / Inventory**：

  * 扩展 `StockReservation` 生命周期；
  * `Quantifier` 只统计 active RESERVED；
  * `Reserve` 保留悲观锁；
  * `Release` 改状态语义；
  * 新增 Commit fact service/coordinator；
  * `ExpireJob` 改状态化。
* **Transaction Snapshot**：

  * 新 Transaction 写 Snapshot Schema V2；
  * 增加 inventory demand evidence；
  * 历史 Snapshot V1 保持 immutable。
* **Transaction Services**：

  * `Transactions::Start`：Reserve before PaymentSession；
  * `Transactions::Finalize`：Reservation guard + existing physical finalization + Commit fact；
  * `Transactions::Resume`：inventory validity gate；
  * `Transactions::Recover`：PaymentFact + InventoryFact；
  * `OnPaymentSuccess` 不直接把 Reservation 标 COMMITTED。
* **Canonical Finalization**：

  * 保留 `Carts::Complete` / Order/Shipment/StockMovement 真实 physical decrement；
  * transaction-aware path 不再 finalize 后 hard-delete Reservation；
  * legacy path阶段性 adapter。
* **Cancel / TTL**：

  * Orders/Transaction cancellation 接 Release；
  * ExpireJob 注册 sidekiq schedule；
  * active PaymentSession TTL extension/validation。
* **Combination**：

  * participant-level Reserve；
  * business-level all-or-nothing；
  * created-this-attempt compensation；
  * 不引入跨订单 2PC。
* **API/Storefront**：

  * 新错误码；
  * 必要 transaction inventory status projection；
  * Storefront 不自判库存。
* **Admin**：

  * Transaction Inventory panel。
* **Observability**：

  * inventory.* audit；
  * inventory trace；
  * metrics hook。
* **影响面**：实施时以 `harness affected --base origin/dev` 为准。

---

## 8. 测试计划

* **新增**：

  * `stock_reservation_spec`：RESERVED/COMMITTED/RELEASED/EXPIRED 状态、终态不可逆、timestamps/reason、active scope。
  * `stock_reservations/reserve_spec`：幂等、last-unit race、backorder/preorder bypass。
  * `stock_reservations/release_spec`：UNPAID release、PAID reject、重复 release。
  * `stock_reservations/expire_spec` / ExpireJob spec：只 expire RESERVED、重复 job 幂等。
  * `stock_reservations/commit_spec`：只在 physical consumption success 后确认 COMMITTED；不得修改 count_on_hand。
  * `inventory_fact_resolver_spec`：全部核心事实矩阵 + AMBIGUOUS。
  * `transactions/start_inventory_spec`：Snapshot V2、Reserve before PaymentSession、Reserve failure no PSP side effect。
  * `transactions/finalize_inventory_spec`：existing StockMovement once + Reservation COMMITTED。
  * `transactions/recover_inventory_spec`：PAID+RESERVED、PAID+EXPIRED、PAID+RELEASED、AMBIGUOUS。
  * `combination_inventory_spec`：all-reserved gate、partial compensation、只 release created_this_attempt。
  * cancellation + TTL/Extend specs。
  * Admin/API inventory projection/error code request specs。
* **关键集成测试规则**：

  * 不允许所有 inventory/payment tests 只通过 factory 直接制造 `Payment completed` / `Reservation committed`；
  * 至少一条关键测试经过真实 service 链：
    `Transactions::Start → Reserve → Payment completion → Finalize → StockMovement → Reservation COMMITTED`；
  * Recovery 测试必须验证重复执行不增加第二条等价 StockMovement。
* **更新**：

  * Carts::Complete specs；
  * CommerceTransaction / recovery specs；
  * Payment/Transaction critical path regression；
  * cancel / split / combination regression。
* **Release Verification**：

  * RV-I01 Normal Purchase：
    `Reserve → Payment → Finalize/StockMovement → COMMITTED`
  * RV-I02 Stock Race：
    two transactions / one final unit → one reserved
  * RV-I03 Paid Finalization Recovery：
    PAID → controlled finalize failure → recovery_required → Recover → StockMovement exactly once → COMMITTED
  * RV-I04 Combination（组合启用时）：
    N participants → all reserve → Payment → physical consume → all committed；另测 partial reserve compensation
  * RV-I05 TTL/3DS：
    active payment authentication window 不得无保护超过 Reservation validity
* **Baseline**：

  * P0 Payment critical regression；
  * P1 Checkout regression；
  * P2 CommerceTransaction / Recovery regression；
  * 全部保持 green。
* **AC→测试映射**：

  * `harness prd verify --id PRD-20260905-shipping-...`
  * 每条 AC 按仓库 convention 标注对应测试。

---

## 9. 文档同步清单（知识同步门）

* [ ] API 文档（若涉及 controller/serializer）：`backend/public/api-docs/{store,admin}.yaml` + `platform/docs/api-reference/` + SDK 类型同步；生成链按当前 R1 实际可运行模式执行。
* [ ] Skill：`pallastrade-checkout`（Reserve-before-payment）、`pallastrade-data-model`（StockReservation lifecycle / Snapshot V2）、`pallastrade-events-webhooks`（inventory.* events，如适用）、`pallastrade-payments`（PAID 与 inventory fact 边界）、`pallastrade-testing`（StockMovement exactly-once / critical path integration）。
* [ ] README / Agent 文件：如新增强制工程规范，更新根 `AGENTS.md` / copilot rules。
* [ ] 反模式库：至少记录：

  * “Commit 再扣一次 physical stock”
  * “PAID 后普通 Release”
  * “Reservation hard delete 丢失 transaction evidence”
  * “过期 Reservation 仍允许 PaymentSession”
* [ ] 研究文档：产出 `docs/research/RESEARCH-20260905-inv-p3-0-*.md`，包含 20 项产物 + 7 策略冻结。
* [ ] 本 PRD 状态与 `docs/prd/README.md` 索引同步。
* [ ] Sidekiq 配置：ExpireJob scheduler 变更同步部署文档/配置说明。
* [ ] P3 Completion Report：最终区分 `ENGINEERING COMPLETE` 与真实 RV 验证状态，不用单元测试替代库存/支付运行时验证。

---

## 10. 变更记录

### 知识同步结论（sync-check，2026-09-05）

| 资产 | 结论 |
|---|---|
| 领域 Skill（checkout / data-model / events-webhooks） | ✅ 已更新 changelog：checkout（Reserve-before-payment/Commit 语义/错误码）、data-model（StockReservation 生命周期/snapshot_schema_version V2）、events（inventory.* 事件） |
| pallastrade-payments Skill | 已评估：P3 不改支付入账语义（PAID 判定/资金不回滚沿用 P2），Finalize/Recover 仅扩展 inventory 分支 → 无正文变更（本次不改 payments skill 正文，相关结论已入 checkout/data-model changelog） |
| scenarios.json / AGENTS.md / copilot-instructions / anti-patterns | 已评估：本 PRD 为既有原语语义补全，未新增反模式/任务规则/PRD 机制变更 → **无需更新**（记录后 --ack）；如需库存生命周期 Eval 场景可在收口回归后追加 |
| README / docs 索引 | ✅ PRD README 索引 + 研究文档 RESEARCH-20260905-inv-p3-0 已更新（S2–S8 记录） |

| 日期         | 版本  | 变更                                                                                                                                                                                                                                                                       | 操作者 |
| ---------- | --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --- |
| 2026-09-05 | 0.1 | 初稿：Reserve→Commit/Release/Expire 生命周期 + CommerceTransaction / Recovery 接入                                                                                                                                                                                                | AI  |
| 2026-09-05 | 0.2 | 架构审计修订：确认 StockItem/StockMovement 为唯一物理库存权威；Commit 从“Finalize 前扣库存”改为“canonical physical consumption 成功后的 Reservation 事实确认”；新增 Snapshot V2、COMMIT_SEMANTICS、第 7 冻结策略、state-aware unique、created-this-attempt 组合补偿、TTL/3DS、InventoryFact consistency；AC 重构为 AC-3001..3028 | AI  |
| 2026-09-05 | 0.3 | INV-P3-0 只读审计完成（approved 后）：产出 `docs/research/RESEARCH-20260905-inv-p3-0-inventory-semantic-freeze.md`（20 项产物 + 7 策略冻结提案 + P3_DB_PROPOSAL/RISK_LIST/IMPLEMENTATION_PLAN），零 migration/零业务改码；**等待用户冻结 7 策略后进入 S2（INV-P3-1）** | AI  |
| 2026-09-05 | 0.4 | 7 策略用户冻结（2026-09-05）→ S2 INV-P3-1 实施完成：migration（state/时间戳/release_reason/commerce_transaction_id + partial unique + backfill，未加 lock_version，沿用 with_lock+state guard）+ StockReservation 状态机 + Quantifier active 语义 + Release→RELEASED / Commit（新）/Extend/ExpireJob 状态化 + ExpireJob cron 注册 + Carts::Complete finalize 后 Commit（AC-3024）；specs 45 例 0 失败、RuboCop 0 告警；**下一包 S3（INV-P3-2 Snapshot V2 + Start Reserve）** | AI  |
| 2026-09-05 | 0.5 | S3 INV-P3-2 实施完成：migration `snapshot_schema_version`（V1 存量兼容）+ Snapshot V2（`schema_version` + participant `inventory_demand`：line_item/variant/quantity/stock_requirement）+ `Stock::InventoryRequirement` policy（REQUIRED/NOT_REQUIRED）+ `Transactions::ReserveInventory`（InventoryReservationPort 首版：Reserve→bind→demand 校验；INSUFFICIENT_STOCK/组合 created-this-attempt 补偿）+ `Transactions::Start` 冻结 Snapshot 后插 Reserve 门（AC-3001/3002/3003/3005/3007/3008，V1 兼容 resolver `resolved_inventory_demand`）；specs 36 例 0 失败、RuboCop 0 告警；**下一包 S4（INV-P3-3 Commit Coordination in Finalize）** | AI  |
| 2026-09-05 | 0.6 | S4 INV-P3-3 实施完成：`Transactions::Finalize` 成功路径加交易级 Commit 兜底（`StockReservations::Commit(transaction:)`，幂等、无第二套扣减；participant 级已由 Carts::Complete finalize 后 Commit 覆盖）+ 失败路径先 reload 再 recovery_required（reservation 保留 RESERVED）；specs：新增 finalize_inventory（AC-3011 commit 兜底 / AC-3013 失败→recovery_required）+ reserve_strategy 断言改为 COMMITTED（AC-3024）——15 例 0 失败、RuboCop 0；**下一包 S5（INV-P3-4 Release/Expire 接线 + Cancel/TTL/Resume 门）** | AI  |
| 2026-09-05 | 0.7 | S5 INV-P3-4 实施完成：`Orders::Cancel` 取消决策时点捕获 release_allowed（取消前基于权威支付事实：payment_total/completed payment/进行中 attempt → 禁止 Release，INV-I09），成功后 `StockReservations::Release(reason: order_canceled)` 释放未支付 RESERVED（FR-032/033/034；COMMITTED 行天然不受影响）；`ReserveInventory` 区分错误码（该 line_item 曾 EXPIRED 且无法重预留 → `INVENTORY_CHANGED`，FR-037；否则 INSUFFICIENT_STOCK）；Resume 支付重试经 Start 复用路径已有 Reserve 门（FR-036/AC-3021）+ 每次 Start（re）reserve 刷新 TTL（TTL 不变量 FR-039）；specs：新增 cancel_inventory + INVENTORY_CHANGED 场景——S2~S5 综合 51 例 0 失败、RuboCop 0；**下一包 S6（INV-P3-5 InventoryFactResolver + Recovery）** | AI  |
| 2026-09-05 | 0.8 | S6 INV-P3-5 实施完成：新增 `Transactions::InventoryFactResolver`（只读：NOT_REQUIRED/UNRESERVED/RESERVED/COMMITTED/RELEASED/EXPIRED/AMBIGUOUS；COMMITTED 需订单完成证据，PARTIAL 组合折叠 AMBIGUOUS）；`Transactions::Recover` PAID 分支扩展 InventoryFact 决策——RELEASED/EXPIRED/AMBIGUOUS 且参与者未完成 → `manual_review`（不猜/不重复扣），RESERVED/COMMITTED 维持 finalize/repair（FR-043/044/AC-3027）；specs：inventory_fact_resolver 矩阵 + recover_inventory（PAID+RELEASED→manual_review；PAID+RESERVED→继续 finalize）——17 例 0 失败、RuboCop 0；**下一包 S7（INV-P3-6 Combination/Legacy + Storefront 错误码）** | AI  |
| 2026-09-05 | 0.9 | S7 INV-P3-6 实施完成：`Transactions::Start` 终态阻止对 recovery_required/manual_review 暴露 `INVENTORY_RECOVERY_REQUIRED`（FR-049；payment_confirmed 等仍 transaction_not_payable）；Storefront BFF `/api/checkout/start` 透传 SDK `PallasTradeError` 的 code/message/HTTP status（INSUFFICIENT_STOCK/INVENTORY_CHANGED/INVENTORY_RECOVERY_REQUIRED 等；Storefront 不自判库存，FR-050），保留通用 502 回退；新 route 测试（转发 INSUFFICIENT_STOCK 422）——后端 Start 8 例 + storefront 5 例 0 失败、RuboCop 0；legacy strategy/历史 reservation 兼容不动（FR-047/051）；**下一包 S8（INV-P3-7 Admin inventory 面板 + inventory.* 审计/trace/metrics + 知识同步 + 收尾）** | AI  |
| 2026-09-05 | 1.0 | S8 INV-P3-7（核心代码）：Admin Transaction show 页新增 **Inventory 面板**（Inventory Fact verdict+reasons、Reservation 表：state/line_item/stock_item/qty/expires/reserved/committed/released/expired/reason，只读，FR-052）；`StockReservation` 状态发布 **inventory.* 审计事件**（reserved/committed/released/expired，after_create/after_transition，复用 Events/audit_logs，FR-053/054；指标 hook 由事件/结构化日志承载，FR-056 不自建 Prometheus）；specs：模型/服务 20 例 + admin request 6 例 0 失败、RuboCop 0；**收尾待办：知识同步（skills/README/scenarios）、全量回归、generated:check/doc-impact/sync-check、evidence/coverage-gate、recovery plan、统一提交** | AI  |
| 2026-09-05 | 1.1 | **实施完成**：全量 backend **747 examples 0 failures**（verifier:backend-rspec POST-COMMIT 证据绑定 `8a0e8b8`）；Gate `GATE-2026-09-05T11-06-29` CLEARED（16/16，evidence verify 四类型 test/review/approval/knowledge + coverage-gate justified clear，monolith line 71.77% < 80 为恒态，历史 gate 同先例）；统一提交 `8a0e8b8`（42 files/+2824，含 migration 20260905000001/02 + schema.rb，排除 `豆包梳理业务需求/`）；同步修复 2 个 **dev 基线回归**（非 P3 引入）：① `gateway/bogus.rb` 防重复扣款——legacy 已全额入账（payment_total 覆盖 total）时不再 find_or_create_payment!（否则 Payment max_amount=0 → 422/重复扣款），仅 complete session；② admin nav AC-007 spec 补 `:transactions` 子项（TXN-P2-7 新增但 spec 未同步）；task `TASK-20260905110600-942c63c2` finished with verified evidence；新增 Eval Scenario **GS-049**（`harness/scenarios/scenarios.json`，commit `b19df7e`）；push `dev`（4c2caaf..b19df7e）触发 CI + pull-deploy | AI  |
| 2026-09-05 | 1.2 | **审计收口（bugfix gate `GATE-2026-09-05T14-33-21`，task `TASK-20260905143300-08830526`）**，落实审计发现 D1–D7：**D2** ExpireJob 不再过期“已捕获支付/已完成订单”的 RESERVED（保留至 Commit/Recover，消除 expired-consume 竞态）；**D3** 新增 `PaymentSessionReservationSubscriber`（`payment_session.processing` → `StockReservations::Extend` 刷新 RESERVED TTL，FR-039/AC-3020）+ Start 每次 reserve 已刷新；**D1** ExpireJob 逐行走状态机 `expire!` → 补发 `inventory.expired` 审计事件（原 update_all 旁路）；**D6** 新增 `recover_inventory_exactly_once_spec`（RV-I03：重复 Recover/Finalize 不产生第二条 StockMovement、恰一次 COMMITTED）；**D7** `Release` 增加 PAID 防御 guard（`reservation_release_blocked_paid`，`allow_paid:` 显式放行）；**D5** 新测试补 AC 标注；**D4** research 文档 InventoryFactResolver committed 语义文字对齐；验证：P3 域回归 96 例 + 新/改 spec 16 例 0 失败、RuboCop 0；详细记录见 `docs/research/RESEARCH-20260905-inv-p3-0-inventory-semantic-freeze.md` §审计收口 | AI  |
