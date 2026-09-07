# REQ-20260907-order-standard-fulfillment-and-storefront-visibility

> 关联 Task：TASK-20260907121523-6c85f43c ｜ Gate：GATE-2026-09-07T12-18-39
> 任务类型：bugfix（架构内修复，无临时方案）

## 问题（两个 bug，已用 dev 数据 + 真实 API 复现证实）

1. **后台无法发货**：标准流程订单（如 `R916762118`，`state=paid`、`completed_at` 已写）后台填物流号后无「Ship」按钮。
   - `Shipment` 卡 `pending`；`Order#can_ship?` 只有 legacy checkout 语义（`complete?`=`state=='complete'`），对标准状态永远 false →
     `Shipment#determine_state` 恒 `pending` → `ship` 事件（from ready/canceled）不可达 → admin `_shipment.html.erb` 的
     `can_ship?(shipment)`（`shipment.shippable?`）不渲染发货 footer。
   - 标准状态机（`paid→processing→shipped→completed`）在 `order/checkout.rb` 已定义，但**全仓库无驱动者**：
     `Carts::Complete#complete_standard_order!` 只 `pay!`+`finalize!`，订单永久停在 `paid`。
2. **前台看不到订单**：`/customers/me/orders` 对所属账户（user 5 / store 1）返回 200 且含该单（已直连验证）；
   storefront `account/orders` 为登录 JWT 门控，未登录 401 被 `withFallback` **静默吞成 `[]`** → 渲染空态「no orders」，无登录引导。
   共享浏览器 `/account` 处于未登录（登录表单），即测试在未登录/登录错账户态查单。

## 根因归类

两条 bug 同源：**标准正向链路（Carts::Submit → paid → 履约）只实现了「支付完成」，履约（shipment 就绪/发货）与
订单标准状态机推进没有接入既有履约管线（ShipmentHandler/Shipment 状态机/admin/API）**；加上前台账户区对匿名会话无门控。
属 PRD-20260829（标准电商改造 P1）宣称「Admin 侧兼容」但未落地 + 新流程账户可见性 UX 缺口的架构断点。

## 设计（在架构内，无临时方案）

正向链路既有 canonical 履约管线 = `Order → Shipment（state_machine pending→ready→shipped）→ ShipmentHandler`
（ship 后：inventory_units ship!、touch shipped_at、OrderUpdater 刷新 shipment_state、事件 shipment.shipped/order.shipped）。
标准状态机（order/checkout.rb）已定义 `process/ship/complete_order`。修复 = **把标准流程接入该管线**：

1. `Order#can_ship?`：对 standard flow 的 `paid/processing` 返回 true（legacy 不变）→ `Shipment#determine_state` 可使 pending→ready。
2. `Order#advance_standard_fulfillment!`：shipment 已发货后推进标准状态机（全部发货→`ship!`→shipped；部分发货→`process!`→processing），
   并刷新派生 `shipment_state`。幂等、仅 standard、仅 paid/processing。
3. `ShipmentHandler#perform`（ship 的唯一同步汇聚点，覆盖 admin Rails、admin API、`Fulfillments::Create` 三条路径）末尾调用推进。
4. `Order#refresh_fulfillment_states!`：paid/processing 标准订单对 shipments 做派生重算（pending→ready 等，幂等，不改 shipped/canceled），
   - 挂到 admin `OrdersController#show`（治愈存量卡 pending 订单，打开即就绪）与 `Shipments::Update` 服务（任意 fulfillment 变更后即时派生）。
5. storefront：`account/orders` 增加账户会话门控——匿名/过期重定向 `/account?redirect=...`（与 `/account` 登录页一致），不再静默空态；
   `getOrders` 语义不变（登录态正常出单）。单笔订单详情 `/account/orders/[id]` 保留 guest token 单查，不加门控。
6. 逆向链路（P6）契约零破坏：标准订单发货后 `cancel` 已被 `allow_cancel?` 拒绝、走退款/退货域；状态推进只在状态机允许的
   `paid→processing→shipped` 内，不触碰 `completed`（交付确认另行治理）。

## Step 0：跨层搜索结果

| 层 | 结论 |
|---|---|
| backend/app | 无订单/履约覆写；用户邮箱账户(user 5) | 
| core | `Order`(STANDARD_STATES/can_ship?/fulfill!/fully_shipped?)、`order/checkout.rb`（标准状态机 pay/process/ship/complete_order）、`Shipment`(state machine/determine_state/shippable?)、`ShipmentHandler`、`OrderUpdater#update_shipment_state`、`Shipments::Update` |
| api | store `OrdersController`/`customer/orders_controller`（scope 正确）、admin `orders/fulfillments_controller#fulfill`（`@resource.ship!`） |
| admin | `ShipmentsController#ship`（`@shipment.ship`）、`orders/_shipment.html.erb`（can_ship? 渲染门控）、`shipment_helper#can_ship?`、`OrdersController#show/edit`、`OrderConcern` |
| storefront | `lib/data/orders.ts`（getOrders + withFallback）、`account/orders/page.tsx`（无鉴权门控）、`account/page.tsx`（已登录表单模式） |
| platform | SDK `customer.orders.list`（GET /customers/me/orders，auth JWT）；无需改 |

## Step 1：Skill 咨询证据（真实读取）

| Skill | 关键结论 |
|---|---|
| `pallastrade-shipping-fulfillment` | Shipment 状态机 pending→ready→shipped（cancel/resume）；`ship` 触发 `shipment.shipped` 并更新 order.shipment_state；Order Routing/Splitter 不属本变更；external fulfillment 走 `Fulfillments::Create`（ship! 汇聚点） |
| `pallastrade-checkout` | 标准流程：`Carts::Submit` 建 pending 订单 + `order.submitted`；`Carts::Complete` 对 standard 成员 `pay!+finalize!`（RISK-01 组合分流）；父订单发货状态用只读 `combined_shipment_state`；本变更不触及这些只读聚合 |
| `pallastrade-data-model` | `Order.state` vs `status`；Shipment 独立状态机（column state）；`state_machine` 状态即权威；`completed_at` 与 `state=='complete'` 语义区别（`complete` scope=completed_at not null） |

## 变更文件（预计）

- core：`order.rb`、`order/checkout.rb`（如需注释）、`shipment_handler.rb`、`services/shipments/update.rb`
- admin：`orders_controller.rb`（show 派生刷新）
- storefront：`account/orders/page.tsx`（+ 小型 server guard helper）
- spec：标准流程发货推进 model/service spec；admin/API 发货路径 request spec（若环境可跑）
- knowledge：`ai/skills/pallastrade-checkout/SKILL.md`（标准状态推进）、`ai/skills/pallastrade-shipping-fulfillment/SKILL.md`（standard 接线说明）

## 验证计划

- 后端：新增/更新 RSpec（标准订单 paid→shipment ready→ship→order shipped；部分发货→processing；legacy 零回归）；
  `harness check --profile quick`。
- 前台：storefront 单测/静态（守卫重定向逻辑）。
- dev 环境：以 R916762118 打开后台 → shipment 变 ready → 填/存物流号 → Ship → order 转 shipped；前台登录所属账户可见订单。
