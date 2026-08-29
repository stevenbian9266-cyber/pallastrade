# PRD-20260829-checkout-订单流程标准电商改造-购物车与订单分表-订单确认-提交订单-checkout纯支付-自有化去spree化

| 元数据 | 值 |
|---|---|
| 状态 | approved（2026-08-30 用户确认「实施」） |
| 创建日期 | 2026-08-29 |
| 来源 | 需求：购物车提供商品选择和删除；选中商品后进入订单确认流程（收件信息、物流方式等），点击提交订单进入 checkout 页面走支付流程；商品详情页 Buy Now 进入订单确认流程（同上）。需覆盖父子单、拆单、合单、合并支付、逆向订单流程。按标准电商方案靠拢；购物车与订单分表；处理自有化不干净部分 |
| 分类 | checkout |
| 关联 Skill | pallastrade-checkout / pallastrade-storefront / pallastrade-api-v3 / pallastrade-data-model / pallastrade-events-webhooks |
| 关联 REQ | 实施时回填 |
| 关联 PRD | 原 PRD-20260829-checkout-订单模块-单笔走现有checkout-多笔走组合支付新流程（需求演进，范围扩大为订单流程标准电商改造） |
| 关联设计 | `docs/design/order-flow-redesign.md`（完整方案，本 PRD 为其实施级细化） |
| 需求类型 | 新功能 / 架构改造（去 Spree 化） |

## 1. 背景与目标

- **一句话需求原文**：购物车提供商品选择和删除；选中商品后进入订单确认流程（收件信息、物流方式等），点击提交订单进入 checkout 页面走支付流程；商品详情页 Buy Now 进入订单确认流程（同上）。需覆盖父子单、拆单、合单、合并支付、逆向订单流程。按标准电商方案靠拢；购物车与订单分表；处理自有化不干净部分。
- **背景**：
  - 当前 PallasTrade 5.x（`PallasTrade.version = 5.6.0.rc1`）中 **Cart 与 Order 同表**（`PallasTrade::Order`，`state=cart` 即购物车；`POST /carts` 即插入 Order 记录）。这是从 Spree fork 演化遗留的**同表妥协**。
  - 订单没有「订单确认」「提交订单」节点：只有购物车（cart 态）与已支付完成（complete 态）；「已提交待支付」订单只能靠 `completed_at` 有值 + 未支付来表达，不符合标准电商语义。
  - 代码内存在大量**自有化不干净**的痕迹：Spree 的 `checkout_flow`（cart→address→delivery→payment→confirm→complete）、`PallasTrade.base_class`、Zone/Taxon/Taxonomy 等 Spree 概念、大量 `naming bridge`（5.5/5.6 → 6.0 列重命名）、几十处 `@deprecated ... removed in PallasTrade 6.0` 过渡注释。
  - 代码注释明确规划了 **6.0 Cart/Order split**（`carts/complete.rb`："In PallasTrade 6 this service will complete the PallasTrade::Cart, and create a PallasTrade::Order"），本次即**提前落地该规划**。
- **目标**：
  1. **Cart / Order 物理分表**：购物车独立表 + 极简状态；订单独立表 + 标准状态机。
  2. **新增「订单确认」与「提交订单」节点**：收货/物流在订单确认独立步骤填写；提交订单 = 创建订单（待支付）；Checkout 收敛为纯支付。
  3. **购物车勾选/删除** + Buy Now 走订单确认流程。
  4. **自有化去 Spree 化**：清理本次改造涉及订单/购物车的 Spree 遗留、naming bridge 与过渡 deprecation。
- **成功指标**：
  - 新购物车流程：加购 → 勾选 → 订单确认 → 提交订单 → Checkout 支付，端到端可走通。
  - 订单状态机符合标准电商（pending→paid→shipped→completed；canceled/refunded/returned）。
  - `pallastrade_orders` 表不再承载 cart 语义（无 `state='cart'` 新数据）；新增 `pallastrade_carts` 表承载购物车。
  - 涉及订单/购物车的 deprecation 注释与 naming bridge 清理完毕，`harness doc-impact` 通过。

## 2. 范围（Scope）

### 2.1 本次实施（P1）
1. 新建 `pallastrade_carts` + `cart_items` 表，`PallasTrade::Cart` 模型（极简状态机）。
2. `PallasTrade::Order` 去除购物车语义（移除 `state=cart`/`checkout_flow` 购物车段），改用标准状态机。
3. `POST /api/v3/store/carts/:id/submit`（提交订单 → 创建 Order + Cart converted）。
4. 前端：购物车页勾选/删除；订单确认页（收件+物流+预览）；Checkout 纯支付页；Buy Now 走订单确认。
5. 后端 API/事件/Webhook 相应重构 + 测试。
6. **自有化清理**：本次触碰的订单/购物车相关 Spree 遗留与过渡注释清理（清单见 §6.5）。

### 2.2 本次不做（后续阶段）
- 存量数据迁移（用户确认：**存量数据不处理**，存量购物车/订单保持原样，新流程只作用于新数据）。
- P2：我的订单补付 + 合并支付增强（收货逐单确认/明细）。
- P3：逆向流程前台化 + 父子/拆合单在新状态机下理顺。
- P4：Zone/Taxon/Taxonomy 等非订单领域的 Spree 概念移除。
- 6.0 的 User→Customer 表重命名等。

## 3. 现状分析（5.x 现状 + 自有化遗留）

### 3.1 订单/购物车现状
- `PallasTrade::Order` 单表承载：购物车（`state=cart/address/delivery/payment/confirm`）、正式订单（`complete`）、逆向（`canceled/returned/awaiting_return/resumed`）。
- `checkout_flow`（Spree 模式）：`cart → address → delivery → payment → confirm → complete`，`previous_states = [:cart]`。
- `status`：draft（购物车/Admin 代下单）/ placed / canceled；`completed_at` 表示下单完成。
- 派生状态：`payment_state`（OrderUpdater：paid/balance_due/credit_owed/failed/void）、`shipment_state`（pending/ready/partial/shipped/backorder）。
- 购物车服务：`Carts::Create/Update/UpsertItems/Complete/AutoSplit`；`PallasTrade::Cart` 模型**不存在**（Cart 即 Order 的 cart 态）。
- 购物车页：有删除/数量，**无勾选**；「Checkout」跳 `checkout/[cartId]`（地址+配送+支付一页）。
- 父子单（P2/P3）：`parent_id/children` + `combined_*` 聚合；拆单 `Splitter/ManualSplit/AutoSplit`；合并支付 `PaymentCombination/PaymentSplit`。
- 逆向：`Orders::Cancel/Refund/ReturnAuthorization/CustomerReturn/Reimbursement`。

### 3.2 自有化遗留清单（本次改造涉及）
| # | 遗留 | 位置 | 本次处理 |
|---|---|---|---|
| S-01 | Order 承载购物车语义（state=cart、previous_states [:cart]、checkout_flow 购物车段） | `order.rb` / `order/checkout.rb` | ✅ 分表移除 |
| S-02 | `PallasTrade::Cart` 缺失（Cart=Order 同表） | `Carts::*` 服务 | ✅ 新建 Cart 模型 |
| S-03 | naming bridge（"5.5 API naming bridges (DB column rename in 6.0)"、user_id→customer_id 注释） | `order.rb:84,150`、`line_item.rb:106` 等 | ✅ 本次触碰文件清理 |
| S-04 | deprecation 过渡注释（"removed in 6.0"）涉及订单/购物车 | 多个 concern/model | ✅ 本次触碰文件清理 |
| S-05 | `PallasTrade.base_class`（Spree::Base 模式） | 全局 | ⏸ 本次不动（超出范围） |
| S-06 | Zone/Taxon/Taxonomy（Spree 概念） | 全局 | ⏸ 本次不动 |

> 原则：只清理**本次改造触碰**的文件/概念，避免扩大爆炸半径；未触碰领域留待 P4。

## 4. 目标架构（标准电商）

```
Cart（pallastrade_carts，临时会话）
  active → converted / abandoned          （极简状态）
  加购 / 勾选 / 删除 / 收件信息 / 物流选择 / 金额预览

    └─ 提交订单（POST /carts/:id/submit）→ 创建 Order + Cart→converted

Order（pallastrade_orders，正式实体，标准状态机）
  pending（待支付）→ paid → processing → shipped → completed
  ├─ canceled / refunded / partially_refunded / returned / partially_returned（逆向）
  ├─ 快照：order_items、shipping_address、shipments（物流/运费）、金额
  ├─ 父子：parent_order_id / children（拆单）
  ├─ 合并支付：PaymentCombination / PaymentSplit
  └─ 逆向：Cancellation / Refund / ReturnAuthorization / CustomerReturn
```

## 5. 验收标准（AC 摘要，完整见 §7）

- AC-001：新建购物车走新流程：加购 → 勾选 → 订单确认 → 提交订单 → Checkout 支付，端到端成功。
- AC-002：`pallastrade_carts` 表存在，购物车状态 active→converted；订单创建后购物车不可再改。
- AC-003：`POST /carts/:id/submit` 创建 Order（pending），商品/收件/物流/金额快照正确，服务端重算金额。
- AC-004：订单状态机支持 pending→paid→shipped→completed 及 canceled/refunded/returned 转换。
- AC-005：Buy Now 从商品详情页进入订单确认流程（单商品）。
- AC-006：购物车页支持勾选/全选/删除；勾选为空时「去结算」禁用。
- AC-007：Checkout 页为纯支付（收货/物流只读，无地址编辑表单）。
- AC-008：涉及订单/购物车的 naming bridge 与 deprecation 清理完毕，测试全绿。

## 6. 技术方案（详细）

### 6.1 数据模型

#### 6.1.1 新增 `pallastrade_carts`

```ruby
# migration
create_table "pallastrade_carts", force: :cascade do |t|
  t.string   "token", null: false, index: { unique: true }   # 游客会话令牌
  t.bigint   "user_id", index: true                          # 登录用户（可空=游客）
  t.bigint   "store_id", null: false, index: true
  t.string   "currency", null: false, default: "USD"
  t.string   "locale", null: false, default: "en"
  t.string   "status", null: false, default: "active"        # active/converted/abandoned
  t.string   "email"                                         # 游客邮箱（暂存）
  t.bigint   "shipping_address_id", index: true              # 收件信息（确认阶段暂存）
  t.bigint   "billing_address_id", index: true
  t.string   "customer_note"
  t.datetime "expires_at"                                    # 弃购时间
  t.jsonb    "public_metadata"
  t.jsonb    "private_metadata"
  t.datetime "converted_at"                                  # 转订单时间
  t.datetime "created_at", null: false
  t.datetime "updated_at", null: false
end
```

#### 6.1.2 新增 `pallastrade_cart_items`

```ruby
create_table "pallastrade_cart_items", force: :cascade do |t|
  t.bigint   "cart_id", null: false, index: true
  t.bigint   "variant_id", null: false, index: true
  t.integer  "quantity", null: false, default: 1
  t.boolean  "selected", null: false, default: true          # 勾选（去结算范围）
  t.jsonb    "metadata"
  t.datetime "created_at", null: false
  t.datetime "updated_at", null: false
end
```

#### 6.1.3 `pallastrade_orders` 变更

```ruby
# 新增列
add_column :pallastrade_orders, :cart_id, :bigint, index: true        # 来源购物车（可空）
add_column :pallastrade_orders, :submitted_at, :datetime               # 提交订单时间
# 语义调整（不删列，兼容存量）：
#   state 仅保留正式订单状态（见 6.2）；status=draft 仅 Admin 代下单
#   completed_at 仅支付成功后设置；paid_at 增加
```

- **不做物理删列**（存量数据不处理）：`state` 列保留但新流程写入新状态值；旧值（cart 等）仅存量。
- `order_items`：继续使用现有 `line_items` 表（`order_id` 关联）作为订单快照；`cart_items` 为购物车行，两者语义分离（6.0 再物理拆分）。

### 6.2 状态机

#### 6.2.1 Cart 状态机（极简）

```ruby
state_machine :status, initial: :active do
  event :convert  { transition active: :converted }   # 提交订单后
  event :abandon  { transition active: :abandoned }   # 过期/主动清除
end
```

#### 6.2.2 Order 状态机（标准）

```ruby
state_machine :state, initial: :pending, use_transactions: false, action: :save_state do
  # 正向
  event :submit       { transition draft: :pending }                 # Admin 草稿→待支付
  event :pay          { transition pending: :paid }                  # 支付成功
  event :process      { transition paid: :processing }               # 开始履约
  event :ship         { transition processing: :shipped }            # 发货
  event :complete     { transition shipped: :completed }             # 完成

  # 逆向
  event :cancel       { transition [:pending, :paid, :processing, :shipped] => :canceled }
  event :refund       { transition [:paid, :processing, :shipped] => :refunded }
  event :partial_refund { transition [:paid, :processing, :shipped] => :partially_refunded }
  event :request_return  { transition [:paid, :processing, :shipped] => :awaiting_return }
  event :return       { transition awaiting_return: :returned }
  event :partial_return { transition [:paid, :shipped] => :partially_returned }
end
```

- 派生状态保留：`payment_state`（paid/balance_due/credit_owed/failed/void）、`shipment_state`（pending/ready/partial/shipped/backorder）由 OrderUpdater 计算（复用现有）。
- **兼容旧值**：旧订单 `state=complete` 在读取/展示时视为 `completed`；`state=cart 等` 存量不迁移。
- 事件名与现有事件映射：现有 `cancel`/`return`/`resume` 保留；`authorize_return` 保留。

#### 6.2.3 提交订单（Submit）语义

```
POST /carts/:id/submit
  1. 校验：Cart 属于当前用户/游客 token、status=active、至少 1 个 selected item、库存、价格（P8 前置校验复用）
  2. 事务：
     a. 创建 Order：user/email/currency/locale/cart_id=cart.id
     b. order.line_items ← 勾选的 cart_items（variant/quantity 快照；行级价格锁定）
     c. order.ship_address ← cart.shipping_address（快照）；bill_address 同理
     d. 生成 shipments + 选择物流（复用现有 Shipment/ShippingRate 逻辑）+ 运费
     e. OrderUpdater 重算金额（item/tax/shipment/total）
     f. order.submitted_at=now；order.state=pending（或 submit 事件）
  3. cart.convert!（status=converted, converted_at=now）
  4. 返回 Order（含 prefixed id）→ 前端跳 /checkout/[orderId]
```

### 6.3 后端（模型 / 服务 / API / 事件）

#### 6.3.1 模型
- **新建 `PallasTrade::Cart`**（`pallastrade_carts`）：`has_many :cart_items`、`belongs_to :user/store`、极简状态机、`SingleStoreResource`。
- **新建 `PallasTrade::CartItem`**（`pallastrade_cart_items`）。
- **改造 `PallasTrade::Order`**：
  - 移除购物车段：`checkout_flow` 的 cart 入口、`previous_states [:cart]`、`state=cart` 相关方法（`cart?` 等按需保留兼容或移除）。
  - 增加 `belongs_to :cart, optional: true`、`submitted_at`。
  - 标准状态机（6.2.2）；保留 payment_state/shipment_state 派生。
- **LineItem**：保留（订单行），与 CartItem 语义分离；`naming bridge` 清理（本次触碰文件）。

#### 6.3.2 服务
- 新建 `PallasTrade::Carts::Submit`（提交订单，见 6.2.3）。
- 重构 `PallasTrade::Carts::*`（Create/Update/UpsertItems/Complete）从 Order 迁移到 Cart 模型。
- `Carts::Complete` 语义：改为「支付成功后完成订单」的适配（或由新流程取代）。
- `Checkout::Advance/Next`：购物车段移除，仅保留支付前信息收集（如仍需要）。

#### 6.3.3 API（Store v3）
```
购物车（基于 carts 表）：
  POST   /api/v3/store/carts                       # 创建
  GET    /api/v3/store/carts/:id                   # 详情（含 items/勾选/金额预览）
  POST   /api/v3/store/carts/:id/items             # 加购
  PATCH  /api/v3/store/carts/:id/items/:item_id    # 数量/勾选
  DELETE /api/v3/store/carts/:id/items/:item_id    # 删除
  PUT    /api/v3/store/carts/:id                   # email/备注
订单确认：
  PUT    /api/v3/store/carts/:id/shipping_address  # 收件信息
  PUT    /api/v3/store/carts/:id/fulfillments/:fid # 物流选择
  POST   /api/v3/store/carts/:id/submit            # ★提交订单 → Order
Checkout（基于 orders 表）：
  POST   /api/v3/store/orders/:id/payment_sessions
  PATCH  /api/v3/store/orders/:id/payment_sessions/:sid/complete
  POST   /api/v3/store/orders/:id/complete
  GET    /api/v3/store/orders/:id                  # 支付页信息（只读）
```
- 兼容：`POST /carts` 返回结构从 Order（cart 态）改为 Cart；`GET /carts/:id` 序列化器新增 CartSerializer。

#### 6.3.4 事件 / Webhook
- `cart.created/updated/converted/abandoned`（新增）。
- `order.submitted/paid/shipped/completed/canceled/refunded/returned`（按新状态机对齐现有 `order.*` 事件）。
- 弃单恢复（P0-3 邮件 `?token=`）：适配 Cart 表（`carts.token`）。

### 6.4 前端（Storefront）

#### 6.4.1 页面 / 路由
| 页面 | 路由 | 说明 |
|---|---|---|
| 购物车 | `/cart` | 勾选/全选/删除/数量/金额汇总 + 去结算 |
| 订单确认（新） | `/checkout-info/[cartId]` | 收件 + 物流 + 商品/金额预览 + 提交订单 |
| Checkout 支付 | `/checkout/[orderId]` | 只读收货/物流/商品 + 支付方式 + Stripe（纯支付） |
| Buy Now | 商品页 → `/checkout-info/[cartId]` | 单商品订单确认 |
| 订单完成 | `/order-complete/[id]` | 成功页（已有） |

#### 6.4.2 组件
- 购物车：`CartPage` 增加勾选（checkbox/全选）；`CartContext`/`useCart` 适配 Cart API。
- 订单确认：新 `CheckoutInfo` 组件（地址表单复用 `AddressBlock`/地址选择器 + `FulfillmentBlock` 物流选择 + 金额摘要 + 提交按钮）。
- Checkout 支付：改造现有 `CheckoutPageContent`/`PaymentSection` 为只读信息 + 支付（去掉地址填写）。
- Buy Now：`buy-now.ts` 改为创建 Cart（含商品）→ 跳订单确认。

#### 6.4.3 SDK
- `Cart` 类型（新）、`CartItem`（含 selected）、`Order.submitted_at/cart_id`。
- 客户端方法：`carts.submit`、`carts.items.select`、`carts.updateShippingAddress`、`orders.paymentSessions.*`（迁移到 orders 域）。

### 6.5 自有化清理清单（本次实施）

| # | 动作 | 文件 |
|---|---|---|
| C-01 | 移除 Order 购物车段 checkout_flow（cart 入口/previous_states [:cart]/cart 相关转换） | `order.rb`、`order/checkout.rb` |
| C-02 | 新建 `PallasTrade::Cart`，`Carts::*` 服务迁到 Cart | `carts/*.rb`、新 `cart.rb` |
| C-03 | 清理订单/购物车 naming bridge 注释（"5.5 API naming bridges"、"user_id stays in 5.x"） | `order.rb:84,150`、`line_item.rb:106` 等本次触碰文件 |
| C-04 | 清理涉及订单/购物车的 `removed in 6.0` deprecation 注释与废弃方法 | 本次触碰的 concern/model/service |
| C-05 | 更新 `Carts::Complete`/`Checkout` 服务注释（不再表述 "In PallasTrade 6..."） | `carts/complete.rb` 等 |
| C-06 | 涉及订单/购物车的 API 文档与 Skill 同步（去 5.x/6.0 表述） | `api-docs/store.yaml`、`ai/skills/pallastrade-checkout/SKILL.md` 等 |

> 非本次领域（Zone/Taxon/Taxonomy、`base_class`、全量 naming bridge）留待 P4，不扩大爆炸半径。

### 6.6 兼容策略（存量数据不处理）
- 存量 `pallastrade_orders` 中的 `state=cart/address/delivery/payment/confirm` 与 `complete` 记录**原样保留**（不迁移、不清理）。
- 新流程只写新语义（Cart 表 + Order 新状态）。旧 `checkout/[cartId]`（旧购物车结算）保留可用（针对存量 cart 态订单）或逐步下线。
- API 兼容：`POST /carts` 新返回 Cart；旧客户端（若存在）需适配（灰度/双兼容可评估）。
- 序列化器：OrderSerializer 保留现有字段（`is_parent/is_child/combined_*`），新增 `submitted_at/cart_id`。

## 7. 功能需求（FR）与验收标准（AC）

| FR | 说明 | AC |
|---|---|---|
| FR-001 | 购物车支持加购/勾选/全选/删除/数量/金额汇总 | AC-001/006 |
| FR-002 | 订单确认页（收件信息 + 物流方式 + 商品/金额预览） | AC-009 |
| FR-003 | 提交订单创建正式订单（待支付）+ Cart converted | AC-002/003 |
| FR-004 | Checkout 纯支付页（收货/物流只读） | AC-007 |
| FR-005 | Buy Now 走订单确认流程 | AC-005 |
| FR-006 | Order 标准状态机（pending→paid→shipped→completed + 逆向） | AC-004 |
| FR-007 | 自有化清理（S-01~04 涉及项） | AC-008 |
| FR-008 | 订单 API 迁移到 orders 域 + 事件对齐 | AC-010 |

- AC-009 ← FR-002：订单确认页可选择已存地址或新建地址、选择物流方式，金额随运费更新。
- AC-010 ← FR-008：`POST /carts/:id/submit` 后触发 `order.submitted` 事件；`order.paid` 等事件按新状态机触发。

## 8. 非功能需求（NFR）

- 性能：订单确认/提交接口 P95 < 500ms；购物车读写 P95 < 300ms。
- 安全：Cart 归属校验（user_id 或 token）；Order 提交后不可篡改（服务端重算金额）；沿用 `require_authentication!` + 前置校验（P8）。
- 兼容：存量数据/旧接口可用；SDK 类型向后兼容（新增字段可选）。
- 可维护性：Cart/Order 职责单一；服务分层清晰；去掉过渡注释后文档自洽。

## 9. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 关键词 | 找到 | 结论 |
|---|---|---|---|---|
| App | `backend/app/` | order/cart 自定义 | `app/models/pallastrade/user.rb` 等 | 无购物车自定义，可在 host 扩展 |
| Core | `pallastrade_gems/pallastrade_core/app/` | Order/Cart/checkout_flow | `order.rb`、`order/checkout.rb`、`carts/*`、`orders/*` | 分表+标准状态机改造核心 |
| API | `pallastrade_gems/pallastrade_api/app/` | carts/orders/payment_combinations | `store/carts*`、`store/customer/orders_controller.rb`、`payment_combinations_controller.rb` | 购物车/订单 API 重构 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | 订单/发货/拆单 | `orders_controller.rb`、`shipments_controller.rb`、`orders_split` | 不涉及（Admin 侧兼容） |
| Storefront | `storefront/src/` | cart/checkout/Buy Now | `cart/page.tsx`、`checkout/[id]/page.tsx`、`buy-now.ts`、`CartContext` | 页面重构 |
| Platform | `platform/packages/` | sdk carts/orders | `sdk/src/types`、`store-client.ts` | SDK 类型/方法 |

**结论**：Core+API+Storefront+SDK 需改造；Admin 保持兼容；存量数据不迁移。

## 10. 测试计划

- 后端 RSpec：
  - `Cart` 模型（状态机/归属/勾选）、`CartItem`。
  - `Carts::Submit`（快照/金额重算/库存/Cart converted/幂等/并发）。
  - `Order` 标准状态机（各转换 + 非法转换）。
  - Store API request specs（购物车 CRUD、订单确认、submit、Checkout）。
  - 兼容：存量状态读取（complete→completed 视图）。
- 前端 Vitest：
  - 购物车勾选/全选/删除；订单确认表单（地址/物流/金额）；Checkout 只读；Buy Now 跳转。
- E2E（dev 浏览器）：新购物车 → 订单确认 → 提交 → Checkout 4242 卡支付 → 完成页。

## 11. 文档同步清单

- [ ] `docs/prd/README.md` 索引
- [ ] `docs/design/order-flow-redesign.md`（已含，P1 落地标注）
- [ ] `ai/skills/pallastrade-checkout/SKILL.md`（状态机/流程更新 + 去 5.x/6.0 表述）
- [ ] `ai/skills/pallastrade-data-model/SKILL.md`（Cart/Order 模型）
- [ ] `ai/skills/pallastrade-storefront/SKILL.md`（页面/组件）
- [ ] `ai/skills/pallastrade-api-v3/SKILL.md`（API）
- [ ] `ai/skills/pallastrade-events-webhooks/SKILL.md`（事件）
- [ ] `backend/public/api-docs/store.yaml` + `platform/docs/api-reference/`（generated:check）
- [ ] `harness/scenarios/scenarios.json`（如涉及 Skill 变更）

## 12. 风险与开放问题

- **R1**：Cart/Order 分表涉及大量现有服务/控制器迁移（Carts::*、Checkout::*、CartResolvable、弃单恢复），改动面大，需分步实施 + 测试覆盖。
- **R2**：存量数据不处理 → 旧 `checkout/[cartId]`（针对旧 cart 态订单）需保留兼容路径；新旧 Cart 序列化结构不同，需评估灰度。
- **R3**：订单状态机语义变更影响事件/Webhook 消费者（邮件、ERP、弃单恢复），需同步。
- **R4**：库存锁定时机（提交 vs 支付，`reserve_stock_on` preference）在分表后需明确。
- **R5**：`Checkout::Advance/Next` 的购物车段移除后，Admin 代下单/拆单等流程对新状态机的适配。
- **O1**：`state` 列保留旧值兼容，还是新流程用 `status` 表达、`state` 逐步废弃？倾向：新订单用 `state=pending/paid/...`，旧值读取映射。
- **O2**：Buy Now 是否新建单商品 Cart（走完整确认）还是直接创建 Order？倾向：新建 Cart 走完整确认（符合"Buy Now 进入订单确认流程"）。
