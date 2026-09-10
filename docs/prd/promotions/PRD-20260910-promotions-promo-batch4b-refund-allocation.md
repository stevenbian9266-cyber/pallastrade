# PRD-20260910-promotions-promo-batch4b-refund-allocation

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-10 |
| 来源 | `promotion模块架构-任务拆解.md` 批次 4 → Phase 6（PR-P6-1..4，含前置决策 PR-A0-5）；架构 §57 AdjustmentAllocation、§59 Refund Amount、§101 Refund Promotion Admin Panel、§142 Refund Invariant |
| 分类 | promotions |
| 关联 Skill | pallastrade-promotions、pallastrade-pricing（分摊权威）、pallastrade-payments（退款链路）、pallastrade-api-v3、pallastrade-admin、pallastrade-data-model、pallastrade-testing |
| 关联 REQ | REQ-20260910-promo-batch4b-refund-allocation.md（实施时回填） |
| 关联 PRD | batch2（DiscountProjection）、batch3a/3b（核销台账）、batch4a（成交快照，本批次的金额来源）、REV-P6-3（退款分摊权威） |
| 需求类型 | 优化迭代（售后分摊可解释 + 可退金额只读预览；**不改退款金额语义**） |

> **口径原则**：本批次**不新增第三套分摊、不落新表、不改退款金额计算**。
> 退款金额唯一权威仍是 `Calculator::Returns::DefaultRefundAmount`（REV-P6-3 审计冻结）；
> 本批次提供的是「这笔订单的促销折扣如何分摊到行 / 可退多少」的**只读投影**与 **Admin 只读预览端点**。

---

## 1. PR-P6-1：现状盘点（REV-P6 已建能力，2026-09-10 实测）

### 1.1 退款金额（分摊）现状

| 环节 | 现状实现 | 结论 |
|---|---|---|
| 退款金额权威 | `PallasTrade::Calculator::Returns::DefaultRefundAmount#compute(return_item)`（`return_item.rb:26` 绑定） = `行加权 pre_tax 金额 + 订单级非税调整 × 行占比`（`pre_tax_amount / order.pre_tax_item_amount`） | **已是"退款时 prorate"模型**，且被 REV-P6-3 审计冻结为 `REFUND_AMOUNT_AUTHORITY`（`pallastrade-pricing` §224-229：**REUSE，禁止另起 Calculator**） |
| 行级促销 | 已净额体现在 `line_item.pre_tax_amount`（`return_item.rb:161` `total = pre_tax + included_tax + additional_tax`） | 无需再分摊 |
| 订单级促销 / 运费 | 通过 `order.adjustments.eligible.non_tax` 按行占比分摊（**含订单级 promotion + shipping**） | 已是架构 §59「Allocated coupon」语义 |
| 税额 | `ReimbursementTaxCalculator`（`pre_tax / refunded` 百分比） | 已冻结策略 |
| 落库字段 | `ReturnItem#pre_tax_amount`（写入即冻结；`ReturnItem` 无促销维度字段） | **无促销维度分摊事实** |

### 1.2 缺口（本批次要补的）

1. **无促销维度分摊**：无法回答「这笔退款里有 9 元是 WELCOME20 的折扣、属于哪一行」——架构 §57 `AdjustmentAllocation` 缺失（order / order_promotion / adjustment / line_item / allocated_amount / allocation_basis）。
2. **无可退金额预览面**：Admin/Store 在发起退货前看不到「原金额 / 分摊优惠 / 可退金额」三件套（架构 §101 Refund Promotion Admin Panel 要求）；现有只有 `admin/orders/:id/refunds`（创建后才知道金额）。
3. **无分摊恒等式测试**：batch4a 冻结了 `order_promotions.total_amount`，但没有测试断言「**分摊之和 == 冻结折扣**」。
4. **无"不重跑引擎"的回归证明**：退款链路是否依赖当前促销定义，缺少显式约束测试。

### 1.3 选型结论（PR-A0-5 / D1）

**REUSE 现状（退款时 prorate）+ 只读投影**，理由：

- REV-P6-3 已把 proration 冻结为唯一权威，另起「成交预分摊」表会形成**第三套分摊**（PR-A0-5 明令避免）；
- 预分摊表需要随退货/部分退/组合拆单持续维护，成本高且与 `ReturnItem#pre_tax_amount` 存在双事实风险；
- 只读投影可立即满足「可解释 + 可预览 + 可断言」，且**零资金风险**（不写库、不跑引擎）。

> 命名沿用架构 §57 的 `AdjustmentAllocation`：它是**值对象/服务**（transient），不是表。

---

## 2. 功能需求（FR）

- **FR-001 分摊服务（PR-P6-2）**：新增 `PallasTrade::Promotions::Allocation::AdjustmentAllocation`
  - 入口 `AdjustmentAllocation.for(order:)`，返回只读结果对象：
    - `#lines` → `[Line(order_promotion_id:, promotion_id:, line_item_id:, allocated_amount:, allocation_basis:)]`
    - `#promotion_totals` → `[{ promotion_id:, order_promotion_id:, original_amount:, allocated_amount:, basis_totals: { line_item:, order_prorata:, shipment_prorata: } }]`
    - `#balanced?`、`#total_allocated`
  - 分摊基（`allocation_basis`）三类：`line_item`（行级促销调整直接归行）、`order_prorata`（订单级促销调整按行 `pre_tax_amount / order.pre_tax_item_amount` 占比）、`shipment_prorata`（运费级促销调整同按行占比）。
  - 金额总额来源**冻结优先**：`order_promotions.total_amount`（batch4a 快照）→ 未冻结时退回 `DiscountProjection::Line#amount`；**不重跑 Promotion Engine、不写库**。
  - 只统计 `source_type = PallasTrade::PromotionAction AND eligible = true` 的调整（batch1/batch2 口径）。
- **FR-002 金额权威（PR-P6-3，REUSE）**：可退金额一律经 `ReturnItem#refund_amount_calculator`（`DefaultRefundAmount`）计算——服务内以**内存 ReturnItem**（`PallasTrade::ReturnItem.new(inventory_unit:, return_quantity:)` + `set_default_pre_tax_amount`）调用，**不复制公式**。
- **FR-003 售后金额预览（PR-P6-3）**：Admin API 只读端点 `GET /api/v3/admin/orders/:order_id/refund_calculation`
  - 返回（Admin 只读扁平风格，同 batch3c）：`{ data: { order_id, currency, line_items: [...], promotions: [...], totals: {...} } }`
    - `line_items[]`：`line_item_id`、`quantity`、`return_quantity`、`original_amount`（`line_item.amount`，折前）、`allocated_discount`（促销分摊绝对值）、`allocated_discount_breakdown`（basis → amount）、`refundable_amount`（权威计算）、`pre_tax_amount`
    - `promotions[]`：`promotion_id`、`order_promotion_id`、`name`、`code`（快照优先）、`original_discount`、`allocated_discount`
    - `totals`：`original_amount`、`allocated_discount`、`refundable_amount`、`currency`
  - 可选 query：`quantities[<line_item_id>] = n`（默认每行全量 `line_item.quantity`）；非法/超量值 → 422 `validation_error`。
  - 只读、幂等、无副作用；**不创建 Refund/ReturnItem、不改订单**。
- **FR-004 鉴权与作用域（PR-P6-3）**：JWT 管理员须显式 `authorize!(:read, order)`（read 无全局钩子）；订单作用域 = `current_store.orders`；跨店订单 → 404；无权限 → 403。
- **FR-005 Admin 只读展示（PR-P6-3，架构 §101）**：订单页促销面板对**已冻结**促销行显示「分摊 / 可退」列（数据来自 FR-001/002，只读，无写入口）。
- **FR-006 Invariant 测试（PR-P6-4）**：
  - `Σ allocated_amount (per promotion) == order_promotion.total_amount`（冻结）/ `projection line amount`（未冻结）；
  - 舍入确定性：`Σ 行分摊 == total`（BigDecimal 2 位，余数补到金额最大的行）；
  - 不重跑引擎：冻结订单在「促销改名 / 改 kind / 改码 / 删动作 / 改规则」后，分摊与可退金额逐字段不变。
- **FR-007 文档同步**：`pallastrade-promotions`（分摊节）、`pallastrade-pricing`（分摊 ADR 指向）、`pallastrade-api-v3`（新只读端点）、`pallastrade-admin`（面板列）、`scenarios.json` GS-087、PRD 索引。

---

## 3. 业务规则与边界

| # | 规则 | 说明 |
|---|---|---|
| R1 | 只减不增 | `allocated_amount` 为促销折扣的**绝对值**（源调整为负数 → 取绝对）；非负 |
| R2 | 口径 | 只统计 eligible + `PromotionAction` 调整；store credit / gift card / 税调整**不参与**促销分摊（架构 §58/§59） |
| R3 | 占比分母 | 行占比分母 = `order.pre_tax_item_amount`；为 0（全赠品/异常）时全部落到最大行，保证 Σ 守恒 |
| R4 | 舍入 | BigDecimal 2 位；先按占比计算，余数补到 `total` 对应促销的**最大分摊行**（确定性，与行序无关） |
| R5 | 冻结优先 | 冻结订单用快照 total；未冻结（购物车/未回填）用投影 total——两者都与 `discount_total` 口径一致 |
| R6 | 不重跑引擎 | 服务内**不调用** `PromotionHandler` / `OrderUpdater` / 任何促销 eligibility 判定；只读既有调整 |
| R7 | 只读 | 不写任何表；不创建 Refund/ReturnItem（预览用内存对象） |
| R8 | 币种 | 一律订单币种（架构 §58，不做 FX） |
| R9 | 预览数量 | `quantities` 缺省 = 每行全量；`n > quantity` → 422；`n = 0` → 该行 `refundable_amount = 0` 但仍在响应中 |
| R10 | 空态 | 无促销订单：`promotions: []`、`allocated_discount = 0`、`balanced? = true`；无 inventory unit 的行：`refundable_amount` 用权威公式的降级值（`pre_tax_amount` 按行占比）并标记 `refundable_source: 'authority' \| 'fallback'` |

---

## 4. 验收标准（AC，与测试一一映射）

| AC | 对应 | 判定条件 | 映射测试 |
|---|---|---|---|
| AC-001 | FR-001/R1/R2 | 三类 basis 正确：行级调整 → `line_item`；订单级调整 → `order_prorata`；运费级 → `shipment_prorata`；行级金额精确等于该行调整绝对值，占比分摊金额随 `pre_tax_amount` 变化；非 eligible / 非 PromotionAction 调整不参与 | `backend/spec/services/pallastrade/promotions/allocation/adjustment_allocation_spec.rb` |
| AC-002 | FR-006/R4 | **Invariant**：per promotion `Σ allocated_amount == total_amount`（冻结快照）；未冻结订单 == 投影 `line.amount`；不整除金额（如 3 行分 10 元）时余数补到最大行且总和精确相等；行序变化不影响结果 | 同上 + `backend/spec/models/pallastrade/order_promotion_allocation_invariant_spec.rb` |
| AC-003 | R3/R9/R10 | 多促销并存互不串；`pre_tax_item_amount = 0` 不炸且 Σ 守恒；无促销订单返回空集且 `balanced?`；数量 0 / 超量边界 | `adjustment_allocation_spec.rb` |
| AC-004 | FR-006 | 不重跑引擎：冻结订单改促销名/kind/码 + 删动作 + 改规则后，`lines`、`promotion_totals`、可退金额逐字段不变；未冻结购物车仍实时 | `order_promotion_allocation_invariant_spec.rb` |
| AC-005 | FR-002/003 | 预览端点返回三件套（原金额/分摊优惠/可退金额），默认全量；`quantities[...]` 生效；`refundable_amount` 等于 `ReturnItem` 权威计算值（同一输入下与 `ReturnItem#pre_tax_amount` 一致） | `backend/spec/requests/api/v3/admin/order_refund_calculation_spec.rb` |
| AC-006 | FR-003/R7 | 端点只读：请求前后 `Refund`/`ReturnItem`/`order_promotions` 行数与金额不变；重复请求结果一致 | 同上 |
| AC-007 | FR-004 | 鉴权：无 `read` 权限 403；未认证 401；跨店订单 404；非法 `quantities` → 422 | 同上 |
| AC-008 | FR-005 | Admin 订单页对冻结促销显示分摊/可退（渲染断言），未冻结订单回退实时；页面无写入口 | `backend/spec/requests/pallastrade/admin/order_promotion_allocation_panel_spec.rb` |

验证补充（非 AC，不参与 `prd verify` 的 AC↔测试映射）：

| 编号 | 对应 | 判定 | 证据 |
|---|---|---|---|
| VERIFY-01 | FR-007 | Skill ×4 更新、GS-087 入库、`prd verify` 全 AC 覆盖、`doc-impact` 无缺失 | `harness prd verify` / `harness doc-impact` 输出 |
| VERIFY-02 | §7 | 回归：batch1/2/3a/3b/3c/4a 既有 spec 全绿 | 回归命令输出 |

---

## 5. 跨层搜索记录（6 层，2026-09-10 实测）

| 层 | 路径 | 关键词 | 找到 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | allocation / refund calculation | 无宿主实现 | 不涉及 |
| Core | `pallastrade_core/app/` | DefaultRefundAmount / ReimbursementTaxCalculator / adjustment allocation | `calculator/returns/default_refund_amount.rb`（**退款金额权威**）、`reimbursement_tax_calculator.rb`、`return_item.rb`（`refund_amount_calculator`、`pre_tax_amount`、`total`）、`promotions/projection/discount_projection.rb`（batch2 展示投影）、`promotions/snapshot/freeze.rb`（batch4a 快照） | **需新增只读分摊服务**（REUSE 现有权威） |
| API | `pallastrade_api/app/controllers` | refunds / returns / calculate | `admin/orders/refunds_controller`（index/show/create，**无 calculate**）、`store/orders/refunds` 同类 | **需新增只读预览端点** |
| Admin | `pallastrade_admin/app/views/pallastrade/admin/orders` | promotions panel | `_promotions.html.erb` + `_order_promotion.html.erb`（batch4a 已改读快照） | **需加只读分摊/可退列** |
| Storefront | `storefront/src/` | refund / return | 无退货流程页（售后归站外/客服） | 不涉及 |
| Platform | `platform/packages/` | allocation | 无相关类型；本批次新增只读端点会产出 schema（需 `api:docs:schemas` + 平台副本同步） | **契约再生** |

---

## 6. 技术影响

- **新增**：`pallastrade_core/app/services/pallastrade/promotions/allocation/adjustment_allocation.rb`（只读值对象 + 服务）；API controller `admin/orders/refund_calculations_controller.rb` + serializer；路由（member GET）；3 个 spec 文件。
- **修改**：`pallastrade_api/config/routes.rb`、Admin `_order_promotion.html.erb`、`ai/skills/*` ×4、`harness/scenarios/scenarios.json`、契约产物（`admin.yaml` + 平台副本）。
- **不改**：`DefaultRefundAmount` / `ReimbursementTaxCalculator` / `ReturnItem` / `Refund` / `Reimbursement` 计算与状态机；核销台账；订单金额。

---

## 7. 测试计划

| 文件 | 类型 | 覆盖 AC |
|---|---|---|
| `backend/spec/services/pallastrade/promotions/allocation/adjustment_allocation_spec.rb`（新） | service | AC-001/002/003 |
| `backend/spec/models/pallastrade/order_promotion_allocation_invariant_spec.rb`（新） | invariant | AC-002/004 |
| `backend/spec/requests/api/v3/admin/order_refund_calculation_spec.rb`（新） | request | AC-005/006/007 |
| `backend/spec/requests/pallastrade/admin/order_promotion_allocation_panel_spec.rb`（新） | request（Admin） | AC-008 |
| 既有批次回归（promotions + 退款相关） | 回归 | VERIFY-02 前置 |

运行命令（容器 `pallastrade-web-1`，工作目录 `/rails`）：

```bash
DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec <上表新文件> \
  spec/services/pallastrade/promotions spec/models/pallastrade/promotion_spec.rb \
  spec/models/pallastrade/promotion_redemption_spec.rb spec/models/pallastrade/order_checkout_*.rb \
  spec/jobs/pallastrade/promotions spec/requests/api/v3/admin spec/requests/pallastrade/admin
```

---

## 8. 文档同步清单（知识同步门）

- [x] `ai/skills/pallastrade-promotions/SKILL.md`：batch4b 分摊节（三类 basis / 恒等式 / 只读预览）。
- [x] `ai/skills/pallastrade-pricing/SKILL.md`：分摊权威节补「batch4b 只读分摊投影（不改权威）」。
- [x] `ai/skills/pallastrade-api-v3/SKILL.md`：新只读端点。
- [x] `ai/skills/pallastrade-admin/SKILL.md`：订单页分摊/可退列。
- [x] `harness/scenarios/scenarios.json`：GS-087。
- [x] `docs/prd/README.md` + 本 PRD 状态。
- [x] 契约：`rake api:docs:schemas` + `platform/docs/api-reference/admin.yaml` 同步 + `generated:check`。

---

## 9. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-10 | 0.1 | 初稿：PR-P6-1 现状盘点（REV-P6-3 权威）+ 选型（REUSE + 只读投影） | AI |
| 2026-09-10 | 1.0 | 用户「继续」授权实施批次 4b；FR/AC（AC-001..009）与测试映射锁定 | AI |
| 2026-09-10 | 1.1 | 实施完成：分摊服务 + 预览服务 + Admin API 只读端点 + 后台只读卡片；4 个新 spec 全绿；`api:docs:schemas` 再生（RefundCalculation* schemas）且 check clean；平台副本同步；Skill ×4 + GS-087 | AI |
| 2026-09-10 | 1.2 | done：回归 167 examples 0 failures（含 batch1/2/3a/3b/3c/4a）；rubocop 新增文件 0 违规；`prd verify` 全 AC 覆盖；`doc-impact` 0 missing | AI |

## 10. 实施说明与偏差记录

| 项 | 说明 |
|---|---|
| `frozen?` 锚点 | 快照 total 取 `order_promotion.total_amount.abs`；未冻结订单取投影 `Line#amount.abs`（同口径），两者都在测试中断言。 |
| 舍入余量阈值 | 仅当余量 ≤ `MAX_ROUNDING_REMAINDER = 0.05` 时才补给最大行（区分「舍入余数」与「真实数据不一致」）；超出时保留原始分摊并置 `balanced: false`（不掩盖不一致）。 |
| 零占比降级 | `order.pre_tax_item_amount == 0` 时全部归**最大金额行**（确定性），不是均分；spec 断言只出现一行分摊。 |
| 无 inventory unit 的行 | `refundable_amount = nil` + `refundable_source = 'unavailable'`（**不臆造金额**）；前台/后台渲染为 `n/a`。 |
| 参数校验位置 | 放在控制器（未知行/非整型/超量 → 422 并带具体 message），服务层只做 `clamp` 防御；动态 key 必须走 `to_unsafe_h`（否则 ActionController 报 400）。 |
| 422 状态 | 使用数值 `422`（Rack 3.2 已弃用 `:unprocessable_entity` 符号名，与 `:unprocessable_content` 行为不一致）。 |
| 路径文档 | `admin.yaml` 的 `paths` 为人工维护，本批次与 batch3c 一致**只再生 components schemas**（未新增 path 条目）；`api:docs:schemas:check` clean。 |
