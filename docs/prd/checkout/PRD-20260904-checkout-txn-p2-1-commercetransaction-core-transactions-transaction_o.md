# PRD-20260904-checkout-txn-p2-1-commercetransaction-core

| 元数据 | 值 |
|---|---|
| 状态 | approved |
| 创建日期 | 2026-09-04 |
| 来源 | `豆包梳理业务需求/P2 — Commerce Transaction Orchestration & Recovery.md`（TXN-P2 程序，用户定稿）+ `docs/research/RESEARCH-20260904-txn-p2-0-commerce-transaction-semantic-audit.md`（TXN-P2-0 审计，用户「实施」批准） |
| 分类 | checkout（关键词命中；harness prd new 自动判定） |
| 关联 Skill | pallastrade-data-model、pallastrade-payments、pallastrade-checkout |
| 关联 REQ | REQ-20260904-txn-p2-1.md（实施时回填） |
| 关联 PRD | N/A（P2 程序首个子包 PRD） |
| 需求类型 | 新功能（Transaction Core 数据层） |

> 本包范围锁定（TXN-P2-0 §6.14）：**只实现 `CommerceTransaction`/`TransactionOrder` 数据模型 + 状态机 + immutable snapshot + 审计事件**。**不接支付流 / 不新增 API / 不接 storefront**（TXN-P2-2+）。

## 1. 背景与目标

- **一句话需求原文**：新增 CommerceTransaction 编排数据层（P2-1），在 P0 Payment 与 P1 Checkout 之间提供 durable 交易上下文。
- **背景**：当前「支付成功→订单完成」无 durable orchestration 上下文（TXN-P2-0 审计 §1 实证：全仓无 Transaction 实体）；单订单 recovery 缺口与组合 standard 成员缺陷（已修复于 `64f92b5`）都源于缺少「交易级生命周期」。
- **目标**：建立 `transactions`（txn_）+ `transaction_orders` 数据模型与状态机，能冻结交易快照、记录审计事件，为 TXN-P2-2（Start/Resume）与 TXN-P2-4（Recovery）提供底座。
- **成功指标**：模型/状态机/snapshot 规格测试全绿；不改任何既有支付/checkout 行为（回归绿）；不产生任何 API/前端行为变化。

## 2. 用户故事 / 场景

- 作为系统，我希望一笔商业交易有持久化生命周期记录，以便支付确认后能定位「这笔交易依据什么报价、涉及哪些订单、处于什么状态」。
- 场景：
  - 正常：普通订单交易 created → … → completed（全生命周期由后续包驱动）。
  - 边界：一个 Transaction 关联 1..N 个 Order（`transaction_orders`）；一个 Order 可（时间上）属于多个 Transaction。
  - 异常：模型层不得出现「两个 active 交易写同一 primary order」的并发态（由唯一索引/校验在 TXN-P2-2 收口；本包先提供约束面）。

## 3. 功能需求（FR）

- FR-101：`PallasTrade::CommerceTransaction`（表 `pallastrade_commerce_transactions`，前缀 `txn_`）——字段按 TXN-P2-0 §6.11（state/purpose/checkout_version/price_version/snapshot_fingerprint/snapshot_data jsonb/amount/currency/payment_combination_id 可空/时间戳/recovery_attempts/last_error_*）。
- FR-102：状态机 `created → payment_pending → payment_confirmed → finalizing → completed`；`created|payment_pending → canceled`；`payment_confirmed|finalizing → recovery_required`；`recovery_required → manual_review`。禁止 `payment_confirmed → payment_pending`（INV-02/03）。非法迁移抛业务错误（参考 `PaymentCombination::InvalidTransitionError` 模式）。
- FR-103：`PallasTrade::TransactionOrder`（表 `pallastrade_transaction_orders`）：`transaction_id/order_id/role(primary|participant)/amount_snapshot/completion_status(pending|completed|failed)`；唯一索引 `[transaction_id, order_id]`；索引 `order_id`。
- FR-104：交易启动语义——`CommerceTransaction` 有 `purpose`（purchase|balance_collection|combined_payment 首版最小集，枚举校验）。
- FR-105：snapshot 能力——提供 `CommerceTransaction#snapshot!` 写入 immutable `snapshot_data`（JSONB）+ `checkout_version/price_version/snapshot_fingerprint/amount/currency`（供 TXN-P2-2 Start 冻结使用；本包只提供写入/读取原语 + 校验「已冻结不可覆写」）。
- FR-106：审计事件——交易生命周期经既有 `AuditLog`/`publishes_lifecycle_events` 模式发布（transaction.created/…/recovery_required/…/canceled），不新建审计引擎（TXN-P2-0 §6.11）。
- FR-107：约束面——不引入「同一 order 并发两个 active transaction」强制（TXN-P2-2 用订单锁实现）；本包在 TransactionOrder 层提供 association 查询辅助（`active_for_order(order, purpose:)` 供后续复用）。

## 4. 非功能需求（NFR）

- 兼容：不修改既有 Order/Payment/Session/Combination 表结构与行为；新表全新增。
- 幂等语义面：状态迁移与 snapshot 写入必须在事务内原子（`transaction + with_lock` 面由 TXN-P2-2 编排，模型保证单写路径）。
- 可审计：所有状态迁移写 `state_changes`/审计事件（对齐 PaymentSession 模式）。
- 数据规模：交易量级与 Order 同量级，索引足够，无特殊性能要求。

## 5. 验收标准（AC，与测试一一映射）

- AC-201 ← FR-101/102：创建交易默认 `created`；合法迁移链可达 `completed`；`payment_confirmed → payment_pending` 抛业务错误。
- AC-202 ← FR-102：`payment_confirmed/finalizing → recovery_required` 合法；`recovery_required → manual_review` 合法。
- AC-203 ← FR-103：Transaction 可挂 1..N TransactionOrder（role/amount_snapshot/completion_status）；唯一索引阻止同单重复挂载。
- AC-204 ← FR-104：purpose 枚举校验（purchase/balance_collection/combined_payment）。
- AC-205 ← FR-105：`snapshot!` 写入后不可覆写（再次调用抛错）；快照含版本/指纹/金额/currency。
- AC-206 ← FR-106：状态迁移产生审计事件/state_changes（created/completed/recovery_required/canceled 抽查）。
- AC-207 ← FR-107：`active_for_order` 查询按 order+purpose+active 状态返回最近活跃交易（无则 nil）。
- AC-208：既有支付/checkout/组合 spec 回归全绿（p0-payment-rspec 等）；无 API/前端行为变化。
- AC-209：RuboCop 0；migration 可 up/down。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | transaction/CommerceTransaction | 仅 serializer TS 类型 + Devise | 否（需新建 core） |
| Core | `pallastrade_gems/pallastrade_core/app/` | CommerceTransaction/Transactions | 无；`transaction_id` 仅 PSP/Refund | 否（需新建模型） |
| API | `pallastrade_gems/pallastrade_api/app/` | transactions | 无 transactions 资源 | 否（本包不建 API） |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | transaction | 无交易管理 | 否（TXN-P2-7） |
| Storefront | `storefront/src/` | transaction | 无 | 否（TXN-P2-6） |
| Platform | `platform/packages/` | transactions | 无 SDK 方法 | 否（TXN-P2-6） |

**结论**：全层无 Transaction 实体 → 在 core 新增模型（参考 PaymentSession/PaymentCombination 模式）；防重复判定成立。

## 7. 技术影响

- 新增表：`pallastrade_commerce_transactions`、`pallastrade_transaction_orders`（backend/db/migrate 新 migration，绝不动旧 migration）。
- 新增模型：`pallastrade_core/app/models/pallastrade/commerce_transaction.rb`、`transaction_order.rb`（含 state machine、has_prefix_id、SingleStoreResource、publishes_lifecycle_events 对齐既有模式）。
- 模型目录需确认是否含 `order/`、`checkout.rb` 之类子目录惯例——按 `payment_combination.rb` 同级。
- 影响面：纯增量；不改 Order/Payment/PaymentSession/PaymentCombination；`harness affected` 预期仅 core+spec。

## 8. 测试计划

- 新增：
  - `backend/spec/models/pallastrade/commerce_transaction_spec.rb`（AC-201/202/204/206 状态机+枚举+审计）
  - `backend/spec/models/pallastrade/transaction_order_spec.rb`（AC-203 唯一索引/role）
  - `backend/spec/models/pallastrade/commerce_transaction_snapshot_spec.rb`（AC-205）
  - `backend/spec/services/...`（如建模 `CommerceTransaction#snapshot!` 为服务则置于 services）
- 回归：p0-payment-rspec / chk-p1-5-rspec（既有支付+checkout 不破坏，AC-208）。
- 每个 spec 头部标注 `# PRD-20260904-checkout-txn-p2-1 AC-xxx`。

## 9. 文档同步清单（知识同步门）

- [x] TXN-P2-0 审计 `docs/research/RESEARCH-20260904-...`（更新 §8 Entry Gate 已满足 + 本包落地状态）
- [ ] `ai/skills/pallastrade-data-model/SKILL.md`（新增 Transaction/TransactionOrder 模型）
- [ ] `ai/skills/pallastrade-checkout/SKILL.md`（changelog：TXN-P2-1 数据层）
- [ ] `docs/prd/README.md` 索引（本 PRD）
- [ ] `harness/requirements/REQ-20260904-txn-p2-1.md`
- [ ] 无 API 变更 → 不触碰 store/admin.yaml（本包）

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-04 | 0.1 | 初稿（依据 TXN-P2-0 审计 §5/§6.11 冻结提案） | AI |
