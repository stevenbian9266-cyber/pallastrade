# PRD-20260903-checkout-chk-p1-1-order-checkout-application-layer-checkoutview

| 元数据 | 值 |
|---|---|
| 状态 | implementing |
| 创建日期 | 2026-09-03 |
| 来源 | CHK-P1-1 Order Checkout Application Layer + CheckoutView（Order-centric Checkout Consolidation，用户评审通过 P1-0 审计后授权） |
| 分类 | checkout |
| 关联 Skill | pallastrade-checkout / pallastrade-customization / pallastrade-api-v3 |
| 关联 REQ | REQ-20260903-chk-p1-1.md |
| 关联 PRD | 查重：与 PRD-20260830-checkout-下单链路规范化统一化 语义相邻（MERGE 建议已记录于 P1-0 审计），本 PRD 为 CHK-P1 系列首包实施件，独立编号 |
| 需求类型 | 优化迭代（后端 Checkout Application Layer + CheckoutView） |

## 1. 背景与目标

- **一句话需求**：评审通过 CHK-P1-0 审计，授权实施 CHK-P1-1：在现有 Order 域之上建立 Checkout Application Layer（编排收敛）与 Server-driven CheckoutView（单一视图），不新建 CheckoutSession/快照表/定价引擎。
- **背景**：P1-0 审计证实——金额/商品/物流/税已由 Order + OrderUpdater 权威承载；前端（UnifiedCheckout/CheckoutPageContent/OrderPaymentContent）仍在**多个后端响应间自行拼装金额与状态**（多副本 + 裸 fetch BFF），无单一 Server-driven Checkout 视图，也无统一的"一次结算意图"读模型。
- **目标**：把 Checkout 的读取收敛为一个服务端生成的 `CheckoutView`（由 Order 及已有关联投影），并建立 `PallasTrade::OrderCheckout` 应用层命名空间，为 P1-2（版本/失效/过期）、P1-3（Readiness/Snapshot）、P1-4（前端收敛）提供稳定基座。**不改支付链、不改状态机、不加表**。
- **成功指标**：新增服务层 100% 单测；Order 域既有回归（p1-order-flow / P0 基线）全绿；无 DB migration；无 Storefront 行为回归（本包不改前端）。

## 2. 用户故事 / 场景

- 作为后端调用方（未来 Storefront/Internal），我希望用 `order_id` 一次取得**完整且单一权威**的 Checkout 视图（商品/联系/地址/物流/优惠/税/价格/币种/状态），以便前端不再自行拼装多份响应。
- 作为 Store API，我希望更新订单联系/收货信息后能拿到**同一视图的最新投影**，以便 mutation 后立即渲染一致状态。
- 场景：
  - 正常：`or_` 订单（state=pending）生成完整 CheckoutView。
  - 边界：legacy 在途订单（state=cart/address…）仍可投影（View 兼容输出，不含标准字段则置空/降级）。
  - 边界：父子单/组合支付成员订单投影不报错（金额用 order 自身 amount_due 语义，聚合在既有 serializer 层处理，本包不复制）。
  - 异常：订单不存在/无权访问 → 既有 404/403 语义（复用 order_resolvable 访问控制）。
  - 异常：order 已 complete → View 仍可生成（status=complete），readiness/支付字段由后续包约束。

## 3. 功能需求（FR）

- FR-101：新增 `PallasTrade::OrderCheckout::View` 服务 `call(order:)` → 返回 CheckoutView 值对象（DTO，非 AR 模型）。投影数据全部来自 `order` 及既有关联（line_items/addresses/email/shipments+selected_shipping_rate/调整与金额列），**禁止新查询语义或复制计算**（金额直接读 order 权威列）。
- FR-102：CheckoutView DTO 至少含字段契约：`order_id`、`status`（order.state/status 现状）、`items`（行项目：variant/name/quantity/unit 金额/行小计/币种）、`contact`（email）、`shipping_address`/`billing_address`（现状地址，缺失为 nil）、`shipping`（可用物流选项 + 已选 method/rate + 金额）、`discounts`/`taxes`（adjustments 投影，金额读 order 权威列）、`price`（item_total/shipment_total/discount 合计/tax 合计/total/amount_due/currency）、`version`（P1-1 占位 = order.updated_at.to_i，注释标明 P1-2 正式语义）、`expires_at`（nil 占位，P1-2）、`ready`/`missing_requirements`（P1-1 基础判断占位，P1-3 正式化）。
- FR-103：新增 `PallasTrade::OrderCheckout::UpdateAddress`（WRAP）`call(order:, params:)` → 复用 `PallasTrade::Orders::UpdateShippingAddress` 的地址赋值/sync_shipments 逻辑 + `Orders::UpdateContactInformation`（email），返回最新 CheckoutView。仅允许未完成（!completed?）订单；已下单未支付订单沿用现语义（不重置状态机）。为 P1-2 invalidation 预留 `after_update` 扩展点（注释 + 空实现）。
- FR-104：API 新增只读端点 `GET /api/v3/store/orders/:id/checkout` → `{ data: { id, type:'checkout', attributes: <CheckoutView> } }`，访问控制复用订单 token/customer 既有解析（order_resolvable），store 隔离不破坏。
- FR-105：serializer（`PallasTrade::Api::V3::Store::CheckoutSerializer` 或等价命名）输出 View 为 v3 契约（prefixed id、decimal→string、hide_prices 门控金额照既有规则）。
- FR-106：所有新代码遵循现有 ServiceModule::Base（success/failure）与 gem 内 `PALLAS-CUSTOM:` 注释约定；命名遵循核心服务现有 convention。

## 4. 非功能需求（NFR）

- 无 DB migration；不改 Order/Payment 模型结构；不加表。
- 不改 PaymentSession/Payment/Stripe/Carts::Complete；P0 支付回归基线保持全绿。
- 只读端点不产生副作用（无写）；UpdateAddress 与现有服务事务语义一致。
- CheckoutView 投影 N+1 可控（预加载 line_items/addresses/shipments.rates/adjustments）。
- 兼容 legacy 在途订单（不假设 state=pending）。
- 本包不触碰 Storefront 渲染与 SDK（防 scope creep，前端收敛归 P1-4）。

## 5. 验收标准（AC，与测试一一映射）

- AC-101 ← FR-101：`OrderCheckout::View.call(order:)` 返回结构完整 DTO，金额/地址/行项目与 order 权威列一致（spec 断言逐字段）。
- AC-102 ← FR-101：state=pending 标准订单可投影；complete 订单可投影（status=complete）；父子单成员/组合成员订单投影不抛错。
- AC-103 ← FR-102：DTO 字段契约存在且类型正确（金额 string/子单位语义遵守现有 serializer 规则；id 使用 prefixed）。
- AC-104 ← FR-103：`OrderCheckout::UpdateAddress` 更新 ship/bill/email 后返回的 View 反映新值；已 complete 订单拒绝更新；不重置 legacy 状态机（回归断言）。
- AC-105 ← FR-104：`GET /store/orders/:id/checkout` 200 返回 v3 信封；无权限/不存在 404/403；不改变订单任何列。
- AC-106 ← FR-105：hide_prices 门控与金额序列化遵守 `store.yaml` 既有 Cart/Order 语义（不引入新金额格式）。
- AC-107（回归）：既有 order-flow/P0 回归 spec 全绿；无 migration 产生（`git status` 无 db 文件）。

## 6. 跨层搜索记录（6 层，CHK-P1-0 审计已全量执行，此处固化结论）

| 层 | 路径 | 搜索关键词 | 找到的文件（代表） | 是否满足 |
|---|---|---|---|---|
| App | `backend/app/` | checkout/order 服务 | host 无相关代码（仅 user/admin_user 模型） | N/A |
| Core | `pallastrade_core/app/` | Order/OrderUpdater/Carts::Submit/Orders::* | `order.rb`、`order_updater.rb`、`services/orders/{update_shipping_address,update_contact_information}.rb`、`services/carts/submit.rb`、`models/order/checkout.rb` | ✅ WRAP 基座已存在 |
| API | `pallastrade_api/app/` | store orders controllers/serializers | `store/orders/payment_sessions_controller.rb`、`customer/orders/shipping_address_controller.rb`、`order_serializer.rb`、`cart_serializer.rb`、`middleware/request_id.rb` | ✅ 复用序列化/访问控制模式 |
| Admin | `pallastrade_admin/app/` | checkout_advance 等 | admin orders 控制器（advance 依赖，勿动） | N/A（不触碰） |
| Storefront | `storefront/src/` | checkout view/multi-source | `CheckoutPageContent.tsx`/`UnifiedCheckout.tsx`/`lib/data/checkout.ts`（多副本+裸 fetch） | 前端收敛归 P1-4，本包只读不改 |
| Platform | `platform/packages/` | sdk checkout types | SDK 无 checkout view 类型 | 本包不加 SDK（P1-4） |

**结论**：Order 域已有全部事实与修改入口；本包新增"只读投影 + WRAP 编排 + 读端点"，**无重复实现**。防重复：不建新聚合、不复制 OrderUpdater 公式、不动 legacy 状态机。

## 7. 技术影响

- 新增（core）：`app/services/pallastrade/order_checkout/view.rb`、`update_address.rb`、`view.rb`（值对象/结构）。
- 新增（api）：`serializers/pallastrade/api/v3/store/checkout_serializer.rb`（或等价）；`controllers/pallastrade/api/v3/store/orders/checkout_controller.rb`（GET show）；`config/routes.rb` 一条只读路由。
- 修改（core）：无（若需把 address 赋值提取共享，则以模块内 private 复制现有逻辑，不做跨文件重构）。
- DB：无 migration。
- 影响面：`harness affected`（仅上述新文件 + routes）；不触碰支付/前端。
- SDK/OpenAPI：`backend/public/api-docs/store.yaml` 增补 checkout 端点 schema（若生成器可用；否则记录 R1 类待办）。

## 8. 测试计划

- 新增：`backend/spec/services/pallastrade/order_checkout/view_spec.rb`（AC-101/102/103）
- 新增：`backend/spec/services/pallastrade/order_checkout/update_address_spec.rb`（AC-104）
- 新增：`backend/spec/requests/api/v3/store/orders/checkout_controller_spec.rb`（AC-105/106）
- 回归：`p1-order-flow-rspec` + P0 基线相关 spec（AC-107）；`rubocop`；`generated:check`（预期无 drift 或按 R1 记录）。
- AC↔测试映射见上；`harness prd verify --id PRD-20260903-checkout-chk-p1-1-...`。

## 9. 文档同步清单

- [ ] `backend/public/api-docs/store.yaml`（checkout 端点）
- [ ] `ai/skills/pallastrade-checkout/SKILL.md`（OrderCheckout 层/CheckoutView 契约）
- [ ] `docs/checkout/CHK-P1-1_OrderCheckout_Application_Layer.md`（本包设计记录，供 P1-2/3 接续）
- [ ] `docs/prd/README.md` 索引
- [ ] 状态推进 approved→implementing→verifying→done

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-03 | 0.1 | 初稿（依据 CHK-P1-0 审计 + 用户授权） | AI |