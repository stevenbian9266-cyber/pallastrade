# REQ-20260907-rev-p6-5-return-restock-exactly-once — Return Restock Decision & Exactly-Once Restock

> 关联 PRD：`docs/prd/shipping/PRD-20260907-shipping-rev-p6-5-return-restock-decision-exactly-once-restock-accept.md`（approved）
> 源规格：`豆包…/P6 — Refund, Cancellation & Dispute Orchestration.md`（§39-42/§60）
> Task：`TASK-20260907220220-da45a720`；Gate：`GATE-2026-09-07T22-02-28`
> 分支：dev @ 52e4569

## Step 0 跨层搜索（节选结论）
| 层 | 结论 |
|---|---|
| App | 无 override |
| Core | return_item.rb `process_inventory_unit!`（receive 即 restock=改点）、customer_return.rb、stock_movement.rb、stock_location.rb；新增 returns/restock_fact.rb |
| API | 无 returns controller（本包不加 API） |
| Admin | customer_returns#create / return_items#update 为触发点（不改） |
| Storefront/Platform | 无 |

## 需求描述
1. ReturnItem restock 触发从 receive 移到 acceptance（accepted）后（FR-R65-101）；rejected/manual 未决不 restock（修复坏品提前入库）。
2. `stock_movements.return_item_id`（可空）+ partial unique → exactly-once；restock 幂等跳过（FR-R65-102）。
3. `Returns::RestockFact` 只读 resolver 五态（RESTOCKED/NOT_REQUIRED/NOT_RESTOCKABLE/PENDING/AMBIGUOUS）（FR-R65-103，REV-P6-6 消费）。
4. REUSE：通道仍 StockMovement after_create；Shipment cancel/OrderInventory 不改；无数据 backfill（不猜）；reimbursement async 拆链后置 REV-P6-6/6-8（边界）。

## 影响范围
- Core：return_item.rb（restock_if_needed + public restock_eligible?）、stock_movement.rb（belongs_to return_item）、新 returns/restock_fact.rb。
- 迁移：backend/db/migrate/20260908000000_add_return_item_to_pallastrade_stock_movements.rb + schema.rb。
- 测试：return_item_restock_spec.rb、returns/restock_fact_spec.rb（9 例绿）。
- 文档：payments skill（REV-P6-5）、scenarios GS-064、PRD/REQ/README。

## 决策节点（用户 2026-09-08「继续，自主决定，最优解优先」授权）
1. 决策时机移至 acceptance；2. return_item_id DB 幂等；3. resolver 只读派生不持久化（存量不猜）；4. reimbursement async 拆链与 Reverse Recovery（REV-P6-6）同包后置。

## 阶段③：验证表
| 改动 | 最低验证 | 结果 | 状态 |
|---|---|---|---|
| Core + migration | return_item_restock + restock_fact spec（9 绿） | 9 examples, 0 failures | ✅ |
| 回归 | returns/admin/stock/reimbursement/recover/refunds（151 例） | 150 绿（ai_models 测试库污染，重置后单独绿） | ✅ |
| 全量 | backend-rspec verifier | （提交前/后各一次） | ⬜ |
