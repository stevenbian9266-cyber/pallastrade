# REQ-20260910-promo-batch4b-refund-allocation

| 元数据 | 值 |
|---|---|
| 状态 | done（分摊投影 + 预览端点已实施并验证） |
| 任务类型 | 优化迭代（售后分摊只读投影 + 可退金额预览；不改退款金额语义、不落新表） |
| 关联 PRD | `docs/prd/promotions/PRD-20260910-promotions-promo-batch4b-refund-allocation.md` |
| 关联任务 | TASK-20260910130502-ffc31e08 / GATE-2026-09-10T13-05-11 |
| 前置 | batch4a（成交快照）、REV-P6-3（退款分摊权威冻结）、batch2（投影口径） |
| 风险等级 | standard（requiredEvidence: test / review / knowledge） |

---

## Step 0：跨层搜索（本轮实测，2026-09-10）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App | `backend/app/` | allocation / refund calculation / 分摊 | 无宿主实现（仅 AI 与部署相关） | 不涉及 |
| Core — models | `pallastrade_core/app/models/` | DefaultRefundAmount / ReturnItem / promotion adjustment | `calculator/returns/default_refund_amount.rb`（**退款金额唯一权威**：行加权 pre_tax + 订单级非税按行占比）、`reimbursement_tax_calculator.rb`、`return_item.rb`（`refund_amount_calculator` / `set_default_pre_tax_amount` / `pre_tax_amount`）、`promotion_action.rb`、`adjustment.rb`（`adjustable` 三类：Order / LineItem / Shipment） | ⚠️ 权威齐备但**无促销维度分摊** |
| Core — services | `pallastrade_core/app/services/` | projection / snapshot / allocation | `promotions/projection/discount_projection.rb`（batch2：per-promotion item/order/shipping 三档 breakdown）、`promotions/snapshot/freeze.rb`（batch4a：冻结 total）、`financial_ledger/allocation_integrity.rb`（**组合支付** ORDER_ALLOCATION 恒等式，与促销折扣无关） | ❌ 需新增促销分摊服务（复用以上三者） |
| API | `pallastrade_api/app/{controllers,serializers}` | refunds / returns / calculate | `admin/orders/refunds_controller`（index/show/create，**无 calculate**）；无 return_items/reimbursements 端点 | ❌ 需新增只读预览端点 |
| Admin | `pallastrade_admin/app/views/pallastrade/admin/orders` | promotions panel / refunds | `_promotions.html.erb` + `_order_promotion.html.erb`（batch4a 已改读快照，含锁定徽章） | ⚠️ 需加只读「分摊 / 可退」列 |
| Storefront | `storefront/src/` | refund / return / aftersale | 无退货页面（售后由客服/站外处理） | 不涉及 |
| Platform | `platform/packages/` | allocation | 无相关类型 | ⚠️ 新端点 → schema 需再生 + 平台副本同步 |

### 搜索结论

- 「退款金额」已有唯一权威（REV-P6-3 审计冻结：`DefaultRefundAmount` + `ReimbursementTaxCalculator`）——**本批次禁止重写公式**，只做投影与预览。
- 缺口是三层：**促销维度分摊**（架构 §57）、**可退金额预览面**（架构 §101/§59）、**分摊恒等式测试**（§142 Refund Invariant）。
- 展示数据源全部现成：batch2 投影（三档 breakdown）+ batch4a 快照（冻结 total）+ `ReturnItem` 权威（可退金额）。

---

## Step 1：Skill 文件咨询（真实结论）

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-pricing/SKILL.md` | ✅ 已读（§224-229） | **REFUND_AMOUNT_AUTHORITY = `Calculator::Returns::DefaultRefundAmount`（REUSE，禁止另起 Calculator）**；TAX 策略 = `ReimbursementTaxCalculator`；SHIPPING/PROMOTION 走订单级 non-tax 按行占比。→ 本批次以此为准，只读投影不得改变金额。 |
| `ai/skills/pallastrade-payments/SKILL.md` | ✅ 已读（REV-P6-3 节 + Allocation Integrity 节） | 组合退款 ownership 创建即冻结（split/target_order）；`ORDER_ALLOCATION` 是**组合资金归属**不是 cash；分摊 authority 审计冻结（REUSE）。→ 促销折扣分摊是**另一维度**，需明确命名与边界，勿与组合分摊混淆。 |
| `ai/skills/pallastrade-promotions/SKILL.md` | ✅ 已读（batch2/3a/3b/3c/4a 节） | 投影是唯一展示权威（`SUM==discount_total`）；快照冻结后历史不可漂移；核销台账与 usage_limit 口径。→ 分摊服务必须复用投影/快照，且对冻结订单稳定。 |
| `ai/skills/pallastrade-api-v3/SKILL.md` | ✅ 已读（batch3c 节） | Admin 只读端点范式：`ResourceController`/扁平 serializer、prefixed id、`{ data, meta }`（列表）；**JWT 管理员需显式 `authorize!`**；契约再生 + `schemas:check`。 |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读（订单面板 + 只读运维页范式） | 订单促销面板已读快照；只读区块不得提供写入口；改动面板不涉及导航一致性。 |
| `ai/skills/pallastrade-testing/SKILL.md` | ✅ 已读 | RSpec + FactoryBot；容器内 `DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec`；spec 头标 `# PRD-xxx AC-xxx`。 |
| `ai/skills/pallastrade-data-model/SKILL.md` | ✅ 已读 | 本批次**不新增表/列**（只读投影），`ReturnItem#pre_tax_amount` 已是落库冻结事实。 |

---

## 需求标题

Promotion 批次 4b：AdjustmentAllocation 接退款（PR-P6-1..4）——售后可解释：原金额 / 分摊优惠 / 可退金额，复用 REV-P6 权威、只读、不重跑引擎。

## 需求描述

在 REV-P6-3 已冻结的退款金额权威之上，新增**只读**促销分摊投影 `Promotions::Allocation::AdjustmentAllocation`（架构 §57 语义：per promotion × per line，`allocated_amount` + `allocation_basis`，行级直分/订单级与运费级按行占比），
提供 **Admin API 只读预览** `GET /api/v3/admin/orders/:order_id/refund_calculation`（原金额 / 分摊优惠 / 可退金额，支持 `quantities[...]`），
在 Admin 订单促销面板加只读「分摊 / 可退」列，并以 Invariant 测试锁定「Σ 分摊 == 冻结折扣」「不重跑引擎」「只读无副作用」。

## 影响范围

- **新增**：分摊服务（1 个目录 2 个类）、API controller + serializer + route、4 个 spec。
- **修改**：Admin 订单促销 partial、4 个 Skill、scenarios（GS-087）、契约产物（admin.yaml + platform 副本）。
- **不改**：`DefaultRefundAmount` / `ReimbursementTaxCalculator` / `ReturnItem` / `Refund` / `Reimbursement` / 核销台账 / 订单金额。

## 技术方案

1. **分摊服务**：读 `DiscountProjection.for(order:)`（含 `Line#adjustments` 明细）→ 按 `adjustable_type` 分档：`LineItem` → `line_item`；`Order` → `order_prorata`；`Shipment` → `shipment_prorata`；占比分母 `order.pre_tax_item_amount`。
2. **总额守恒**：per promotion 以（冻结）`order_promotion.total_amount` 或（未冻结）投影 `line.amount` 为锚，逐行 BigDecimal 2 位分摊后余数补到最大行。
3. **可退金额**：内存 `ReturnItem.new(inventory_unit:, return_quantity:)` + `set_default_pre_tax_amount`（**唯一权威**）；无 inventory unit 时降级并标记 `refundable_source`。
4. **API**：`GET /api/v3/admin/orders/:order_id/refund_calculation`（member route），扁平只读响应；JWT 显式 `authorize!(:read, order)`；`current_store.orders` 作用域。
5. **契约**：`typelizer:generate`（serializer typelize）→ `api:docs:schemas` → 平台副本同步 → `api:docs:schemas:check` clean。

## 风险点

| 风险 | 等级 | 缓解 |
|---|---|---|
| 被误读为「新分摊权威」→ 双轨金额 | 中 | 服务命名/注释明确「只读投影，金额权威仍是 `DefaultRefundAmount`」；spec 断言预览值 == `ReturnItem#pre_tax_amount`；pricing Skill 补边界说明 |
| 舍入导致 Σ≠total（恒等式破） | 中 | 余数补最大行的确定性策略 + 不整除场景 spec（3 行分 10 元） |
| 预览端点被当成写路径/触发副作用 | 中 | 纯读实现（无 save/无 enqueue）；AC-006 断言前后行数与金额不变 |
| 组合支付/多店作用域泄漏 | 中 | `current_store.orders` 作用域 + 显式 `authorize!(:read, order)`；跨店 404 spec |
| 无 inventory unit 的行导致 500 | 低 | 降级路径 + `refundable_source` 标记 + spec |
| 契约漂移 | 低 | `api:docs:schemas` 再生 + `generated:check` + 平台副本同步 |

## 决策节点

> ✅ 2026-09-10 用户「继续」（承接上一条消息「说继续我就按 R8 开批次 4b 的 PRD/REQ 并走完整流程」）=
> 授权按 PRD §1.3 选型结论实施批次 4b：**REUSE 现状 proration + 只读投影**（不落新表、不改金额语义）；无额外决策点。

## 验证方案（AC → 命令）

| AC | 命令 |
|---|---|
| AC-001/002/003 | `rspec spec/services/pallastrade/promotions/allocation/adjustment_allocation_spec.rb` |
| AC-002/004 | `rspec spec/models/pallastrade/order_promotion_allocation_invariant_spec.rb` |
| AC-005/006/007 | `rspec spec/requests/api/v3/admin/order_refund_calculation_spec.rb` |
| AC-008 | `rspec spec/requests/pallastrade/admin/order_promotion_allocation_panel_spec.rb` |
| AC-009 | `harness prd verify --id PRD-20260910-promotions-promo-batch4b-refund-allocation` + `harness doc-impact --base origin/dev` |
| 回归 | 见 PRD §7 命令（promotions + admin/API 请求 spec） |
