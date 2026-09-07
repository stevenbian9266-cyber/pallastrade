# PRD-20260907-shipping-rev-p6-5-return-restock-decision-exactly-once-restock-accept

| 元数据 | 值 |
|---|---|
| 状态 | verifying |
| 创建日期 | 2026-09-07 |
| 来源 | 需求：REV-P6-5 Return Restock Decision & Exactly-Once Restock（acceptance 后 restock + Restock Fact + movement DB 幂等） |
| 分类 | shipping（关键词命中；库存/履约域） |
| 关联 Skill | `pallastrade-payments`（REV-P6 系）、`pallastrade-data-model` |
| 关联 REQ | REQ-20260907-rev-p6-5-return-restock-exactly-once.md（实施时回填） |
| 关联 PRD | REV-P6-1~4（done，退款/取消 durable 底座） |
| 需求类型 | 优化迭代（库存资金安全增量，feature gate，risk=critical） |

> 🔁 查重回写：自动查重通过。源：`豆包…/P6 — Refund, Cancellation & Dispute Orchestration.md` §39-42/§60。
> ⚠️ 边界决策：源文档 REV-P6-5=Return Inspection & Restock；REV-P6-2 PRD 曾把「reimbursement 链完整 async 拆链」记入 REV-P6-5 —— 本包**不做资金链拆链**（与 Reverse Recovery/REV-P6-6 一起后置，避免半吊子 async 破坏 Reimbursement 记账），只做 **Restock 决策事实 + exactly-once 底座**。存量已 restock 数据无可证明事实 → 不 backfill（REV-P6-3「不可证明不猜」原则）。

---

## 1. 背景与目标

- **现状（2026-09-08 测绘）**：`ReturnItem#process_inventory_unit!` 在 **receive**（awaiting→received）即按 `should_restock?`（resellable? && track && stock_item && Config）**同步建 `StockMovement(+)`**——先于 acceptance 决策。坏品/需人工判断（`manual_intervention_required`）的退货在 receive 已被 restock（源 §39/§40 语义不满足）；且 restock 无持久化事实、无 DB 幂等兜底（`return_items.inventory_unit_id`、`stock_movements.originator` 均非唯一；originator=RA 一对多不可作键）。退货/restock 域无直接 model spec。
- **目标**：
  1. restock 决策移到 **acceptance（accepted）** 后；rejected/manual 未决不 restock（修复坏品提前入库）。
  2. 引入 **Restock Fact**（只读 resolver，基于 ReturnItem/InventoryUnit/StockMovement 证据派生，不猜不存）供 REV-P6-6 恢复消费。
  3. **exactly-once**：`stock_movements.return_item_id`（可空）+ partial unique（not null）DB 兜底；restock 重试/重复（含并发）幂等跳过。
  4. REUSE：不建第二套 Restock；仍走 `StockMovement` 唯一写入通道（after_create adjust_count_on_hand）。
- **成功指标**：坏品/manual 未决不再提前 restock；同一 return_item 至多一条正向 movement（DB 保证）；自动可售退货（receive→auto accept）行为不变；新增核心域 model spec；P0-P5 + backend-rspec 全量绿。

## 2. 用户故事 / 场景

- 作为 **退货处理员**，接收一件可售退货 → 自动 accept → 立即 restock（与旧行为一致）。
- 作为 **退货处理员**，接收一件损坏/需人工的退货（manual_intervention_required）→ **不**自动 restock；仅当手动 accept 后才 restock；若 reject → 永不 restock。
- 作为 **系统**，restock 写入重试/重复（并发双 CR、超时重试）→ 不产生第二次 `StockMovement(+)`。
- 作为 **恢复器（REV-P6-6）**，可查询某 return_item/CR 的 restock 事实（RESTOCKED/NOT_REQUIRED/NOT_RESTOCKABLE/PENDING）以收敛。

## 3. 功能需求（FR）

- **FR-R65-101（决策时机）**：`ReturnItem` restock 触发从 `reception_status→received`（`process_inventory_unit!`）移至 `acceptance_status→accepted`（新 `after_transition to: :accepted` 回调 `restock_if_needed`）。`process_inventory_unit!` 仅保留 `inventory_unit.return!`。rejected/given/manual 未决不 restock。自动 attempt_accept（eligible→accepted）与手动 accept 都覆盖。
- **FR-R65-102（exactly-once）**：`stock_movements.return_item_id`（可空 belongs_to）+ partial unique index（`return_item_id IS NOT NULL`）。`restock_if_needed` 建 movement 带 `return_item_id: id`；`ActiveRecord::RecordNotUnique` → 幂等跳过（已 restock）。
- **FR-R65-103（Restock Fact）**：新增只读 resolver（`PallasTrade::Returns::RestockFact.resolve(return_item)` / `.resolve_for_customer_return`），输出 `RESTOCKED`（accepted && should_restock? && 存在 return_item_id movement）/ `NOT_RESTOCKABLE`（accepted && !should_restock?）/ `NOT_REQUIRED`（未 accepted 终态：rejected/given/cancelled）/ `PENDING`（未决）/ `AMBIGUOUS`（accepted && should_restock? 但无 movement——异常，供 REV-P6-6 收敛）。证据来自 ReturnItem/InventoryUnit/StockMovement，不持久化（不猜）。
- **FR-R65-104（REUSE/兼容）**：通道仍 `StockMovement.create!`（after_create 唯一 adjust_count_on_hand）；Shipment cancel / OrderInventory 路径不改；存量不做数据 backfill；RA 一对多 originator 保留（幂等由 return_item_id 承担）。

## 4. 非功能需求（NFR）

- 迁移：仅 backend/db/migrate 新增列 + partial unique index；无数据迁移。
- 幂等/并发：DB 层权威；应用层 rescue 捕获。
- 行为兼容：自动可售退货 restock 结果不变；manual 未决语义是修复（不再提前 restock）。
- 回归：parent_order_returns（admin RA 流程）、stock_reservations、recover_inventory_exactly_once、reimbursement 链、P0-P5。

## 5. 验收标准（AC）

| AC | 源 | 验收条件 | 覆盖 FR |
|---|---|---|---|
| AC-R65-01 | §39 | 可售退货 receive→auto accept→restock（与旧一致；movement 带 return_item_id） | FR-R65-101/102 |
| AC-R65-02 | §39 | manual_intervention_required（损坏）receive 后**不** restock；手动 accept 后 restock；reject 后永不 restock | FR-R65-101 |
| AC-R65-03 | §42 | 同一 return_item 重复 restock（重试/再 accept）→ 仅 1 条正向 movement（DB partial unique 幂等） | FR-R65-102 |
| AC-R65-04 | §41 | RestockFact 对 5 态（RESTOCKED/NOT_REQUIRED/NOT_RESTOCKABLE/PENDING/AMBIGUOUS）可判定且只读不写 | FR-R65-103 |
| AC-R65-05 | — | 既有 admin RA/退货流程（parent_order_returns）+ stock/reimbursement 回归绿；不建第二套 restock | FR-R65-104 |
| AC-R65-06 | AC-6030~35 | P0-P5 baseline + backend-rspec 全量绿 | 全部 |

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 关键词 | 找到 | 满足 |
|---|---|---|---|---|
| App | backend/app/ | return/restock | 无 override | 否 |
| Core | .../pallastrade_core/app/ | CustomerReturn/ReturnItem/StockMovement | return_item.rb（process_inventory_unit! restock=改点）、customer_return.rb、stock_movement.rb、stock_location.rb、order_inventory.rb、orders/cancel.rb（release） | 部分——本包补 |
| API | pallastrade_api | returns | 无 controller/route（仅 serializer） | 否（本包不加 API） |
| Admin | pallastrade_admin | customer_returns | orders/customer_returns_controller.rb（CR create→receive）、return_items#update（accept/reject） | 触发点（无需改） |
| Storefront | storefront/src/ | return | 无 | 否 |
| Platform | platform/packages | return | 无 | 否 |

**结论**：restock 唯一漏洞集中在 core ReturnItem receive 语义 + DB 幂等缺失；本包在 core 内闭环，Admin 触发点不变，无新 API/无新通道。

## 7. 技术影响

- Core：`models/pallastrade/return_item.rb`（接受后 restock + 幂等）、`models/pallastrade/stock_movement.rb`（belongs_to :return_item optional）、`models/pallastrade/return_item.rb`（has_many restock movements，如需）、新增 `services/pallastrade/returns/restock_fact.rb`（或等价目录）。
- 迁移：`backend/db/migrate/20260908xxxxxx_add_return_item_to_stock_movements.rb`（列 + partial unique）+ schema.rb。
- 测试：新增 return_item restock 决策/exactly-once/resolver spec；parent_order_returns 等回归。
- 文档：payments skill（REV-P6-5 节）、data-model skill（如需）、scenarios GS-064、PRD/REQ/README。

**风险**：restock 时机从 receive→accepted 的行为变化面（坏品不再提前入库=修复）；用回归 + 新 spec 兜底。无 migration 数据回填；回滚=git revert（迁移 down 提供）。

## 8. 测试计划

**新增**
- `backend/spec/models/pallastrade/return_item_restock_spec.rb`：AC-R65-01~03（auto accept restock / manual 不提前 restock / accept 后 restock / reject 不 restock / 重复幂等 exactly-once）。
- `backend/spec/services/pallastrade/returns/restock_fact_spec.rb`：AC-R65-04 五态。
**更新/回归**：`parent_order_returns`、stock_reservations、recover_inventory_exactly_once、reimbursement（original_payment_child）、full suite。
每 spec 头标注 `# PRD-REV-P6-5 AC-R65-xx`。

## 9. 文档同步清单

- [x] PRD/REQ 已建
- [ ] Skill：`pallastrade-payments`（REV-P6-5 节）+ 场景 GS-064 + README 索引 + doc-impact

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-07 | 0.1 | 初稿（依据源 §39-42/§60 + 2026-09-08 退货/restock 测绘） | AI |
| 2026-09-08 | 0.2 | 实施：ReturnItem restock 移至 acceptance（restock_if_needed + public restock_eligible?）；process_inventory_unit! 只保留 inventory return；stock_movements.return_item_id + partial unique（migration 20260908000000）；Returns::RestockFact 五态 resolver；新增 spec 9 例绿（return_item_restock + restock_fact）；回归 151（ai_models 为测试库污染，重置后单独绿）；payments skill REV-P6-5 + GS-064 + REQ + README。 | AI |
