# REQ-20260910-promo-batch3a-redemption-ledger

| 元数据 | 值 |
|---|---|
| 状态 | done（实施完成；证据见 gate GATE-2026-09-10T05-52-53 收尾记录） |
| 任务类型 | 功能优化（资金完整性：核销记账） |
| 关联 PRD | `docs/prd/promotions/PRD-20260910-promotions-promo-batch3a-redemption-ledger.md` |
| 关联任务 | TASK-20260910055216-90c45a7d / GATE-2026-09-10T05-52-53 |
| 来源 | `豆包梳理业务需求/promotion模块架构-任务拆解.md` 批次3（PR-P4-1/2/4 + P4-8 基础） |

---

## Step 0：跨层搜索（本轮实测）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | redemption / coupon / promotion | 仅生成的 TS 类型（`app/javascript/types/serializers/*`）；无宿主业务逻辑 | 无需改动 |
| App — views/decorators | `backend/app/` | promotion / coupon | 无 | 无需改动 |
| Core Gem — models | `pallastrade_core/app/models/` | redemption / credits_count / usage_limit / apply_order! | `promotion.rb`（credits/adjusted_credits/usage_limit_exceeded）、`coupon_code.rb`（apply_order!/remove_from_order）、`promotion_handler/coupon.rb`（apply→占用）、`order/checkout.rb`（complete→use_all_coupon_codes）、`order.rb`（use_all_coupon_codes） | ❌ 不满足：无台账、无占用状态机、apply 即消耗 |
| Core Gem — services | `pallastrade_core/app/services/` | redemption / coupon_codes | `coupon_codes/bulk_generate.rb`（生成码）、`coupon_codes_handler`（use_all_codes） | ❌ 不满足：无核销服务 |
| API Gem — controllers | `pallastrade_api/app/controllers/` | coupon / promotion / usage | admin `coupon_codes_controller`（只读列表）、store `carts/discount_codes_controller`（apply/remove） | 部分相关：4a 不改 payload |
| Admin Gem — controllers | `pallastrade_admin/app/controllers/` | coupon / credits | `coupon_codes_controller`、`orders/order_promotions_controller` | 4a 不改 |
| Admin Gem — views | `pallastrade_admin/app/views/` | usage_limit / coupon | `promotions/_usage_limit.html.erb`（`coupon_codes.used.count`） | 4b 再评 |
| Storefront | `storefront/src/` | coupon / redemption | `app/api/checkout/coupon/route.ts`、`components/checkout/CouponCode.tsx` | 无核销概念；行为变化对前端透明 |
| Platform | `platform/packages/` | coupon / promotion | SDK 类型/文档（`Promotion`、`discountCodes.apply`） | 无改动 |

### 搜索结论

- 全仓**不存在** redemption / 核销台账能力（`backend/db/schema.rb` 与全 6 层零命中）→ 本批次为新建。
- 现有占用语义集中在 `PromotionHandler::Coupon`（apply 时 `CouponCode#apply_order!`）与 `Order::Checkout`（complete 时 `use_all_coupon_codes`），两者职责重叠且都发生在「非支付确认」时刻。
- 数量统计口径来自 `Promotion#credits_count`（Adjustment 统计），与本批次要建的 ledger 并存会造成双口径 → 必须一并切换。
- 核心改动全部落在 `pallastrade_core` gem（本仓库允许直接修改 gem 源并 git 跟踪）。

---

## Step 1：Skill 文件咨询（真实结论）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树优先级：Settings → Configuration → **Events** → Dependencies → … → Decorators；「react to something happening（order completed…）」优先用 **Events subscriber**，本批次核销事件（FR-014）按此发布；结构性模型改动直接改 core 源（本仓库约定，见 AGENTS.md §1）。 |
| `ai/skills/pallastrade-promotions/SKILL.md` | ✅ 已读 | 批次1 条目：单码 `code` store 级唯一由「模型校验 + PG 函数索引」双保险；`with_coupon_code` 必须确定性；批次2 条目：折扣投影唯一来源为 `DiscountProjection`，金额不变量 `SUM(discounts)==discount_total`。本批次**不得**触碰这两条口径。 |
| `ai/skills/pallastrade-data-model/SKILL.md` | ✅ 已读 | 模型关系图约定：新增模型需明确 belongs_to/has_many 与 store 作用域（如 `Review`/`BackInStockSubscription` 均 store-scoped + 唯一约束）；`PromotionRedemption` 按此模式落地（store-scoped + `(promotion_id, order_id)` 唯一）。 |

**按需 Skill：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-events-webhooks` | ✅ | ✅ 已读 | 订阅者**不会自动发现**，必须注册；`publish_event` 在调用点派发（可能在事务内）→ 核销事件在事务**内**发布需注意订阅者可见性；已用 `subscribes_to` + 注册模式（本批次只发布事件，订阅者在 4b/下游接）。 |
| `pallastrade-payments` | ✅ | ✅ 已读 | 支付状态机 `checkout → processing → pending → completed`，`payment.completed` 事件存在；Order 完成与资金确认之间存在时间差 → 4a 选定「order.complete 短事务内 Reserve+Commit」，与 4b 的 `commerce_transaction.payment_confirmed` 挂接解耦（见 PRD D3）。 |
| `pallastrade-testing` | ✅ | ✅ 已读 | 栈为 RSpec + FactoryBot + Capybara；factory 来自 `pallastrade/testing_support/factories`；新增 spec 沿用 `create(:order_with_line_items)` 等既有工厂（批次1/2 已验证）。 |
| `pallastrade-api-v3` | ⬜ 否 | — | 本批次无 API payload 变化（4b 再做只读端点）。 |
| `pallastrade-decorators` | ⬜ 否 | — | 直接改 core gem 源（仓库允许），不用装饰器。 |
| `pallastrade-dependencies` | ⬜ 否 | — | 无依赖注入替换需求。 |
| `pallastrade-storefront` | ⬜ 否 | — | 前端消费的 `discounts` 投影不变；apply 不再消耗对前端透明。 |
| `pallastrade-i18n` | ⬜ 否 | — | 无新增用户可见文案（错误码沿用既有 `coupon_code_*`）。 |
| `pallastrade-admin` | ⬜ 否 | — | 4b 才涉及只读核销页。 |

---

## 需求标题

促销核销台账（PromotionRedemption）：把「apply 即消耗」迁移为「下单核销」，`usage_limit` 改读 ledger，并提供历史回填。

## 任务类型

功能优化（资金完整性 / 数据一致性）——不含金额计算变更。

## 需求描述

顾客把优惠码填进购物车时，不应立即消耗该码；只有在订单真正成交时才应记一笔「核销」，取消订单后应可释放。当前系统在**加到购物车**时就把一次性码标记为已使用，并且 `usage_limit` 依赖「调整记录即时统计」，既没有可审计台账，也无法区分「占用中/已核销」。本批次建立核销台账与三个状态（reserved/committed/released），提供核销/释放服务并在下单与取消路径挂接，`usage_limit` 改读台账，历史数据可回填。

## 影响范围（预估）

- 新增：1 迁移（`pallastrade_promotion_redemptions`）、1 模型、4 服务（Reserve/Commit/Release/FinalizeOrder+ReleaseOrder）、1 rake 任务、4 个新 spec + 2 个回归 spec。
- 修改：`promotion.rb`、`coupon_code.rb`、`promotion_handler/coupon.rb`、`order/checkout.rb`、`order.rb`。
- 不改：金额计算（Calculator/Adjuster）、API payload、Admin UI、支付/退款、storefront。

## 技术方案（初步）

1. 迁移建表 + 唯一约束（`(promotion_id, order_id)`、部分唯一 `(coupon_code_id)`）与查询索引。
2. `PallasTrade::PromotionRedemption`（enum 三态 + 前缀 id）与三模型关联。
3. 服务层 `Promotions::Redemption::{Reserve,Commit,Release,FinalizeOrder,ReleaseOrder}`，全部幂等；`FinalizeOrder` 在 `order.complete` 短事务内完成 Reserve+Commit 并原子占用多码。
4. `Promotion#usage_limit_exceeded?` 与 `credits_count` 切换到 ledger；`PromotionHandler::Coupon` 删除提前占用（保留校验与错误码）。
5. `Order::Checkout` 挂接：complete → `FinalizeOrder`；canceled → `ReleaseOrder`。
6. rake 回填（dry-run 默认）+ 事件发布 + 不变量 specs。

## 风险点

| 风险 | 等级 | 缓解 |
|---|---|---|
| 口径切换导致 usage_limit 判定变化（历史数据） | 中 | 回填 + AC-007/AC-008 固化；`credits_count` 保留兼容 |
| 下单路径新增写入失败影响成交 | 中 | 同事务 + 唯一约束兜底；失败即回滚（不产生半占用） |
| 多码占用时机后移导致的可见性差异（后台显示 used 时间点） | 低 | 写入 PRD §11 与 data-model SKILL；4b 评估后台读数口径 |
| 与 TXN-P2 / REV-P6 事件状态机耦合 | 中 | 4a 不挂 `commerce_transaction.*` 事件（明确留 4b），避免双轨 |

## 决策节点

> ✅ **已确认（2026-09-10）**：用户确认 PRD §3 的 D1..D7 全部建议方案，核销触发点采用 `order.complete` 短事务内 Reserve+Commit（D3 建议项）。实施产物：迁移 `20260910000001_create_pallastrade_promotion_redemptions`、模型 `PromotionRedemption`、服务 `Promotions::Redemption::{Reserve,Commit,Release,FinalizeOrder,ReleaseOrder}`、回填 rake `pallastrade:promotions:backfill_redemptions`、4 个新 spec（AC-001..013）。
