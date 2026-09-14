# REQ-20260914-checkout-cart-discount-codes-canonical — cart_ 阶段优惠码 canonical 端点

> 关联 PRD：`docs/prd/checkout/PRD-20260914-checkout-cart-discount-codes-canonical.md`（implementing）
> 来源：research §9.1 P0-e / §5.1 / §11 PRD-4 行（端点方向待决策）→ 用户指令「继续」
> Task：`TASK-20260914030920-b691e727`；Gate：`GATE-2026-09-14T03-09-28`（feature）
> 产出：`cart_` 优惠码端点恢复可用（修 403）+ 提交携带优惠码（金额生效、失败即报错）+ legacy 观测

## Step 0：跨层搜索（已执行，含 dev 实测）

| 层 | 路径 | 结果 |
|---|---|---|
| App | `backend/app/` | 无宿主层实现 |
| Core | `pallastrade_core/app/` | `Order#coupon_code` 虚拟属性（L124）、`Orders::Create#apply_coupon`（L37/L139-150 权威样例）、`PromotionHandler::Coupon`（`coupon_code_not_found` / `coupon_code_expired`）、`Promotion.with_coupon_code`、`Carts::Submit` **无 coupon 处理**、`PallasTrade::Cart` **无 coupon_code 列**（有 `private_metadata`） |
| API | `pallastrade_api/app/` | `store/carts/discount_codes_controller.rb`（`find_cart!` = **403 根因**）、`CartResolvable`、`store/carts_controller.rb#find_shopping_cart_for_association`（可复用解析形态） |
| Admin | `pallastrade_admin/app/` | 不涉（范围外） |
| Storefront | `storefront/src/` | `app/api/checkout/coupon/route.ts` → `carts.discountCodes.apply/remove`（打同一 URL；**无需改动**） |
| Platform | `platform/packages/sdk/` | `carts.discountCodes.*` 已存在（无需改） |

**dev 实测（关键证据）**：`POST /api/v3/store/carts/cart_GpMUcnUYI5/discount_codes` → **403 `access_denied`**（legacy 解析器解析不到 `pallastrade_carts`）→ 确认「Coupon 坏链」为**真实线上缺陷**，非理论问题。

## Step 1：Skill 咨询

| Skill | 状态 | 关键结论 |
|---|---|---|
| `pallastrade-promotions` | ✅ 已读 | ① **应用码不消耗码**（占用在 redemption `reserve` 阶段，`coupon_code.with_lock`）；② `Promotion.with_coupon_code` 确定性查找（单码优先，否则 generated `CouponCode`）；③ 码大小写不敏感但需精确匹配；④ `multi_codes` 走 `CouponCode` 记录 |
| `pallastrade-api-v3` | ✅ 已读 | Store API 契约、前缀 id、错误信封 `{ error: { code, message } }`；参数白名单即契约 |
| `pallastrade-storefront` | ✅ 已读 | 优惠码 BFF 与服务端错误口径；Money 契约 |
| `pallastrade-prd` | ✅ 已读 | PRD → 确认 → gate → REQ → AC↔测试 → 知识同步门 |

## 决策记录（ADR 摘要）

1. **端点方向 = 双解析 canonical 端点**（`cart_` 前缀走新 ShoppingCart；否则 legacy）——storefront/SDK 零改动即恢复功能，且不破坏 legacy 调用方。
2. **码的持久化 = `cart.private_metadata['discount_code']`**（不新增列；与 billing 修复同样的"避免 schema churn"取向）。
3. **提交时码失效 → 提交失败并返回 `coupon_code_*`**（**不**静默按原价下单；与 `Orders::Create` 的"记录错误继续"不同，理由：用户显式申请折扣，静默丢弃会导致实付金额高于预期）。
4. **范围内**：carts 侧 discount_codes 双解析 + 应用/移除 + 提交携带 + 观测。**范围外**：gift_cards / store_credits 端点、`or_` 阶段 promotions 端点、后台促销管理。

## 实施结果（待实施）

| 项 | 结果 |
|---|---|
| 双解析（FR-001） | ⏳ |
| 应用/移除服务（FR-002/003） | ⏳ |
| 提交携带（FR-004） | ⏳ |
| legacy 观测（FR-005） | ⏳ |
| 契约与知识（FR-006） | ⏳ |

## 验证与证据（待实施）

| 证据 | 结果 |
|---|---|
| 请求 spec（AC-001/002/003） | ⏳ |
| 服务 spec（AC-004/005/006） | ⏳ |
| dev 实测（修复后 `cart_` 端点不再 403） | ⏳ |
| OpenAPI ×2 + Skill + 场景库（AC-007） | ⏳ |
