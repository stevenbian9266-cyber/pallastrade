# REQ-20260910-promo-batch2-discount-projection-unified

> 关联 PRD：`docs/prd/promotions/PRD-20260909-promotions-promo-batch2-discount-projection-unified.md`（approved；用户 2026-09-10 选定方案 A）
> 任务：TASK-20260910021639-706a85fc ｜ Gate：GATE-2026-09-10T02-16-46 ｜ 分支 dev @ c2f9b9d

---

## Step 0：跨层搜索结论（本会话已核实）

| 层 | 关键词 | 结论 |
|---|---|---|
| backend/app | promotion | 无宿主代码（仅生成 TS 类型）→ 无需宿主改动 |
| core | order_promotion / order_checkout view / order_updater | `OrderPromotion#amount` 未过滤 eligible（批次1 记录）；`CheckoutView#discounts` 仅 order 级调整（Finding D）；updater 三档口径已是事实（批次1 附录A） |
| api | cart/order/checkout serializer + discount serializer | Cart/Order `many :discounts`→order_promotions（每行一次 SQL sum=N+1）；CheckoutSerializer discounts=`{id,amount,currency}`(adj 行，仅 order 级) |
| admin | order serializer/views | Admin Order（expand discounts）走 api serializer；Rails 页面显示 order_promotions 摘要，不改 UI |
| storefront | discounts | 仅消费 `cart.discounts`（CouponCode/GTM）与 order.discounts；**不消费 Checkout API discounts**（方案 A 影响面小） |
| platform | CheckoutViewLine / Discount 类型 | SDK 有生成类型 `CheckoutViewLine{id,amount,currency}` + `Discount`；API 变更需再生类型 |

**结论**：新建 core 投影服务 + 切换 4 个序列化点（Cart/Order/AdminOrder/Checkout）；无新表、无金额写入。

## Step 1：Skill 咨询证据表（Gate 强制）

| Skill | 状态 | 关键结论引用 |
|---|---|---|
| `pallastrade-promotions`（领域） | ✅ 已读 | 促销=Rule/Action/Calculator；择优=每 adjustable 只留最大折扣一条；演示口径需按 eligible 聚合（批次1 已固化） |
| `pallastrade-customization`（必读） | ✅ 已读 | core 属团队产品，直接改源（git 跟踪）；行为改动遵循决策树 |
| `harness-prd` / `pallastrade-prd`（流程） | ✅ 已读 | approved→gate+REQ→实施→AC↔测试（prd verify）→知识同步门 |
| `pallastrade-api-v3` | ✅ 已读（本会话早前） | v3 序列化/Api 注册/OpenAPI 生成（typelize + generated:check）；载荷变更需同步 store.yaml/SDK 类型 |
| `pallastrade-testing` | ✅ 已读 | RSpec+FactoryBot；core factories 可用；测试放 backend/spec |
| `pallastrade-admin` / `catalog`（模板必读） | ⬜ 不涉及 | 不改 Admin 页面/控制器、不改商品目录（跨层搜索已证实） |

## 需求描述

建立 `PallasTrade::Promotions::Projection::DiscountProjection` 作为唯一"已享优惠"展示源（eligible-only 三档聚合、breakdown、removable、display）；Cart/Order/AdminOrder/Checkout 序列化统一切换；Checkout 形状对齐 Cart（方案A，含 id/粒度语义变更说明）；消除 N+1；锁定 `SUM(discounts)==discount_total` 与 parity 契约。

## 技术方案
- core 新增服务 + DTO（内存聚合；2-3 条批量查询）。
- api：共享渲染器输出规范 payload（含 hide_prices 门控：金额类字段置 null、身份字段保留）；Cart/Order/Checkout/AdminOrder 切换；typelize 类型更新。
- CheckoutView#discounts 委托投影（去掉自查询）。
- 测试：投影单测 + parity/QueryCounter 契约测试；storefront 核对（无消费则仅回归）。

## 风险点
- Checkout discounts id/粒度语义变更（外部 SDK 用户）→ API changelog/迁移说明必写。
- 竞争促销在 Cart 旧展示（含 ineligible 行）将被修正为 eligible-only（预期行为变化，测试锁定）。
- display_amount 生成需与既有 Money 格式一致。

## 验证方案（AC↔命令）
| 组 | 验证 |
|---|---|
| A(001-004) | `backend/spec/services/pallastrade/promotions/discount_projection_spec.rb` |
| B(005-009) | `projection_parity_spec.rb` + storefront 回归 |
| C(010-012) | 契约/批次1回归 + QueryCounter；`harness check --profile quick`；API 变更 → `generated:check` |

## 决策节点
- 用户 2026-09-10「按照方案A改」= PRD 确认 + 方案 A 选定。✅
