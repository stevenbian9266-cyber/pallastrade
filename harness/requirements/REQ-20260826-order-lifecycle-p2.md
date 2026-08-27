# REQ-20260826-order-lifecycle-p2

> 关联 PRD：`docs/prd/checkout/PRD-20260826-checkout-实施-p2-统一拆单引擎-orders-splitter-策略分组-调整分摊-幂等.md`
> 上游方案：`docs/research/RESEARCH-20260826-order-lifecycle-upgrade-plan.md`（§P2）

---

## Step 0：跨层搜索（6 层）

| 层 | 搜索路径 | 搜索关键词 | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App | `backend/app/` | split / 拆单 | 无 | ⛔ 需新建（core） |
| Core — models | `pallastrade_core/app/models/` | class Splitter / def split | 仅 `stock/splitter/*`（拆 shipment） | ⛔ 需新建 |
| Core — services | `pallastrade_core/app/services/orders/` | splitter / split | 无（上次实现已回滚） | ⛔ 需新建 |
| API | `pallastrade_api/app/controllers/` | split | `fulfillments_controller#split`（shipment 级） | ⛔ P2 不涉及 |
| Admin | `pallastrade_admin/app/controllers/` | split | `shipments_controller#split`（shipment） | ⛔ P2 不涉及 |
| Storefront | `storefront/src/` | splitOrder / split | 无 | ⛔ P2 不涉及 |
| Platform | `platform/packages/` | split / Splitter | 无 | ⛔ P2 不涉及 |

### 搜索结论

无订单级拆单实现；现有 `split` 均属 shipment 级（发货单拆分）。`Orders::Splitter` 全新创建，无重复风险。

---

## Step 1：Skill 文件咨询

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `pallastrade-customization` | ✅ 已读（P1） | 决策树：业务逻辑放服务对象；`PallasTrade.dependencies` 可换服务实现 |
| `pallastrade-checkout` | ✅ 已读 | 订单状态机 `cart→address→delivery→payment→confirm→complete`；`order.next!` 推进；`state` vs `status` 双列 |
| `pallastrade-data-model` | ✅ 已读（P1） | Order 父子模型（P1 已建 parent/children/split_from）；Adjustment polymorphic 三级（Order/LineItem/Shipment） |
| `pallastrade-payments` | ✅ 已读（P1） | PaymentSplit 分摊记录（P1 已建）；`Payment#max_amount` 约束 |
| `pallastrade-testing` | ✅ 已读（P1） | RSpec + FactoryBot；`create(:order)` 等核心 factories |

---

## 需求标题

订单生命周期升级 P2：统一拆单引擎（`Orders::Splitter` + 策略分组 + 调整项分摊 + 已付分摊 + 幂等）。

## 任务类型

新功能（能力层服务，默认不接入任何流程）

## 需求描述

实现把一笔订单按分组拆成多笔子订单的统一引擎：行项目迁移到子订单（挂同一父订单）、order 级促销调整按行项目金额比例分摊、税额与金额重算、已付金额按比例写 `PaymentSplit`、支持按仓库地址/按店铺两种策略分组、幂等且发布 `order.splitted` 事件。P2 仅提供能力，不接入 checkout/API/前端。

## 影响范围（harness affected）

仅 `pallastrade_core`：新增 `services/pallastrade/orders/splitter.rb` + `split_strategies/*`；`order.rb` 事件（如需）。无迁移、无 API、无前端。

## 技术方案（初步）

1. **`Orders::Splitter#split(order:, groups:, options:)`**（事务内）：
   - 校验：源订单可拆（非取消/非空/行项目不跨组/跨店商品可用）
   - 为每个 group 创建子订单（复制属性 + `parent_id`=源（或指定 parent）+ `split_from_id`=源）
   - 迁移行项目：`line_item.update!(order: child)` + 同步其 `Adjustment#order_id`
   - order 级非税 eligible 调整按行项目金额比例分摊创建到子订单
   - 子订单 `create_tax_charge!` + `OrderUpdater#update`
   - 已付金额：按行项目金额比例创建 `PaymentSplit`
   - 源订单 `OrderUpdater#update`（剩余行项目）
   - 发布 `order.splitted` 事件
2. **策略分组**：`SplitStrategies::ByStockLocation`（按商品仓库地址，复用 `Stock::Coordinator` 分组）、`ByStore`（按店铺）；`PallasTrade.orders_split_strategies` 注册点。

## 风险点

| 风险 | 缓解 |
|---|---|
| 金额分摊误差 | 行项目金额比例分摊 + 尾差归到最后组 + 总额守恒断言 |
| 调整项重复/丢失 | 只迁移 line_item 级（随行）；order 级按比例重建，不移动原记录 |
| 跨店商品不可用 | 前置校验（publication/价格/税/配送），失败整体回滚 |
| 幂等 | `split_from_id` + 源订单状态守卫 + 行项目唯一性校验 |
| 并发 | 源订单 `with_lock` |
