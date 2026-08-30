# RESEARCH-20260830-下单链路规范化统一化（阿里国际站参考）

> 日期：2026-08-30 ｜ 类型：研究/方案 ｜ 任务：TASK-20260830145503-9644b34d ｜ Gate：GATE-2026-08-30T14-55-15
> 范围：只读分析，不涉及代码改动；本文档输出「现状 → 差距 → 目标架构 → 分阶段改造方案」

---

## 1. 目标定义

用户要求把**用户下单链路**整体规范化、统一化，覆盖三个入口场景：

| 场景 | 入口 | 期望流程 |
|---|---|---|
| **A** | cart 场景（购物车 → 结算） | 点击 checkout → **下单页面（同场景 A）** → 支付 → 支付完成/失败/其它 |
| **B** | viewcart / shopping cart 场景（购物车页勾选商品） | 选中商品 → **下单页面（同场景 A）** → 支付 → 完成/失败/其它 |
| **C** | 个人中心 Order 模块 | 选择订单 → 点击 pay now → **收银台弹窗**（选支付方式 + 显示表单组件）→ 完成/失败/其它 |

**重要约束：**
1. 场景 A/B 的下单页面**同一个页面**，**大布局左右分栏**：
   - **左侧**：订单基础信息 = 收件地址信息 + 商品信息 + 支付方式选择 + 物流方式 + Pay Now 按钮
   - **右侧**：订单小结
2. 场景 C 点击 pay now 后**弹窗**显示收银台（选择支付方式、显示支付表单组件），非跳页。
3. 参考**阿里巴巴国际站**流程与逻辑，包括**合并支付、拆单**。
4. 注意前后台、数据结构、**父子单结构**、正逆向流程。

---

## 2. 现状盘点（跨层搜索结果）

### 2.1 前端路由与页面现状

| 路由 | 布局组 | 现状 |
|---|---|---|
| `/cart` | (storefront) | 新购物车页：勾选/全选/删除/数量；右侧金额小结；「去结算」→ checkout-info |
| `/checkout-info/[cartId]` | (storefront) | **独立订单确认页**：左 2/3 = email+收件(AddressFormFields)+物流(radio)；右 1/3 = 商品/金额预览+「提交订单」 |
| `/checkout/[id]` | (checkout) | 按前缀分流：`or_` → `OrderPaymentContent` 纯支付页；其它 → legacy 一页式 |
| `/combined-payment/[id]` | (checkout) | 合并支付收银台：**居中单栏两步骤**（收货 → 商品+支付） |
| `/account/orders` | (storefront) | 列表 + 顶部 `OrderCombinedPay` 勾选区（单笔→/checkout/[or_id]；多笔→/combined-payment） |
| `/account/orders/[id]` | (storefront) | 订单详情：**无 pay now 入口**（仅只读 PaymentInfo） |
| `/confirm-payment/[id]`、`/order-placed/[id]` | (checkout) | 离站回跳 / 完成页 |

### 2.2 后端服务链路（已实现且稳定）

- `Carts::Create / Update / UpsertItems / Submit / Complete`（新 Cart 实体标准流程）
- `Payments::PaymentCombinations::{Create, Complete}` + `PaymentSplit` + `CombinationSettleJob` 补偿
- `Orders::Splitter / ManualSplit / AutoSplit`（拆单引擎，flag 灰度默认关）
- 标准状态机 `pending → paid → processing → shipped → completed`（ADDITIVE，与 legacy 共存）+ 逆向 `cancel/refund/return`
- 支付三入口幂等：前端回调 / Stripe webhook / confirm_payments，统一经 `Carts::Complete`

### 2.3 数据结构

- **Cart**（`pallastrade_carts`，`cart_` 前缀）：极简，无金额/支付/履约；`cart_items.selected` 表达勾选范围
- **Order**（`pallastrade_orders`，`or_` 前缀）：完整电商字段 + `cart_id`/`submitted_at`/`parent_id`/`split_from_id`/`payment_combination_id`
- **PaymentCombination** + **PaymentSplit**：合并支付载体与分摊记账

---

## 3. 差距分析（现状 vs 目标）

| # | 目标 | 现状 | 结论 |
|---|---|---|---|
| G1 | A/B 同一页面左右布局 | A/B 被拆成两个独立页：`checkout-info`（确认：地址+物流+提交）→ `checkout`（支付：支付方式+pay now）；确认页**无支付方式与 pay now**；商品预览在**右侧小结**而非左侧 | ❌ 未实现 |
| G2 | 场景 C pay now → **弹窗收银台** | 单笔跳页 `/checkout/[or_id]`、多笔跳页 `/combined-payment/[pcom_id]`；**全库无支付弹窗组件** | ❌ 未实现 |
| G3 | 参考阿里国际站（合并支付、拆单） | 合并支付/拆单后端与页面版收银台已实现；`PaymentSection`（`PaymentSectionHandle.submit`）可复用为弹窗核心 | ⚠️ 后端 ✅、弹窗形态 ❌ |
| G4 | 前后台/数据结构/父子单/正逆向一致 | Cart/Order 分表、父子单（`parent_id`/`split_from_id`）、正逆向状态机均已就绪 | ✅ 底层支撑完备 |
| G5 | 场景 B 独立入口 | 实际 A/B 共用 `/cart`（无独立 viewcart 页） | ⚠️ 用户视角 A/B 分开，当前实现等价（B 的"勾选商品"即 `/cart` 的 selected） |

**风险点（现状隐患）：**
- `CartDrawer`（迷你购物车）走 **legacy 流**（`lib/data/cart.ts` + `/checkout/${cart.id}` legacy 一页式），与新流程不一致 → 统一化时必须一并收敛
- `checkout/[id]` 的 `or_` 前缀判断同时命中标准订单与 legacy 购物车态订单（存量数据歧义）
- 合并支付收银台是居中单栏，非左右布局、非弹窗

---

## 4. 目标架构设计（阿里国际站参考）

### 4.1 统一下单页（场景 A/B 共用）—— `UnifiedCheckout`

```
路由：/checkout/[id]  （id 可为 cart_ 前缀购物车 或 or_ 前缀待支付订单）
布局：左右分栏（lg:grid-cols-3）
┌─────────────────────────────────────────────┬──────────────────────┐
│ 左侧 2/3（订单基础信息，同一页全部可编辑）      │ 右侧 1/3（订单小结）  │
│  ① 收件地址信息（AddressFormFields）           │  商品清单 + 金额明细  │
│  ② 商品信息（行项目列表）                      │  Subtotal            │
│  ③ 物流方式（DeliveryMethodSection radio）     │  Shipping            │
│  ④ 支付方式选择（PaymentSection 内嵌）          │  Tax / 优惠           │
│  ⑤ Pay Now 按钮（提交整单）                    │  Total               │
└─────────────────────────────────────────────┴──────────────────────┘
```

- **入口 A**：`/cart`「去结算」→ `/checkout/[cart_id]`（购物车 ID，直接进统一下单页，不再经 checkout-info）
- **入口 B**：购物车页勾选商品后「结算」→ 同上 `/checkout/[cart_id]`（selected 已由勾选确定）
- **后端语义**：购物车 ID 进入时，页面内完成 ①地址/③物流/④支付方式 的**保存（PATCH cart）+ 提交（Carts::Submit 建 Order）** 一次性完成；提交后同页无缝切换为订单支付态（or_），用户无需跳页
- 这是**阿里式"确认+支付同页"**：所有信息一屏确认，Pay Now 即提交并进入支付

### 4.2 个人中心收银台弹窗（场景 C）—— `PaymentCheckoutModal`

```
个人中心（订单列表 / 订单详情 / 合并支付入口）
  └─ 点击「Pay now」
       └─ <Dialog> 收银台弹窗
            ├─ 选择支付方式（PaymentSection radio：Stripe/Check/...）
            ├─ 支付表单组件（StripePaymentForm PaymentElement / 非会话方式按钮）
            └─ 确认支付 → 成功(跳 order-placed 或就地刷新) / 失败(显示错误+重试) / 其它
```

- **单笔**：选 1 笔订单 → 弹窗（复用 `PaymentSection`，`PaymentSectionHandle.submit` 驱动）
- **多笔**：选 2+ 笔 → 先 `createPaymentCombination` 创建组合 → 弹窗显示组合金额 + 各单分摊 → 支付（复用现有 `Complete` 幂等链路）
- **订单详情页**补「Pay Now」按钮（当前缺失），同样打开弹窗
- 弹窗复用 `PaymentSection`/`StripePaymentForm`，避免与统一下单页逻辑重复

### 4.3 支付结果（完成/失败/其它）统一

| 结果 | 处理 |
|---|---|
| 成功 | `/order-placed/[orderId]`（或弹窗内成功态→跳转）；合并支付各成员 `payment_state=paid` |
| 失败/取消 | 就地显示错误/重试；订单保持 `balance_due`（可再进入 C 流程）；`PaymentSession` failed/expired 幂等 |
| 3DS/离站 | 复用 `/confirm-payment/[id]` 回跳中转 |
| Webhook 幂等 | `Carts::Complete` 三入口统一，重复回调短路 |

### 4.4 数据结构 / 父子单 / 正逆向 影响评估

- **无破坏性 schema 变更**：Cart/Order 分表、`parent_id`/`split_from_id`/`payment_combination_id` 已存在
- **统一下单页** 需要：购物车进入时一页完成「保存+提交」——`Carts::Submit` 已是幂等转换（active→converted），页面在提交后需将 `cart_` 状态切换到 `or_` 订单态（前端用返回的 order 重新渲染）
- **拆单**：保持 flag 灰度（`auto_split_orders`），统一下单页展示以 Order 为准；合并支付弹窗展示各成员分摊（`PaymentSplit`）
- **逆向**：退/换货前端入口仍待补（后端 P7 就绪）——属于后续阶段，不在本方案首期
- **遗留收敛**：`CartDrawer` legacy 结算链路必须切换为新流程，否则统一化后存在双入口不一致

---

## 5. 分阶段改造方案

### 阶段 1（前端统一下单页，核心）
1. 新建/改造 `/checkout/[id]` 为**统一下单页 `UnifiedCheckout`**（左右布局，左：地址+商品+物流+支付方式+Pay Now；右：小结）
2. `cart_` 前缀进入 → 页面内联保存+提交（`updateShoppingCartDetails` + `submitCartAndGoToCheckout`），提交后无缝切换 `or_` 支付态
3. `or_` 前缀进入（场景 C 单笔旧入口保留兼容）→ 直接支付态（只读地址/物流或允许编辑视配置）
4. `checkout-info/[cartId]` 页废弃/重定向到统一下单页（或保留为只读确认预览）
5. **收敛 `CartDrawer`** 结算入口指向 `/checkout/[cart_id]`（新流程）

### 阶段 2（收银台弹窗，场景 C）
1. 新建 `PaymentCheckoutModal`（Dialog + `PaymentSection` 复用）
2. 个人中心订单列表 `OrderCombinedPay` 单笔/多笔统一改为**打开弹窗**（多笔先建组合）
3. 订单详情页补「Pay Now」按钮 → 打开弹窗
4. 弹窗内复用 `StripePaymentForm`；合并支付展示组合金额+各单分摊

### 阶段 3（一致性收尾 + 逆向入口）
1. `checkout/[id]` legacy 分支清理（存量数据迁移策略确认后移除）
2. 统一下单页与弹窗共享「支付方式+表单」组件（提取 `PaymentMethodSelector`）
3. 逆向流程（退货/退款申请）前端入口补建（后端已就绪）
4. 知识同步：`pallastrade-checkout` / `pallastrade-storefront` SKILL + 场景库 + API 文档

---

## 6. 关键决策点（需产品确认）

1. **统一下单页是否保留「提交订单」前置步骤**：阿里式是"确认+支付同页一次提交"；当前是"checkout-info 提交 → checkout 支付"两步。建议：购物车进入 = 一页内联提交+支付；或保留可配置。
2. **场景 C 单笔支付是否允许编辑地址/物流**：目标①只约束 A/B；C 弹窗建议只读（复用订单已有信息），减少复杂度。
3. **`CartDrawer` legacy 收敛**：是否同时把迷你购物车切换为新 Cart 实体（涉及 `CartContext`/`lib/data/cart.ts` 大改），或首期仅改结算跳转。
4. **合并支付弹窗内是否展示各单收货地址编辑**：当前合并流程有独立"收货步骤"（逐单编辑）；弹窗化后建议保留编辑入口或降级为只读+跳转编辑。
5. **拆单 flag**：维持 `auto_split_orders` 灰度默认关，统一化不改变其语义。

---

## 7. 结论

- **底层（后端/数据结构/父子单/正逆向）已完备**，无需重构；主要工作量在前端**页面/交互统一化**。
- **阶段 1**（统一下单页 A/B）+ **阶段 2**（收银台弹窗 C）即可覆盖用户三个场景目标，是本次需求的核心。
- 阶段 3 为一致性收尾与逆向补齐，可排期后续。
- 建议先出 PRD（`docs/prd/`）对阶段 1/2 做细化（FR/AC/跨层搜索/测试计划），经用户确认后进入 gate 实施。
