# REQ-20260914-checkout-cart-gift-cards-canonical — cart_ 礼品卡端点 canonical 化（收敛切片 1）

> 关联 PRD：`docs/prd/checkout/PRD-20260914-checkout-cart-gift-cards-canonical.md`
> 来源：research §9.3 P2「legacy 六端点收敛」；用户指令「实施收敛」
> Task：`TASK-20260914115824-3eab8fb7`；Gate：`GATE-2026-09-14T12-01-38`（feature）
> 产出：`cart_` 礼品卡端点可用（修 404）+ 提交兑现 + legacy 观测

## Step 0：跨层搜索（已执行）

| 层 | 路径 | 结果 |
|---|---|---|
| App | `backend/app/` | 无实现 |
| Core | `pallastrade_core/app/` | `order/gift_card.rb`（`apply_gift_card` → `gift_card_apply_service`，**创建 store-credit payment 并占用余额**）、`promotion_handler/coupon.rb`（礼品卡分支已存在）、`PallasTrade::Cart` **无礼品卡建模** |
| API | `pallastrade_api/app/` | `store/carts/gift_cards_controller.rb`（`find_cart!` → **404 根因**）、`shopping_cart_serializer.rb`（无 `gift_card` 字段） |
| Admin | `pallastrade_admin/app/` | admin 订单礼品卡走 Order 侧 API（不受影响） |
| Storefront | `storefront/src/` | BFF `coupon` 路由 + `CouponCode.tsx` 调 `carts.giftCards.*`（受益方，零改动） |
| Platform | `platform/packages/sdk/` | `carts.giftCards.apply/remove` 已存在 |

## Step 1：Skill 咨询

| Skill | 状态 | 关键结论 |
|---|---|---|
| `pallastrade-payments`（域） | ✅ 已读 | 礼品卡 = 资金手段：`order.apply_gift_card` 经 `gift_card_apply_service` 建 store-credit payment 并写 `amount_used`；`gift_card_total` 由该 payment 汇总；**资金只存在于 Order/Transaction 侧** |
| `pallastrade-api-v3`（域） | ✅ 已读 | Store API 前缀 id 契约 + 错误信封；`PromotionHandler::Coupon` 的礼品卡分支：`gift_cards_enabled? && load_gift_card_code` → `order.apply_gift_card`，错误码 `gift_card_expired` / `gift_card_already_redeemed` |
| `pallastrade-storefront`（域） | ✅ 已读 | BFF `kind: gift_card` 与 `CouponCode` 交互（移除需 gift_card_id） |

## 决策记录（ADR 摘要）

1. **车阶段只承载意图**（`private_metadata['gift_card_code']`）：canonical 购物车无 payments，车阶段**零资金副作用**；占用在提交生成 Order 时经既有 `PromotionHandler::Coupon` 礼品卡分支 `order.apply_gift_card` 完成（不新写资金逻辑）。
2. **提交时失效即失败**（不静默按原价下单），与 PRD-4 优惠码一致。
3. **双解析 + legacy 观测**（`[legacy-gift-cards]`），legacy 行为零变化。
4. **序列化暴露 `gift_card`**（`code` + `display_amount_remaining`）供 UI 展示已应用状态；不改 `amount_due` 车阶段语义（UI 文案需说明"提交时扣除"）。
5. **范围外**：`store_credits` / `payments` / `payment_sessions` / `fulfillments` 四端点另切片。

## 实施结果

| 项 | 结果 |
|---|---|
| FR-001 双解析 + 观测 | ✅ `gift_cards_controller.rb#find_cart_or_shopping_cart!` + `[legacy-gift-cards]` |
| FR-002/003 应用/移除服务 | ✅ `Carts::ApplyGiftCard` / `Carts::RemoveGiftCard`（`private_metadata['gift_card_code']`，零资金副作用） |
| FR-004 提交兑现（失败不落单） | ✅ `Carts::Submit#apply_gift_card!` → `order.apply_gift_card`（经同一校验口径）；**修复（GATE-2026-09-14T12-44-52）**：改为金额管线之后兑现（读得到最终 `total`）+ 零额守卫 |
| FR-005 序列化 `gift_card` | ✅ `ShoppingCartSerializer`（`code` + `display_amount_remaining`） |
| FR-006 知识同步 | ✅ OpenAPI + Skill×2 + GS-117 + research §9.3 + 契约产物重生成 |

## 验证与证据

| 证据 | 结果 |
|---|---|
| AC-001/002/003/005/006 请求规格 | ✅ `spec/requests/api/v3/store/carts/gift_cards_spec.rb` 9 examples 0 failures |
| AC-002/003 服务规格 | ✅ `spec/services/pallastrade/carts/apply_gift_card_spec.rb` 5 examples 0 failures |
| AC-004 提交规格 | ✅ `spec/services/pallastrade/carts/submit_spec.rb`（2 新例） |
| 验证器 | ✅ `p1-order-flow-rspec`（已扩入两个新 spec 文件）→ gate `verify-test` 证据 |
| 契约产物 | ✅ `typelizer:generate` + `api:docs:schemas`（`ShoppingCart.gift_card`）+ platform 副本同步 |
| dev 实测 | ✅ 2026-09-14（部署 `87cf3946`）：未知码 → 404 `gift_card_not_found`（修复前 `cart_not_found`）；真实码 `GC-DEV-SMOKE-1` → 201 且载荷 `gift_card.code` + `display_amount_remaining`；移除 → 200；DB `private_metadata={"gift_card_code"…}` 且礼品卡 `amount_used=0.0`/`amount_authorized=0.0`（车阶段零资金副作用） |
