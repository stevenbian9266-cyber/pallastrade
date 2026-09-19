# RESEARCH-20260919 — 车级权威报价（checkout cart-level quote）可行性

> 对应 PRD：`PRD-20260919-checkout-order-summary-fee-read-model`（第 5 项方案 A 的可行性复核）
> 结论：**当前架构下不可直接实现**；本轮以 A2（读模型修正 + Prepare 权威金额同步）落地，本文记录 A1 的候选设计与风险，供后续立项。

## 1. 目标

在结账页（`cart_` 阶段、未创建 Order）向买家展示**与最终订单完全一致**的运费 / 税费 / 折扣 / 应付金额。

## 2. 现场证据（代码级）

| 事实 | 位置 |
|---|---|
| 新购物车实体只有 `item_total`，无运费/税/总额 | `pallastrade_core/app/models/pallastrade/cart.rb`（`money_methods :item_total`） |
| 车阶段无报价端点；API 注释明写"权威运费在提交订单时计算" | `pallastrade_api/.../store/shipping_methods_controller.rb` |
| 权威金额全部在 Order 上产生：`build_fulfillment!`（`create_proposed_shipments` + `set_shipments_cost`）→ `update_line_item_prices!` → `create_tax_charge!` → `order.update_with_updater!` | `carts/submit.rb:105-135` |
| 上述步骤依赖**已持久化**的 Order / Shipment / Adjustment（不是纯函数） | 同上 |
| 权威字段已具备完整投影（含 `tax_total` / `amount_due` / `total` + `display_*`） | `order_checkout/view.rb#DELEGATED` |

**推论**：若要"不建 Order 也给权威金额"，只有两条路 —— 重写一套定价逻辑（**违反 money contract**：金额必须单一权威）或让既有管线跑一遍再回滚。

## 3. 候选设计

### A1-a：`Carts::Submit` dry-run（推荐候选）
- 形态：`PallasTrade::Carts::Submit.call(cart:, dry_run: true)` —— 与正常提交**同一事务、同一代码路径**，在读取金额后 `raise ActiveRecord::Rollback`，返回 `{ delivery_total, tax_total, discount_total, amount_due, … }`。
- 优点：数字必然与最终订单一致（同源）；零持久化（订单/库存预留/支付会话都不落库）。
- 必须先解决的清单：
  1. **非事务副作用盘点**：事件发布（`publish_submitted_event` 在事务外，安全）、审计（`Audit.record` 为 DB 写，回滚）、外部调用（目前提交路径无 PSP 外呼；**需逐行复核并加"dry-run 禁止外呼"守卫**）。
  2. **Auto-increment / 序列**：回滚不回退序列（可接受，但需说明）。
  3. **性能与锁**：每次地址/物流变更都跑完整管线 → 需防抖 + 服务端缓存键（cart 版本 + 地址指纹 + 物流方式）。
  4. **Redis/缓存副作用**（若有）需显式排除。
  5. 契约：新增 `POST /api/v3/store/carts/:id/quote` → OpenAPI + SDK 类型 + 契约再生成。
- 风险等级：中高（定价正确性由"同源"保证，风险集中在"回滚不干净"）。

### A1-b：抽取"定价纯函数层"
- 形态：把 Pricing / TaxRate / Shipping 计算从持久化步骤中解耦，形成 `Cart → FeeSet` 的纯计算服务，Order 与 Cart 共用。
- 优点：架构最干净；缺点：改造面覆盖核心定价链路（促销、税、运费、货币），回归面极大，属**平台级项目**。

## 4. 决策

- 本轮**不做 A1**：先以 A2 消除用户可感知缺陷（语义混乱 / 行缺失 / Total 误导），并把"权威金额"在 `Prepare` 后同步到右栏。
- 若后续确需"未建单即报价"，建议按 **A1-a** 立项（先做副作用盘点 + dry-run 守卫，再谈契约），并把 `A1-b` 作为长期方向评估。

## 5. 触发条件（何时值得做 A1）

1. 商家要求"确认页之前就有权威金额"（例如为了减少弃单或用于外部比价）；
2. 出现重复投诉"结账页金额与订单金额不一致"；
3. 新增渠道（如第三方比价/聚合）需要车级报价。

以上任一出现时，按 A1-a 立项。
