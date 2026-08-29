# REQ-20260830-order-flow-standard-ecommerce-p1

> 关联 PRD：`docs/prd/checkout/PRD-20260829-checkout-订单流程标准电商改造-购物车与订单分表-订单确认-提交订单-checkout纯支付-自有化去spree化.md`（status: approved）
> 关联 Task：TASK-20260829160454-a104cb71 ｜ Gate：GATE-2026-08-29T16-05-59

## Step 0：跨层搜索（6 层强制）

| 层 | 搜索路径 | 关键词 | 找到 | 是否满足需求 |
|---|---|---|---|---|
| App — models | `backend/app/` | cart/order 自定义 | `app/models/pallastrade/user.rb` | 无购物车自定义；`user_methods` 有 `has_many :carts`（Order） |
| Core — models | `pallastrade_core/app/models/pallastrade/` | Order/Cart/checkout_flow | `order.rb`(1369行)、`order/checkout.rb`(357行)、`line_item.rb` | Order 同表承载 cart+订单；无 Cart 模型；分表改造核心 |
| Core — services | `pallastrade_core/app/services/pallastrade/carts/` | Carts::* | `create/update/upsert_items/complete/auto_split.rb` | 全部操作 Order（同表）；需迁移到 Cart + 新增 Submit |
| API — controllers | `pallastrade_api/app/controllers/.../store/` | carts/orders/payment_sessions | `carts_controller.rb`(184)、`carts/items_controller.rb`、`payment_sessions_controller.rb` | 购物车 API 基于 Order；需重写为新 Cart + submit 路由 |
| Admin — controllers | `pallastrade_admin/app/controllers/` | 订单/发货 | `orders_controller.rb`、`payments_controller.rb` | 仅 `payments_controller L91` 用 `can_go_to_state?('payment')`；不依赖 cart state（兼容） |
| Storefront | `storefront/src/` | cart/checkout/buy-now | `cart/page.tsx`、`checkout/[id]/page.tsx`、`lib/data/buy-now.ts`、`CartContext.tsx` | 无勾选机制；checkout 含地址表单；Buy Now 建独立 Order-cart；需改造 |
| Platform | `platform/packages/sdk/` | Cart/Order/carts | `src/store-client.ts`、`src/types` | `carts.complete` 即提交；无 submit/selected；需扩展 SDK |

### 搜索结论

- **Core + API + Storefront + SDK 需改造**；Admin 保持兼容（不依赖 cart state）。
- 关键架构事实：`PallasTrade::Cart` 目前是 **Spree 遗留服务模块**（AddItem 等 13 个，DI 注册 `cart_*_service`）；`paid?/shipped?/completed?` 在 Order 已有计算语义方法；支付 webhook 统一经 `Carts::Complete`。
- 存量数据不处理（用户确认）：/carts 路由切换为新 Cart；legacy Order-based cart 不可达可接受。

## Step 1：Skill 文件咨询

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树：Settings→Events→Dependencies→Admin→Generators→Decorators→Extensions；行为变更优先 Events/Subscriber 而非 model 回调；cart 计算可经 DI 换服务 |
| `pallastrade-checkout/SKILL.md` | ✅ 已读 | Order 状态机 cart→address→…→complete；`state`(checkout) vs `status`(draft/placed/canceled) 双维度；`Carts::Complete` 完成入口；`cart_recalculate_service` 链路；事件 `order.completed` |
| `pallastrade-data-model/SKILL.md` | ✅ 已读 | `PallasTrade::Order` 既当购物车又当订单（`state='cart'`）；`PrefixedId` 约定；`PallasTrade::Current` 上下文；`publishes_lifecycle_events` 事件机制 |
| `pallastrade-prd/SKILL.md` | ✅ 已读 | PRD 驱动闭环：task start→brain→risk→gate→REQ→实施→evidence→knowledge→finish；PRD approved 后实施 |
| `pallastrade-api-v3/SKILL.md` | 按需（实施时读） | 序列化器注册在 `api/dependencies.rb`；`PallasTrade.api.x_serializer` |
| `pallastrade-storefront/SKILL.md` | 按需（前端实施时读） | 页面/组件/SDK 约定 |
| `pallastrade-events-webhooks/SKILL.md` | 按需（事件同步时读） | 事件 payload 约定 |
| `pallastrade-testing/SKILL.md` | 按需（测试时读） | RSpec 约定 |

## 需求标题

订单流程标准电商改造 P1：购物车与订单分表、订单确认页、提交订单节点、Checkout 纯支付、Buy Now 走订单确认、自有化去 Spree 化（涉及订单/购物车部分）

## 任务类型

新功能 / 架构改造（去 Spree 化）

## 需求描述

1. 新建 `pallastrade_carts` + `cart_items` 表，`PallasTrade::Cart` 模型（极简状态机 active→converted/abandoned）。
2. `PallasTrade::Order` 增加标准状态机（pending→paid→processing→shipped→completed，additive 兼容 legacy states）。
3. `POST /api/v3/store/carts/:id/submit`：提交订单 → 从 Cart 快照创建 Order（pending）+ Cart converted。
4. 购物车页勾选/删除/数量；订单确认页（收件+物流+预览）；Checkout 纯支付页；Buy Now 走订单确认。
5. 支付闭环：`Carts::Complete` 兼容 standard flow（pay! + finalize!）。
6. 自有化清理：本次触碰的订单/购物车相关 naming bridge / deprecation 注释。

## 技术方案（关键决策）

| 决策 | 方案 | 理由 |
|---|---|---|
| `PallasTrade::Cart` 命名冲突 | legacy `PallasTrade::Cart` 服务模块 13 文件 `module Cart` → `class Cart`（reopen 模型类，无 superclass），沿用 `Order::*` 嵌套模式 | DI 字符串/引用零改动；符合代码库既有模式 |
| Order 状态机 | additive 添加标准状态+事件；保留 legacy states | 存量数据不迁移；`paid?/shipped?/completed?` 已有计算语义覆盖生成谓词（安全） |
| 关联 | 新增 `store.shopping_carts`/`user.shopping_carts` → Cart；保留 `carts` → Order | 零破坏 legacy |
| 解析 | CartResolvable 新增 `find_shopping_cart(/)`；保留 `find_cart(/)` | 新旧 flow 并行 |
| 序列化 | 新 `ShoppingCartSerializer` + `CartItemSerializer`；保留旧 CartSerializer | 旧 storefront 过渡期兼容 |
| 支付闭环 | `Carts::Complete` 按 `standard_flow?` 分支：新订单 `pay!`+`finalize!`；legacy 不变 | webhook/Stripe confirm 入口统一 |

## 风险点

- **R1**：Order 状态机新增状态与 legacy `next` 流并存——新增状态不加入 checkout_steps，legacy 流不受影响；`standard_flow?` 隔离。
- **R2**：`Carts::Complete` 分支逻辑——必须对新/旧订单都幂等（重复 webhook）。
- **R3**：/carts 路由切换后 legacy Order-cart 不可达（存量数据不处理，可接受）。
- **R4**：`allow_cancel?` 对 pending 订单需扩展（否则无法取消待支付订单）。
- **R5**：库存锁定时机（P8 `stock_reservation_strategy`）——Submit 时需按策略处理。
- **Critical 任务**：需 `harness recovery create|verify` 人工恢复计划。

## 测试计划

- 后端 RSpec：`Cart`/`CartItem` 模型、`Carts::Submit`、Order 标准状态机、request specs（cart CRUD/items/submit）、`Carts::Complete` 双流。
- Storefront Vitest：勾选/全选/删除；订单确认表单；Checkout 只读。
- E2E（dev 浏览器）：新购物车→订单确认→提交→Checkout 支付→完成页。

## 文档同步清单

- [ ] `docs/prd/README.md` 索引（PRD 状态 approved）
- [ ] `ai/skills/pallastrade-checkout/SKILL.md`（标准状态机/Submit 更新）
- [ ] `ai/skills/pallastrade-data-model/SKILL.md`（Cart 模型）
- [ ] `ai/skills/pallastrade-storefront/SKILL.md`（页面）
- [ ] `ai/skills/pallastrade-api-v3/SKILL.md`（API）
- [ ] `backend/public/api-docs/store.yaml`（generated:check）
- [ ] `harness/scenarios/scenarios.json`（如涉 Skill 变更）
