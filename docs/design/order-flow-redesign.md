# PallasTrade 订单流程改造方案（标准电商模型 · Cart/Order 分表）

> 需求来源：购物车提供商品选择和删除；选中商品后进入订单确认流程（收件信息、物流方式等），点击提交订单进入 checkout 页面走支付流程；商品详情页 Buy Now 进入订单确认流程。需覆盖父子单、拆单、合单、合并支付、逆向订单流程。
> 设计原则：**按标准电商模型靠拢**——购物车与订单**分表**；购物车状态极简；订单使用标准状态机；下单时从购物车快照生成订单。
> 关联 PRD：PRD-20260829-checkout-订单模块-单笔走现有checkout-多笔走组合支付新流程-收货信息独立填写

---

## 0. 标准电商模型总览

```
┌────────────────────────────── Cart（购物车，临时会话）──────────────────────────────┐
│ 加购 → 勾选 → 删改 → 填收件信息 → 选物流 → 预览金额        （全程可放弃/过期）          │
└──────────────────────────────────────┬────────────────────────────────────────────┘
                                       │ 提交订单（Submit Order）
                                       ▼
┌────────────────────────────── Order（订单，正式业务实体）───────────────────────────┐
│ pending/awaiting_payment → paid → shipped → completed                                │
│ （canceled / refunded / returned 逆向）                                               │
└──────────────────────────────────────┬────────────────────────────────────────────┘
                                       │ 拆单 / 合并支付 / 履约 / 逆向
```

**核心**：
- **Cart 与 Order 是两张独立的表**（物理分表，非 5.x 同表）
- **Cart 无复杂状态机**：active（进行中）→ converted（已转订单）/ abandoned（弃购）
- **Order 用标准订单状态机**：创建（待支付）→ 支付 → 发货 → 完成；取消/退款/退货逆向
- **Order 在下单（提交订单）时创建**，从 Cart 快照商品/收件/物流/金额，之后 Cart 不可再改

---

## 1. 数据模型（分表）

### 1.1 `pallastrade_carts`（购物车表，新增）

| 字段 | 说明 |
|---|---|
| id / token | 购物车标识（token 供游客会话） |
| user_id / store_id | 归属用户与店铺 |
| currency / locale | 币种/语言 |
| **status** | `active`（进行中）→ `converted`（已转订单）/ `abandoned`（弃购） |
| email | 游客邮箱（可暂存） |
| expires_at | 过期时间（弃购触发） |
| selected_line_item_ids（可选） | 勾选商品范围（或前端状态） |

- 关联：`cart_items`（variant_id, quantity, metadata）
- **收件/物流暂存**：`carts.shipping_address_id`、`cart_shipments`（或直接存快照 JSON/关联），提交时锁进订单
- **状态机（极简）**：`active → converted`（提交订单后）；`active → abandoned`（过期/主动弃购）
- 无金额/支付/履约概念（金额在确认页由服务端实时算）

### 1.2 `pallastrade_orders`（订单表，改造现有 Order）

| 字段 | 说明 |
|---|---|
| id / number | 订单号 |
| user_id / store_id / currency | 归属 |
| **state** | 标准状态机（见 §2） |
| **status** | 保留 `draft`（Admin 代下单）/ `placed`（已提交）兼容 |
| cart_id | 来源购物车（可空：Admin 下单 / Buy Now 直下单） |
| **parent_order_id** | 拆单父单 |
| completed_at / paid_at / canceled_at / shipped_at / returned_at | 关键时间戳 |
| shipping_address / billing_address（快照） | 下单时锁定 |

- 关联：`order_items`（**商品快照**：variant_id, name, sku, unit_price, quantity, tax, total）、`shipments`、`payments`、`payment_sessions`、`payment_splits`、`payment_combinations`、`cancellations`、`return_authorizations`、`customer_returns`、`refunds`
- **金额**：item_total、tax_total、shipment_total、promo_total、total、payment_total、outstanding_balance、amount_due（沿用现有 money 体系）

### 1.3 实体关系（ER 语义）

```
User ──1:N── Cart（active 可多个/一个）──提交──► Order（pending）
User ──1:N── Order ──1:N── OrderItem / Payment / Shipment
Order ──1:N── PaymentSplit ──N:1── PaymentCombination（合并支付）
Order ──1:N── Children（parent_order_id，拆单）
Order ──1:N── Cancellation / Refund / ReturnAuthorization / CustomerReturn
```

---

## 2. 状态机（标准电商）

### 2.1 购物车状态（极简）

```
active ──提交订单──► converted
   └──过期/主动清除──► abandoned
```

- 无金额/支付/履约状态；只是临时会话生命周期

### 2.2 订单状态机（标准）

```
draft（Admin 代下单草稿，可选，5.x 兼容）
  │
  ▼ 提交（用户下单 / Admin 确认）
pending / awaiting_payment（已提交·待支付）★ 订单创建节点
  │
  ▼ 支付成功
paid / confirmed（已支付）
  │
  ▼ 履约处理
processing（处理中）→ shipped（已发货）→ completed / delivered（已完成）
  │
  ▼ 逆向
canceled（取消：待支付直接取消 / 已支付退款+取消）
refunded / partially_refunded（退款 / 部分退款）
returned / partially_returned（退货 / 部分退货）
```

| 状态 | 含义 | 触发 |
|---|---|---|
| `draft` | Admin 代下单草稿 | Admin 创建 |
| `pending` / `awaiting_payment` | 已提交待支付 | 用户提交订单 |
| `paid` / `confirmed` | 已支付 | 支付成功 |
| `processing` | 处理中 | 开始履约 |
| `shipped` | 已发货 | 全部/部分发货 |
| `completed` | 已完成 | 完成履约 |
| `canceled` | 已取消 | 取消（未付/已付退款） |
| `refunded` | 已退款 | 退款 |
| `returned` | 已退货 | 售后退货 |

### 2.3 派生状态（沿用现有计算）

- `payment_state`：paid / balance_due / credit_owed / failed / void（由支付记录派生）
- `fulfillment_state`：pending / ready / partial / shipped / backorder（由 shipments 派生）
- 父子单聚合：`combined_*`（父 = Σ 子，P3 现有能力复用）

### 2.4 拆单 / 合单状态

- 拆单：源 Order → 父 Order + 子 Orders（`parent_order_id`），各子单独立走状态机；父单聚合展示
- 合单/合并支付：`PaymentCombination.status`（pending → processing → succeeded/failed/canceled/expired）；成员订单保持各自状态，组合支付成功后统一 `paid`

---

## 3. 数据流（Data Flow）

### 3.1 下单（Cart → Order 快照）

```
提交订单（POST /carts/:id/submit）
  1. 锁 Cart + 校验（库存/价格/风控 P8）
  2. 创建 Order：从 Cart 快照
     - order_items ← cart_items（商品/数量/单价锁定）
     - shipping_address ← cart 收件信息（锁定）
     - shipments ← 物流方式/运费（锁定）
     - 金额服务端重算（item/tax/shipment/total）
  3. Cart → converted（清勾选，Cart 数据保留可查）
  4. Order → pending（待支付）
```

### 3.2 支付（单笔）

```
Checkout 页：POST /payment_sessions（Stripe Checkout Session）
  → PaymentElement 确认 → 支付成功
  → Order → paid（completed_at/paid_at）
```

### 3.3 拆单（Split）

```
已支付 Order（含 N 行）→ Splitter 分组
  → 父 Order（空容器/剩余）+ 子 Orders（parent_order_id, split_from_id）
  → 金额/运费/已付按行比例分摊（order_items 迁移 + PaymentSplit 记账）
  → 各子单独立履约/售后；父单聚合
```

### 3.4 合单 / 合并支付（Combine）

```
多笔 pending/balance_due Orders
  → PaymentCombinations::Create
  → 组合（amount = Σ amount_due，服务端计算）
  → 每单 PaymentSplit（记账分摊）
  → 一个 Stripe Session（挂 primary order）
  → 支付成功 → Complete 按 split 逐单入账 → 各订单 paid
```

### 3.5 逆向（Reverse）

```
取消：OrderCancellation（reason/restock/refund）→ canceled + 回库存 + （退款）
退款：Refund → 原路 / StoreCredit → payment_state 派生（refunded/partial）
退货：ReturnAuthorization → CustomerReturn（return_items）→ Reimbursement
组合逆向：按 PaymentSplit.captured_amount 分摊退款
```

---

## 4. 业务流（Business Flow）

### 4.1 购物车（Cart）
- 加购 / 勾选（checkbox + 全选）/ 删除 / 数量调整 / 金额汇总（仅勾选）
- 勾选为空 → 「去结算」禁用

### 4.2 订单确认（Order Confirmation，仍在 Cart 会话）
- 展示本次结算商品 + 金额
- 收件信息（新增/选已存地址）
- 物流方式（可选配送，运费）
- 备注（可选）
- 「提交订单」

### 4.3 提交订单 → Checkout 支付
- 提交 = 创建 Order（pending）+ Cart converted
- 跳 `/checkout/[orderId]`：只读收货/物流/商品 + 支付方式 + Stripe 支付
- 支付成功 → 完成页

### 4.4 Buy Now
- 商品详情页 → 创建单商品 Cart（或直接提交）→ 订单确认 → 提交 → 支付

### 4.5 我的订单
- 待支付（pending/balance_due）：单笔 → Checkout 补付；多笔 → 合并支付（收货逐单确认 → 商品/金额汇总 → 组合支付）
- 已支付/履约中/已完成/逆向：列表 + 详情

### 4.6 逆向（前台 + Admin）
- 未支付取消；已支付取消退款；退款；售后退货（授权→收货→退款）

---

## 5. 信息流（Information Flow）

### 5.1 页面 / 路由

| 页面 | 路由 | 说明 |
|---|---|---|
| 购物车 | `/cart` | 勾选/删除/数量/汇总 + 去结算 |
| 订单确认（新） | `/checkout-info/[cartId]` | 收件 + 物流 + 预览 + 提交订单 |
| Checkout 支付 | `/checkout/[orderId]` | 只读 + 支付（纯支付页） |
| Buy Now | 商品页 → `/checkout-info/[cartId]` | 单商品订单确认 |
| 我的订单 | `/account/orders` | 待支付/进行中/已完成 + 单笔/多笔 |
| 合并支付（增强） | `/combined-payment/[pcomId]` | 收货确认（逐单）+ 明细 + 组合支付 |
| 订单完成 | `/order-complete/[id]` | 成功页 |

### 5.2 API 设计

```
Cart（重构，基于 carts 表）：
  POST /api/v3/store/carts（创建）
  POST /api/v3/store/carts/:id/items（加购）
  PATCH /api/v3/store/carts/:id/items/:item_id（数量）
  DELETE /api/v3/store/carts/:id/items/:item_id（删除）
  GET /api/v3/store/carts/:id（含勾选/金额）

订单确认（新）：
  PUT /api/v3/store/carts/:id/shipping_address（收件信息）
  PUT /api/v3/store/carts/:id/fulfillments/:fid（物流选择）
  POST /api/v3/store/carts/:id/submit（★提交订单 → 创建 Order）

Checkout（基于 orders 表）：
  POST /api/v3/store/orders/:id/payment_sessions（支付会话）
  PATCH /api/v3/store/orders/:id/payment_sessions/:sid/complete
  GET /api/v3/store/orders/:id（支付页信息）

订单：
  GET /api/v3/store/customers/me/orders（我的订单列表）
  PATCH /api/v3/store/customers/me/orders/:id/shipping_address（合并逐单收货，新）

合并支付：
  POST /api/v3/store/payment_combinations（已有）
  PATCH .../complete（已有）
```

---

## 6. 资金流（Money Flow）

```
确认阶段：金额预览（Cart，服务端实时算，无资金）
提交订单：无资金（Order 创建，金额锁定）
支付：Stripe 一次扣款
  单笔：Payment 挂 Order → Order paid
  合并：Payment 挂组合 + PaymentSplit 逐单 → 各 Order paid
逆向：取消退款（原路）/ 部分退款 / StoreCredit 兜底 / 组合按 split 分摊退款
```

---

## 7. 兼容与迁移（5.x → 标准模型）

### 7.1 数据迁移
1. **新建 `pallastrade_carts` + `cart_items`**（含 token/user/store/currency/status）
2. **现有 `pallastrade_orders` 表**：
   - `state=cart/address/delivery/payment` 且无 `completed_at` 的存量（购物车/弃单）→ 迁到 `carts`（status=abandoned 或 active），或清理
   - `completed_at` 有值的完整订单 → 保留 `orders`，补 `state=paid/complete` 语义
3. **`line_items` 拆分语义**：`cart_items`（购物车）+ `order_items`（订单快照）；存量订单 line_items 关联 order 保持不变（6.0 拆分）

### 7.2 兼容策略
- 新增 `Cart` 模型；`Order` 模型保留（去掉 cart 相关方法/state）
- 现有前端 cart/checkout 页重构为「购物车 + 订单确认 + 纯支付」三段
- 存量订单 API/展示保持兼容（order serializer 不变，补 cart_id/submitted_at）
- Buy Now / 合并支付 / 拆单 / 逆向逐步迁移到新语义

### 7.3 风险
1. **分表迁移**：存量购物车/订单数据迁移脚本 + 双写/回滚方案
2. **checkout 流程重构**：现有 `checkout/[id]`（地址+配送+支付）拆为「订单确认（Cart 内）」+「支付（Order）」，涉及 PaymentSection/地址组件/Webhook 大面积调整
3. **库存锁定时机**：提交订单 vs 支付确认（沿用 `stock_reservation_strategy`，与 P8 前置校验协调）
4. **Webhook/事件兼容**：`order.*` 事件语义随状态机调整；弃单恢复（P0-3）需适配 Cart 表
5. **拆单/合并/逆向**：基于新 Order 状态机重验证

---

## 8. 实施阶段（Roadmap）

### Phase 1：数据模型分表 + 下单闭环
- 新建 `carts`/`cart_items` 表 + `Cart` 模型
- `Order` 模型去购物车语义 + 标准状态机（pending→paid→shipped→completed）
- 迁移脚本（存量购物车 → carts；存量订单 → orders 补语义）
- `POST /carts/:id/submit`（下单 → 创建 Order + Cart converted）
- 购物车页勾选/删除 + 订单确认页（收件/物流）+ Checkout 纯支付页 + Buy Now
- 后端/前端 API 重构 + 测试

### Phase 2：我的订单 + 合并支付增强
- 待支付订单列表（pending/balance_due 语义）
- 单笔 → Checkout 补付；多笔 → 收货逐单确认 + 明细 + 组合支付
- 订单地址更新 API

### Phase 3：逆向 + 父子/拆合单
- 取消/退款/退货前台化
- 拆单/父子单在新状态机下理顺（提交后/支付后拆分）
- 合并支付逆向退款

### Phase 4：清理与 6.0 对齐
- 废弃旧 cart state（Order.state=cart 等）
- 事件/Webhook/文档/知识同步
- 与 6.0 原生 Cart/Order 分离对齐
