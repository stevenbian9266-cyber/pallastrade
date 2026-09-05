# RESEARCH-20260905-inv-p3-0 — Inventory Semantic Freeze（INV-P3-0）

> 日期：2026-09-05 ｜ 来源：`豆包梳理业务需求/P3 — Inventory Transaction Integration & Reservation Lifecycle.md`（INV-P3）
> Task：`TASK-20260905110600-942c63c2`；Gate：`GATE-2026-09-05T11-06-29`（feature，INV-P3-0 只读阶段）
> 分支：dev @ 4c2caaf7 ｜ 性质：**只读语义审计 — 无 Coding / 无 migration / 未修改任何 Reservation/Transaction schema**
> 关联：`PRD-20260905-shipping-库存事务集成与预留生命周期-p3-stockreservation-接入-commercetransaction-res`（v0.2 approved）；`REQ-20260905-inv-p3.md`
> 状态：**DRAFT — 等待用户冻结 7 策略（FR-005/AC-3026）**；冻结通过前禁止 INV-P3-1 migration / schema 修改 / 接入 Start/Finalize/Recover

---

## 0. TL;DR

1. **物理库存权威唯一**：`StockItem.count_on_hand`（每 variant×location）+ `StockMovement`（`after_create` 驱动 `adjust_count_on_hand`）。当前无 `allocated_count` 列（5.5 shim 恒 0）。
2. **Reservation = soft allocation**：`Stock::Quantifier` 的 ATS = `max(count_on_hand − active reservations, 0)`；`Reserve` **不修改 count_on_hand**。
3. **真实物理扣减发生在 canonical finalization**：`Order#finalize! → Shipment#finalize!（inventory_units.finalize_units! + after_resume→manifest_unstock）→ StockMovement(负) → count_on_hand 扣减`；cancel 经 shipment `after_cancel→manifest_restock` 加回。
4. **支付成功后的 legacy `Release`（Carts::Complete finalize 之后）= 消费完成后的 reservation 行清理（硬删除），不是"把库存加回来"**——因为库存已在 finalize 扣减。语义方向正确但硬删除抹掉了 COMMITTED 证据（P3-0 Q6 命中）。
5. **缺口确认**：无显式生命周期状态；`Reserve` 与 `CommerceTransaction` 无关联（`Transactions::Start` 无 Reserve 阶段，标准流 Submit→payment 之间无预留）；`Orders::Cancel` 不清理 RESERVED 行（只能等 TTL）；`ExpireJob` 未注册 sidekiq cron；Snapshot 无 items demand evidence（V2 需补）。
6. **本次冻结 7 策略（§7）**，产出 20 项审计产物（§8）。全部为"建议决策"，等待用户冻结。

---

## 1. CURRENT_INVENTORY_ARCHITECTURE

```
StockItem.count_on_hand（variant × stock_location）
    ▲ 由 StockMovement.after_create → adjust_count_on_hand 驱动
    │
Stock::Quantifier：ATS = max(count_on_hand − Σ active Reservation(其他 order), 0)
    ▲ 只读实时可售（含 excluded_order 自身预留豁免）
    │
StockReservation（soft allocation，不改 count_on_hand）
    ├─ Reserve：悲观锁 stock_items → held_by_others → upsert（unique stock_item+line_item）
    ├─ Release：delete_all（硬删除）
    ├─ Extend：批量续 expires_at
    └─ ExpireJob：delete 过期行（未调度）
    │
Order 完成链（真实扣减）：
  Carts::Complete / Transactions::Finalize → Order#finalize!
    → Shipment#finalize!（inventory_units.finalize_units! + after_resume→manifest_unstock）
    → StockMovement(−qty) → count_on_hand ↓
取消链：Order/Order::Cancel → shipment after_cancel→manifest_restock → StockMovement(+qty)
```

关键结论：
- `count_on_hand` 扣减点 = **order finalize（物理消费）**，与 Reservation **完全脱钩**；Reservation 只通过 `Quantifier` 查询影响"软可售"。
- 因此 P3 **不应让 Commit 再扣一次 count_on_hand**（否则 double decrement），COMMITTED 只能是"physical consumption 成功之后的事实确认"。

## 2. INVENTORY_AUTHORITY_MATRIX

| 事实 | 权威来源 | 更新者 |
|---|---|---|
| Physical on-hand | `StockItem.count_on_hand`（唯一） | `StockMovement.after_create`；admin stock transfer/adjust |
| Physical movement ledger | `StockMovement`（readonly after persist，polymorphic originator） | StockLocation#move/restock/unstock |
| Allocated（未发货占用） | 无列；5.5 `allocated_count` shim=0（6.0 计划加列） | — |
| ATS / 可售 | `Stock::Quantifier`（SQL 聚合） | 只读 |
| Soft reservation | `StockReservation` 行（quantity/expires_at） | Reserve/Release/Extend/Expire |
| 履约分配 | `InventoryUnit`（on_hand/backordered）+ `Shipment` state | Coordinator / Shipment 状态机 |
| 订单完成事实 | `Order.completed_at` / `state` | Order#finalize!（canonical） |

## 3. RESERVE_SEMANTICS

- 触发（全仓 grep 证据）：legacy cart 操作（`:order` 策略，`cart_legacy/{add_item,set_quantity,remove_line_item}`，仅 `in_checkout?` 时）与 `Carts::Complete`（`:payment` 策略，支付后 finalize 前）。
- 目标构建：`build_targets` 只选 `should_track_inventory? && !backorderable? && !preorder? && 有非 backorderable 有货 stock_item` 的 line_item。
- 幂等：`unique(stock_item_id, line_item_id)` upsert；同 order 重复 reserve 更新 quantity 不累计（`this_order_used` 在本批内计数）。
- 并发：`StockItem.where(id:...).lock` 悲观锁序列化，`held_by_others` 排除本 order → 最后一件只有一个成功。
- **不扣 count_on_hand**；`validate_only`（`:payment` 模式 cart 期只校验不落行）。
- 豁免：backorderable / preorder（oversell 由 `Quantifier#can_supply?` + `backorder_limit` 管）；digital / non-stock-managed 天然不 track。

## 4. RELEASE_SEMANTICS

- `Release.call(order:)` = `StockReservation.where(order_id:).delete_all`（**硬删除**）。
- 调用点（全仓）：`Carts::Complete`（legacy complete 后 & standard finalize 后）、`cart_legacy/empty`。
- **支付成功后 Release 的真实语义 = 消费完成后的 reservation 记录清理**（库存已由 finalize 的 StockMovement 扣减），**不是恢复可售库存**。
- **取消路径不调用 Release**：`Orders::Cancel → order.cancel!`（→ shipment after_cancel restock 物理库存），但**不删除 RESERVED 行** → 该行继续降低 ATS 直到 TTL 过期被 `active` 过滤。
- **结论（P3 §12/§13 对应）**：当前"支付后 Release"方向是对的（consume 语义），但以 delete 表达 → 缺 COMMITTED 可追溯；"取消释放"路径缺失 → 需补 RELEASED。

## 5. PHYSICAL_CONSUMPTION_MATRIX

| 路径 | 物理扣减 | 时点 | 证据 |
|---|---|---|---|
| standard（Carts::Submit 订单） | `Order#finalize! → Shipment#finalize! → manifest_unstock → StockMovement(−)` | 支付成功后 finalize | carts/complete.rb `complete_standard_order!`（pay!→finalize!） |
| legacy checkout complete | 同上（state_machine after_transition to complete → finalize!） | checkout complete | order/checkout.rb `after_transition to: :complete, do: :finalize!` |
| 组合成员（standard） | `CombinationMemberComplete → Carts::Complete` | 组合入账后 | payments skill / finalize.rb |
| 取消 restock | `Shipment after_cancel → manifest_restock → StockMovement(+)` | cancel | shipment.rb |
| 拆单（AutoSplit/ManualSplit） | 完成后拆分；子单继承 inventory units/stock location | 支付后 | splitter/autosplit |
| 售后 restock | return/reimbursement 域 StockMovement | 售后 | return_item.rb |

## 6. COMMIT_GAP_ANALYSIS

| P3 期望 | 现状 | Gap |
|---|---|---|
| RESERVED 显式状态 | 无 state 列；active=expires_at>now | 需加 state |
| COMMITTED 显式事实 | 无；finalize 扣库存后 legacy Release=删行 | **缺 COMMITTED**（P3 最大补全） |
| Commit 幂等 | 无 commit 概念 | 需建 Commit fact service |
| Release=undo（未消费） | 取消不清理 → 泄漏 | 需 RELEASED + 取消接线 |
| Expire=时间失效 | ExpireJob 硬删 + 未调度 | 需 EXPIRED + 调度 |
| 交易归属 | Reservation.order 粒度，无 txn FK | 需 commerce_transaction_id（可空） |
| 事务内 reserve 时点 | Start 无 Reserve；:order 只在 legacy cart | 需 Start→Reserve（Snapshot V2） |
| PAID+未消费 Recovery | P2 Recover 无 InventoryFact | 需 InventoryFactResolver + 决策矩阵 |

## 7. 冻结策略（7 项 — 等待用户冻结）

### S1 INVENTORY_AUTHORITY
`StockItem.count_on_hand + StockMovement` 为唯一 physical authority；`Stock::Quantifier` 为可售计算唯一入口；**P3 不建第二套 physical quantity / decrement**。

### S2 RESERVATION_IDENTITY
保留 `order_id + line_item_id + stock_item_id` 粒度与 `unique(stock_item_id, line_item_id)` 的 RESERVED 活跃唯一性；新增可空 `commerce_transaction_id`（FK `pallastrade_commerce_transactions`，命名避免与 PSP transaction_id 混淆）做 ownership/trace；历史/legacy 行允许 NULL。**不建 transaction_inventory_reservations 第二张表**。

### S3 RESERVATION_LIFECYCLE
冻结 RESERVED / COMMITTED / RELEASED / EXPIRED 四态 + timestamps（reserved_at/committed_at/released_at/expired_at）+ release_reason；RESERVED 可 → COMMITTED/RELEASED/EXPIRED；COMMITTED/RELEASED/EXPIRED 终态不可回 RESERVED。Release/Expire 从 delete 改状态流转。`active` scope = `state=RESERVED AND expires_at>now`。

### S4 RESERVATION_TIMING
新 transaction-first 路径冻结：**Start（Snapshot V2 冻结）→ Reserve 全部 REQUIRED → 全 RESERVED 才 PaymentSessions::Start → Payment → canonical Finalize（物理扣减）→ COMMITTED → complete**。`stock_reservation_strategy=order|payment` 保留为 legacy compatibility flag，不影响 canonical Transaction Reserve。

### S5 RESERVATION_TTL_POLICY
定义 `reservation_ttl`（store preference/全局默认 10min 现状）与 `transaction_payment_window`/active payment session validity 关系；冻结不变量：**合法 active payment execution 不得无保护地超过未被续期的 reservation validity**。实现选型：active PaymentSession → `StockReservations::Extend`（现成）或 PSP window ≤ TTL；ExpireJob 注册 sidekiq cron。

### S6 INVENTORY_RECOVERY_POLICY
Recovery 阶段化：Resolve Payment Fact → Resolve Inventory Fact（InventoryFactResolver）→ Decide/Execute；判定矩阵见 §10；AMBIGUOUS 一律 manual_review 不猜；重复执行幂等（不新增 Payment / 不重复 StockMovement）。

### S7 COMMIT_SEMANTICS
**COMMIT ≠ 第二次物理扣减**。COMMIT = canonical physical consumption（existing Finalize/StockMovement）成功后的 Reservation 事实确认（RESERVED→COMMITTED，写 committed_at）。Commit fact 幂等；只可在 physical consume 成功后确认；PAID 但未确认 consume → recovery_required 而非 commit。

## 8. 审计产物清单（FR-001 20 项映射）

1. CURRENT_INVENTORY_ARCHITECTURE — §1
2. INVENTORY_AUTHORITY_MATRIX — §2
3. RESERVE_SEMANTICS — §3
4. RELEASE_SEMANTICS — §4
5. PHYSICAL_CONSUMPTION_MATRIX — §5
6. COMMIT_GAP_ANALYSIS — §6
7. COMMIT_SEMANTICS — §7-S7
8. RESERVATION_STATE_MODEL — §9
9. TRANSACTION_RESERVATION_CARDINALITY — §9
10. RESERVATION_TIMING_MATRIX — §11
11. TTL_AND_PAYMENT_WINDOW_MATRIX — §12
12. COMBINATION_RESERVATION_MATRIX — §13
13. SPLIT_ORDER_RESERVATION_MATRIX — §13
14. BACKORDER_PREORDER_MATRIX — §13
15. INVENTORY_RECOVERY_MATRIX — §10
16. LEGACY_INVENTORY_PATHS — §14
17. P3_REUSE_MATRIX — §15
18. P3_DB_PROPOSAL — §16
19. P3_RISK_LIST — §17
20. P3_IMPLEMENTATION_PLAN — §18

## 9. RESERVATION_STATE_MODEL + TRANSACTION_RESERVATION_CARDINALITY

```
RESERVED ──(payment+finalize+physical consume success)──▶ COMMITTED
RESERVED ──(UNPAID cancel/timeout, PaymentFactResolver 门控)──▶ RELEASED (release_reason)
RESERVED ──(TTL expires_at <= now)──▶ EXPIRED
COMMITTED / RELEASED / EXPIRED：终态，不回 RESERVED
```

- `1 CommerceTransaction : N Reservation`（经 order 间接 + `commerce_transaction_id` 归属）；`1 Order : N Reservation`（order_id 现有）；`1 line_item : ≤1 active RESERVED`（unique）。
- ATS 只受 `RESERVED && expires_at>now` 影响（Quantifier 改造）。

## 10. INVENTORY_RECOVERY_MATRIX（供 P3-5）

| Payment | Inventory | Order | 动作 |
|---|---|---|---|
| UNPAID | RESERVED | incomplete | 允许继续支付 |
| UNPAID | EXPIRED | incomplete | re-reserve 后才可继续 |
| UNPAID | RESERVED | canceled | Release（RELEASED） |
| PAID | RESERVED | incomplete | retry canonical Finalize → physical consume → COMMITTED |
| PAID | COMMITTED | incomplete | retry business finalization / repair order |
| PAID | COMMITTED | complete | repair Transaction → completed |
| PAID | EXPIRED | incomplete | recovery/re-reserve/reconcile；无法安全满足 → manual_review |
| PAID | RELEASED | incomplete | critical inconsistency → manual_review |
| PAID | AMBIGUOUS | 任意 | manual_review |
| AMBIGUOUS | 任意 | 任意 | Payment recovery first，不猜 |

## 11. RESERVATION_TIMING_MATRIX

| 路径 | 现状 timing | P3 目标 |
|---|---|---|
| standard+txn（新） | 无 Reserve（Submit→payment 空窗） | Start（Snapshot V2）→ Reserve → payment_pending → PaymentSessions::Start |
| legacy checkout（:order） | cart 操作 Reserve（in_checkout?） | 兼容保留 |
| legacy/standard（:payment） | Carts::Complete 支付后 Reserve→finalize→Release | 兼容保留；txn 路径不受其影响 |
| 组合 | 无 transaction 级 Reserve（按单） | business-level all-reserved 后支付 |

## 12. TTL_AND_PAYMENT_WINDOW_MATRIX

| 项 | 现状 | P3 |
|---|---|---|
| reservation_ttl | store preferred（默认 10min）→ Config 兜底 10min | 保留；冻结不变量 |
| active payment session validity | 无显式定义（PaymentSession reuse 30min 窗口属 P0 行为） | 定义并与 TTL 对齐 |
| 3DS/PSP 认证窗口 | 无保护 | active session → Extend 或 PSP window ≤ TTL |
| ExpireJob | 存在但**未在 sidekiq_schedule.rb 注册** | 注册 cron；改标 EXPIRED 非删除 |

## 13. COMBINATION / SPLIT / BACKORDER-PREORDER MATRIX

- 组合：reservation 按 order 独立；无"一次原子 Reserve N 单"现成实现 → P3-2 用 business-level all-or-nothing + created-this-attempt 补偿（不 2PC）。
- 拆单（AutoSplit/ManualSplit）：均在订单完成后（reservation 已被清理）→ fulfillment split 不产生新 inventory transaction（INV-I14）；reservation 不随拆迁移（已 COMMITTED/清理）。
- backorder/preorder/digital/non-stock：`Reserve` 已豁免（build_targets 跳过）；`Quantifier#can_supply?` 管 oversell；P3 保持不复制规则。

## 14. LEGACY_INVENTORY_PATHS

- legacy cart（Order-as-cart）：cart_legacy 操作在 `in_checkout?` 时 Reserve/Release；`LineItem dependent: :destroy` 级联删自身 reservation 行（remove_line_item 注释确认）；empty → Release。
- legacy checkout complete：状态机 `after_transition to complete → finalize!`（物理扣减）+ `Carts::Complete` legacy 分支 finalize 后 Release（删行）。
- `:payment` 策略：cart 期 `Reserve(validate_only: true)`；complete 支付后真 Reserve → finalize → Release。
- 历史/存量：无 state 的 reservation 行 backfill 映射 RESERVED；无 txn 归属保持 NULL；**禁止为 P3 强制回填全部历史 transaction ownership**（FR-051）。

## 15. P3_REUSE_MATRIX

| 能力 | 定位 |
|---|---|
| StockReservation 行 + TTL + 悲观锁 + 豁免 | REUSE / EXTEND（状态化） |
| StockReservations::Reserve（含 validate_only） | REUSE as low-level primitive（Port adapter 内） |
| StockReservations::Release | WRAP（改状态语义，legacy delete 收 adapter） |
| StockReservations::Extend | REUSE（TTL 延长/active session） |
| Stock::Quantifier | REUSE（ATS 计算，改只统计 active RESERVED） |
| StockItem/StockMovement/Shipment/InventoryUnit | REUSE（canonical physical consumption，**不重写**） |
| CommerceTransaction / TransactionOrder / Snapshot | REUSE（Snapshot V2 扩展 demand evidence） |
| Transactions::Start/Finalize/Recover/PaymentFactResolver | EXTEND（Reserve/Commit/InventoryFact 阶段） |
| Carts::Complete | KEEP canonical finalization primitive；txn-aware 分支改 COMMITTED 不硬删 |
| Orders::Cancel | EXTEND（取消接 Release） |
| PaymentFactResolver / audit_logs / Admin Transactions | REUSE / EXTEND |

## 16. P3_DB_PROPOSAL（仅提案 — 冻结前禁止 migration）

对 `pallastrade_stock_reservations` 新增（新 migration，不改历史 migration；支持 rollback）：
- `state`（string，默认 `reserved`，索引或 partial index 按查询定）
- `reserved_at` / `committed_at` / `released_at` / `expired_at`（datetime，可空）
- `release_reason`（string，可空）
- `commerce_transaction_id`（bigint 可空 FK → pallastrade_commerce_transactions）
- `lock_version`（integer 默认 0）— 仅在确认与项目并发约定一致且确有需要时启用
- 索引：active reservation 查询 `(stock_item_id, state, expires_at)`；transaction lookup `(commerce_transaction_id)`；保留/调整 `unique(stock_item_id, line_item_id)` 为 **partial unique（WHERE state='reserved'）** 以允许历史终态保留（Postgres 支持；MySQL 需等价格局方案——P3-0 冻结时确认 DB）
- backfill：现有活跃行（expires_at>now）→ `state=reserved, reserved_at=created_at`；过期行 → `state=expired, expired_at=expires_at`（或按 DB_PROPOSAL 定）；不动历史 migration
- **不新建第二张 Reservation 表；不修改 StockItem/StockMovement schema**

## 17. P3_RISK_LIST

| # | 风险 | 等级 | 缓解 |
|---|---|---|---|
| R1 | canonical finalization primitive 改造（Carts::Complete 硬删 Release→COMMITTED）波及 legacy 与组合路径 | 🔴 | txn-aware 分支先行；legacy/transaction_id NULL 收 `LEGACY INVENTORY ADAPTER` 保留现行为，Strangler 收敛 |
| R2 | state-aware 唯一约束在 MySQL 无 partial index | 🟠 | P3-0 冻结确认 DB（Postgres 用 partial unique；否则应用层 guard + 常规索引） |
| R3 | Quantifier 过滤 state 后历史行膨胀 | 🟠 | active 查询带 state+expires_at 索引；ExpireJob 定期清理终态历史（策略化） |
| R4 | Commit 与 Finalize 时序：physical consume 成功但 commit 写失败 | 🟠 | finalize 幂等（order completed 短路）；recovery 重入最终一致；StockMovement exactly-once 靠现有 originator 幂等语义 + DB 约束 |
| R5 | 重复 Recover 触发第二条 StockMovement | 🔴 | 依赖现有 finalize/order.completed 幂等 + reservation state guard（RESERVED→COMMITTED 一次性）；测试 RV-I03 强制 |
| R6 | legacy `:payment` 策略"钱先扣再 Reserve 失败"现状缺口 | 🟠 | 新 txn 路径根治；legacy 保持并记录（非 P3 首包范围） |
| R7 | 长 3DS/PSP 认证窗口超过 reservation TTL | 🟠 | S5 TTL 不变量 + Extend（RV-I05） |
| R8 | P0/P1/P2 baseline 回归 | 🟠 | 每包最小验证 + baseline regression（AC-3028） |

## 18. P3_IMPLEMENTATION_PLAN（冻结后执行）

```
S2 INV-P3-1 Lifecycle Foundation：migration（§16）+ StockReservation 状态机/时间戳 + Quantifier + ExpireJob 状态化+调度 + backfill  spec
S3 INV-P3-2 Snapshot V2 + Reserve：snapshot_schema_version=2 + demand evidence；InventoryReservationPort/StockReservationAdapter；Transactions::Start 插 Reserve（幂等/悲观锁/组合 business-level）
S4 INV-P3-3 Commit Coordination：InventoryCommitCoordinator + Transactions::Finalize（reservation guard + physical consume 后 COMMITTED）+ Carts::Complete txn-aware 分支
S5 INV-P3-4 Release/Expire/TTL：Release 门控（PaymentFact）+ Orders::Cancel 接线 + ExpireJob cron + TTL 不变量 + Extend
S6 INV-P3-5 Inventory Recovery：InventoryFactResolver + Transactions::Recover 扩展（§10 矩阵）
S7 INV-P3-6 Combination/Legacy Convergence + Storefront 错误码
S8 INV-P3-7 Operational：Admin inventory 面板 + inventory.* 审计 + trace + metrics hook
```

每包：spec（标注 PRD AC）→ quick/full check → generated:check（涉及 API）→ evidence → commit。

---

## 附：P3-0 必答问题 → 结论对照（P3 源 §52）

| # | 问题 | 结论 |
|---|---|---|
| 1 | 库存 authority | `StockItem.count_on_hand` + `StockMovement`（§2） |
| 2 | Reserve 是否降低 ATS | 是——通过 `Quantifier` 动态减（active reservations），不改 count_on_hand（§3） |
| 3 | Release 是否恢复 ATS | legacy 删行后不再占用 → ATS 恢复（但这是清理已消费预留）；取消路径**不**恢复（缺口）（§4） |
| 4 | 支付成功后怎么正式扣库存 | canonical `Order#finalize!→Shipment/StockMovement`（§5） |
| 5 | 隐式 commit？ | 无显式 commit；finalize 物理扣减即"隐式消费"，legacy Release=清理（§6） |
| 6 | 删除后能否证明曾消费 | **不能**（硬删除丢 COMMITTED 证据）→ P3-1 状态化（§6/§9） |
| 7/8 | TTL / expiration job | TTL 存在（store 默认 10min）；ExpireJob 存在但**未调度**（§12/§14） |
| 9 | order vs payment 策略资金风险 | `:payment`：钱先扣 → Reserve 失败会卡（legacy 缺口）；`:order` legacy cart 预留；新 txn 路径 Start-Reserve 根治（§11） |
| 10 | 3DS 是否可能超 TTL | 可能；无保护 → S5 不变量（§12，RV-I05） |
| 11/12 | 组合/拆单 | 无组合级原子 Reserve；拆单发生在完成后不涉及 reservation 迁移（§13） |
| 13 | completed order 的 reservation 终态 | 现为"被删"（无终态证据）→ P3 后为 COMMITTED（§6/§9） |
| 14 | backorder/preorder 是否绕过 | 是（Reserve build_targets 豁免；can_supply? 管 oversell）（§3/§13） |
| 15 | 取消是否可靠释放 | **否**（Orders::Cancel 不清理 RESERVED 行）→ P3-4 接线（§4/§17-R6） |

---

## S2 实施记录（INV-P3-1，2026-09-05）

- migration `20260905000001_add_lifecycle_to_pallastrade_stock_reservations.rb` 已应用（test + dev）：
  - 新增 `state`（默认 reserved）、`reserved_at/committed_at/released_at/expired_at`、`release_reason`、`commerce_transaction_id`（可空 FK，index）；
  - 唯一约束改为 partial unique `(stock_item_id, line_item_id) WHERE state='reserved'`；新增热路径索引 `(stock_item_id, state, expires_at)`；
  - backfill：`reserved_at=created_at`；已过 TTL 存量行 → `state=expired, expired_at=expires_at`。
- **lock_version 决策偏差（相对 §16 提案）**：未加 `lock_version`。理由：`CommerceTransaction` 同域先例用 `with_lock`（悲观行锁）+ state guard，无乐观锁列；StockReservation 的并发已在 Reserve 处由 StockItem 悲观锁序列化，状态转移在 `with_lock` 内以 `state` guard 幂等。与项目锁定约定一致。
- 模型/服务：`StockReservation` 状态机（RESERVED/COMMITTED/RELEASED/EXPIRED + 时间戳）；`Reserve` 只复用 RESERVED 行；`Release` → RELEASED（不硬删除）；新增 `Commit`（事实确认，不改 count_on_hand）；`Extend` 只续 RESERVED；`ExpireJob` → EXPIRED（不删除）+ 已注册 sidekiq cron（`backend/config/sidekiq_schedule.rb` `stock_reservation_expiry` */5）；`Carts::Complete` finalize 后由 Release 改 Commit（AC-3024）。
- 验证：S2 + 回归 specs 45 例 0 失败；RuboCop 13 文件 0 告警。

---

## S3 实施记录（INV-P3-2，2026-09-05）

- migration `20260905000002_add_snapshot_schema_version_to_commerce_transactions.rb`：`snapshot_schema_version`（int default 1，历史 V1 兼容）。
- `CommerceTransaction`：`CURRENT_SNAPSHOT_SCHEMA_VERSION=2`；`snapshot!` 写 schema_version；`resolved_inventory_demand`（V1 兼容 demand resolver，不写回旧 snapshot）。
- `Stock::InventoryRequirement`（REQUIRED/NOT_REQUIRED policy，不建表）：track && !preorder && 存在非 backorderable 活跃 stock_item → REQUIRED（缺货仍 REQUIRED，由门校验失败）。
- `Transactions::ReserveInventory`（InventoryReservationPort/StockReservationAdapter 首版）：per-participant Reserve（幂等）→ bind `commerce_transaction_id`（只绑 nil 或本 txn 行）→ demand 校验（REQUIRED 行 active RESERVED ≥ qty）；失败返回 `INSUFFICIENT_STOCK`；组合部分失败仅补偿 **created-this-attempt**（before_ids 之外的行 → RELEASED，保留历史）。
- `Transactions::Start`：create/reuse tx（Snapshot V2 冻结）→ ReserveInventory 门 → 才 `PaymentSessions::Start`（AC-3001/3002）；失败不建 session/PSP side effect，tx 保持 created（可安全 Resume/取消）。
- 验证：start/reserve_inventory/on_payment_success/finalize/commerce_transaction specs 36 例 0 失败；RuboCop 0。

---

## S4 实施记录（INV-P3-3，2026-09-05）

- `Transactions::Finalize`：participant 全部成功后、`complete!` 前加交易级 Commit 兜底
  `StockReservations::Commit(transaction:)`（幂等；处理仍 RESERVED 且归属本交易的行 →
  COMMITTED；commit 绝不改 count_on_hand）。participant 级 commit 已由 `Carts::Complete`
  finalize 后调用覆盖（S2）。
- 失败路径修正：failures 非空时先 `transaction.reload` 再 `record_recovery_failure`
  （mark_recovery_required! 需 finalizing 态）；reservation 保留 RESERVED，不 commit、不 release。
- specs：`finalize_inventory_spec`（AC-3011 兜底 commit / AC-3013 失败 recovery_required +
  RESERVED 保留 + 无第二套扣减）；`reserve_strategy_spec` AC-005 断言改 COMMITTED（AC-3024）。
- 验证：15 例 0 失败；RuboCop 0。

---

## S5 实施记录（INV-P3-4，2026-09-05）

- `Orders::Cancel`：在**取消动作前**基于权威支付事实捕获 `release_allowed`（payment_total>0 / 存在 completed payment / 有进行中 payment attempt 的 active txn → 禁止 Release，INV-I09），取消成功后对未支付订单执行 `StockReservations::Release(reason: 'order_canceled')`（RESERVED→RELEASED）。注意 after_cancel 会 void 已入账 payment，故不能在取消后判断（会把 PAID 误判未付）。
- `ReserveInventory`：错误码区分——该 line_item 曾 EXPIRED 且本次无法重预留 → `INVENTORY_CHANGED`（FR-037）；否则 `INSUFFICIENT_STOCK`。
- Resume/重试支付：经 `Transactions::Start` 复用路径（已有 Reserve 门）；每次 Start (re)reserve 会刷新 `expires_at`（TTL 不变量 FR-039，active payment 尝试内 reservation 保持有效）。
- 验证：cancel_inventory + reserve_inventory（INVENTORY_CHANGED/组合补偿）等 —— S2~S5 综合 51 例 0 失败；RuboCop 0。

---

## S6 实施记录（INV-P3-5，2026-09-05）

- 新增 `Transactions::InventoryFactResolver`（只读、零副作用）：per-line_item 覆盖判定（COMMITTED 需该行有 committed 覆盖且订单完成；RESERVED=active reserved 覆盖；RELEASED/EXPIRED=无覆盖的终态；UNRESERVED=无行；PARTIAL/混合 → AMBIGUOUS 折叠）。
- `Transactions::Recover#plan` PAID 分支：参与者未完成且 InventoryFact ∈ {released, expired, ambiguous} → `manual_review`（先 mark_recovery_required if finalizing，再 manual_review!；不猜、不重复 finalize/扣库存）；RESERVED/COMMITTED/NOT_REQUIRED/UNRESERVED 维持既有 finalize/repair 语义（FR-043/044，AC-3027）。
- specs：inventory_fact_resolver（NOT_REQUIRED/RESERVED/COMMITTED/RELEASED/EXPIRED/UNRESERVED/PARTIAL→AMBIGUOUS）+ recover_inventory（PAID+RELEASED→manual_review；PAID+RESERVED→非 manual_review 继续 finalize）。
- 验证：17 例 0 失败；RuboCop 0。

---

## S7 实施记录（INV-P3-6，2026-09-05）

- `Transactions::Start#terminal_transaction_for`：blocker state ∈ {recovery_required, manual_review} → 前端可见 code `INVENTORY_RECOVERY_REQUIRED`（其余终态仍 transaction_not_payable，FR-049）。
- Storefront BFF `src/app/api/checkout/start/route.ts`：catch `@pallastrade/sdk` 的 `PallasTradeError` → 透传 `{ code, message }` + SDK HTTP status（后端 422/409 原样）；非结构化错误保留通用 502/422 回退；新增测试断言 `INSUFFICIENT_STOCK` 422 转发（FR-050：Storefront 只消费 server 权威响应）。
- legacy `stock_reservation_strategy` order/payment 与历史 NULL transaction 兼容不动（FR-047/051）。
- 验证：后端 Start 8 例 + storefront 5 例 0 失败；RuboCop 0。

---

## S8 实施记录（INV-P3-7 核心代码，2026-09-05）

- Admin Transaction show（`pallastrade_admin/app/views/.../transactions/show.html.erb`）新增 Inventory 面板：Inventory Fact（`Transactions::InventoryFactResolver` verdict + reasons）+ Reservation 明细表（state/line_item/stock_item/qty/expires/reserved/committed/released/expired/release_reason；绑定 txn 或参与者订单，只读）。
- `StockReservation`：after_create / after_transition（committed/released/expired）发布 `inventory.reserved|committed|released|expired` 事件（payload：id/order/txn/stock_item/line_item/qty/reason；复用 Events/audit_logs 通道，不新建 Audit Engine）。reserve_started/failed、commit_started/failed 等细化事件与 metrics hook 由事件/结构化日志承载（FR-056 不自建 Prometheus），如需落库 audit_logs 走订阅方（后续可扩展）。
- 验证：模型/服务 20 例 + admin request 6 例 0 失败；RuboCop 0。

---

## 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-05 | 0.1 | INV-P3-0 只读审计：20 产物 + 7 策略冻结提案 | AI |

---

## 审计收口（2026-09-05，bugfix task TASK-20260905143300-08830526 / gate GATE-2026-09-05T14-33-21）

针对实施后审计发现 D1–D7 的落实记录：

- **D2（ExpireJob 竞态）**：`StockReservations::ExpireJob` 增加守护——`joins(:order).where.not(pallastrade_orders: { id: guarded })`，对**已捕获支付/已完成订单**（`payment_total>0 OR completed_at 非空 OR state∈[paid,complete]`）的 RESERVED 行不按 TTL 过期，保留至 canonical Finalize 的 `Commit`/Recover；消除“物理已消费但行停留 EXPIRED（终态不可转 COMMITTED）”竞态（AC-3011/3024）。
- **D3（TTL/3DS 支付窗口，FR-039/AC-3020）**：新增订阅者 `PallasTrade::PaymentSessionReservationSubscriber`（core `app/subscribers/`，注册进 core engine `PallasTrade.subscribers`），监听 `payment_session.processing` → `StockReservations::Extend(order:, transaction: session.commerce_transaction)` 刷新 RESERVED TTL。配合 `Transactions::Start` 每次 (re)reserve 刷新，覆盖 Start 之后 payment confirm 之前的长时间 PSP/3DS 窗口；超出窗口仍由 ExpireJob 兜底过期 → PAID 侧 InventoryFact/Recover manual_review 安全收口。注意：`payment_sessions` 表外键列为 `transaction_id`（非 commerce_transaction_id），订阅者解析事件用 `find_by_param`（无 prefixed_id 列）。
- **D1（FR-053 事件缺口）**：ExpireJob 由 `update_all` 批量改回**逐行走状态机 `expire!`**（with_lock + state guard）→ after_transition 触发 `touch_expired_at` + 发布 `inventory.expired`（原批量路径旁路状态机导致过期审计事件缺失）。expired_at 语义=流转为 EXPIRED 的时点（backfill 时以 expires_at 近似）。
- **D6（RV-I03 exactly-once）**：新增 `spec/services/pallastrade/transactions/recover_inventory_exactly_once_spec.rb`——真实链路（pending standard order + shipment/shipping method → ReserveInventory reserve+bind → bogus 支付完成 + recovery_required → Recover finalize 物理扣减 1 → COMMITTED），断言 StockMovement 恰 1 条、count_on_hand 5→4、COMMITTED 恰 1 行；重复 Recover（not_recoverable）与重复 Finalize（completed 短路）后仍 1 条/1 行。
- **D7（Release PAID guard，AC-3017/INV-I09）**：`StockReservations::Release` 增加服务层防御——涉及订单 paid/completed 时返回 failure `reservation_release_blocked_paid`（可 `allow_paid: true` 显式放行）；不改变现有调用点（Orders::Cancel 已前置 release_allowed、cart_legacy/empty 仅未付）。
- **D5（AC 映射）**：新/改测试补 AC 标注（recover_inventory_exactly_once AC-3009..3015/3024；subscriber AC-3020；release guard AC-3017；expire D1/D2 AC-3011/3018/3024）。全量 28 项标注收口留待后续专项（本文档 S6/S8 记录与 PRD §5 表仍是权威映射源）。
- **D4（文档-代码口径）**：InventoryFactResolver 的 COMMITTED 判定以**代码为准**——verdict=committed 不强制要求订单已完成（`reasons` 携带 order_completed/order_incomplete；只有 committed+reserved 混合才折叠 AMBIGUOUS），避免 PAID+COMMITTED+incomplete 被误送 manual_review。本段即对齐说明。

验证：P3 域回归（stock_reservations/transactions/jobs/models/cancel/complete）96 examples 0 failures + 新增/修改 spec 16 examples 0 failures；RuboCop（lint 范围 7 文件）0；engine.rb 仅注册一行（该文件存量非 lint 范围）。

