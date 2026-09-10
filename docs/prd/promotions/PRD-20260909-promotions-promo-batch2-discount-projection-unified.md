# PRD-20260909-promotions-promo-batch2-discount-projection-unified

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-09（修订 2026-09-10） |
| 确认 | 2026-09-10 用户选定 **方案 A**（Checkout discounts 对齐 Cart 全字段；id/粒度语义变更 → 需 API 文档 changelog/迁移说明）并指示实施 |
| 来源 | 实施批次2：DiscountProjection 统一投影 + Cart/Checkout/Order 全链路切换（任务拆解 PR-P1-1..4 / PR-P2-1..6；来源 promotion模块架构.md §7/§2/§14） |
| 分类 | promotions（语义微调：骨架自动判为 checkout，因含 cart/order 关键词；AI 记录归 promotions） |
| 关联 Skill | pallastrade-promotions、pallastrade-api-v3、pallastrade-testing |
| 关联 REQ | REQ-20260910-promo-batch2-discount-projection-unified |
| 关联 PRD | PRD-20260909-promotions-promo-batch1-invariants-and-code-uniqueness（本批次依赖其 A0 口径与契约测试） |
| 需求类型 | 优化迭代（资金展示口径收敛） |

> 原则：金额公式零改动（复用批次1 附录 A 口径）；只收敛**对外展示投影**；不触碰 Promotion/Adjustment 写入与 Redemption（后续批次）。

---

## 1. 背景与目标

- **一句话需求**：建立统一 `DiscountProjection` 作为 Cart / Checkout / Order / Email / Webhook / Admin 的唯一"已享优惠"展示源，消灭口径漂移（审计 Finding D）与序列化 N+1，并锁定 `SUM(discounts[]) == discount_total` 不变量。
- **背景（已核实）**：
  - `Order#discounts` = `order_promotions`；`OrderPromotion#amount` 用 `all_adjustments.promotion`（**未过滤 eligible**）→ 竞争促销并存时 discounts 汇总可能 ≠ discount_total。
  - `OrderCheckout::CheckoutView#discounts` 只取 **order 级** `order.adjustments`（漏行级/免邮），且 CheckoutSerializer 输出形状（`{id,amount,currency}`）与 Cart/Order 不一致。
  - CartSerializer `many :discounts` 序列化每条时调用 `OrderPromotion#amount`（每行一次 SQL sum）= N+1。
  - 批次1 已建立契约测试（discount_total==Σeligible、重算确定、remove 幂等），为本次切换提供安全网。
- **目标**：单一投影服务 + 全链路消费 + 口径/形状统一 + N+1 消除。
- **成功指标**：
  - `DiscountProjection` 单测 + 全链路 parity 测试全绿（纳入 quick profile）。
  - Cart/Checkout/Order 对同一交易返回**相同形状**的 discounts 且 `SUM == discount_total`。
  - 订单序列化 discounts 查询次数有界（消除按条 SQL sum）。

---

## 2. 用户故事 / 场景

- 作为顾客：购物车、结算页、订单详情三处看到的优惠名称/金额一致，且与"优惠合计"对得上。
- 作为开发者：一个促销对象（引擎）不会出现"同目标两套优惠展示逻辑"。
- 场景：单码整单折扣 / 自动行级折扣 / 免邮 / 三者并存 / 竞争促销（仅 best eligible 计入投影） / 历史订单（名称/码快照为后续批次，本期沿用当前定义并标注）。

---

## 3. 功能需求（FR）

### A. DiscountProjection 核心服务（`PallasTrade::Promotions::Projection::DiscountProjection`）
- FR-001：`DiscountProjection.for(order:)` 返回按促销聚合的展示行列表（DTO，值对象不落库）。
- FR-002：每行字段契约（统一形状，供所有消费端）：`id`(discount_=order_promotion prefixed，无则 promo prefixed)、`promotion_id`、`name`、`code`(可空)、`kind`、`amount`(总优惠，负值)、`breakdown{item,order,shipping}`、`removable`(coupon_code/多码可移除=true；automatic=false)。
- FR-003：金额口径 = 批次1 附录 A：仅统计 `source_type=PromotionAction AND eligible=true` 的三档调整（order/line_item/shipment），按促销分组聚合；**修复 OrderPromotion#amount 未过滤 eligible 的偏差**（投影层修正，不改写金额事实）。
- FR-004：`amount == breakdown 三档求和`；`SUM(amount) == order.discount_total`（含多促销并存场景）。
- FR-005：一次批量加载（all_adjustments 预载 + 内存分组），**序列化时零按条 SQL**（消除 N+1）。
- FR-006：名称/码展示：coupon 促销取 `promo_code`/`code_for_order` 语义（多码取订单所用码）；automatic 取 `name`；`removable` 依据 kind。
- FR-007：输入校验与降级：无 order / 无订单促销 → 空数组；防御 order_promotions 缺失（数据异常）时仍返回 promo 级行。

### B. 全链路切换（只读消费端）
- FR-008：CartSerializer `many :discounts` 数据源切到 Projection（Store API 载荷形状不变或仅增补，保持 `id/name/code/amount/display_amount/promotion_id`）。
- FR-009：OrderSerializer / Admin OrderSerializer（expand discounts）切到 Projection。
- FR-010：CheckoutView#discounts 与 CheckoutSerializer 切到 Projection，**输出形状与 Cart 对齐**（含 name/code/promotion_id/breakdown；保留 amount/currency 语义）；消除"Checkout 漏行级/免邮"。
- FR-011：storefront 消费核对：CouponCode 组件(已应用列表/移除用 code)、OrderTotals、order-confirmation 邮件、webhook handler 使用的 discount 字段与 Projection 输出一致（必要时小改前端字段读取）。
- FR-012：`OrderPromotion#amount` 保留（兼容旧调用/审计），但**序列化路径不再调用它**；在其上标注"请用 DiscountProjection"备注。

### C. 校验/回归（NFR 落为测试）
- FR-013：契约测试新增：投影行聚合、eligible-only（对比 OrderPromotion#amount 旧口径差，标记 known_gap 关闭点）、SUM 不变量、breakdown 一致、Cart/Checkout/Order parity（同交易、同输入同结果）、移除幂等后投影为空。
- FR-014：N+1 防回归：QueryCounter 断言订单+多促销序列化查询数有界。
- FR-015：不影响批次1 契约（I1..I6 继续全绿）；不改变金额写入/Redemption。

---

## 4. 非功能需求

- 资金展示正确性：金额事实仍为 Adjustment，投影只读。
- 性能：投影一次加载全量调整；Cart/Checkout/Order 序列化查询数不因促销数增长。
- 兼容：Store API Cart/Order 现有 discounts 字段语义不回退（id/amount/display/removable 由现有 UI 依赖，须兼容）；Checkout API 为增量对齐（属 API 展示增强，需文档同步）。
- 可维护性：投影 DTO 值对象、单一测试目录、与批次1 contract spec 同目录。

---

## 5. 验收标准（AC，与测试一一映射；编号供 prd verify）

### A 投影服务
- AC-001 ← FR-001/002：`for(order:)` 返回元素含全部契约字段且类型正确（id/promotion_id/name/code/kind/amount/breakdown/removable）。
- AC-002 ← FR-003：竞争促销场景（两 automatic 整单折扣并存，best 为 -30、另一 -5）投影仅体现 eligible 的 -30；与 discount_total 一致；显式不等于旧 OrderPromotion#amount 汇总（-35，known gap 关闭点断言）。
- AC-003 ← FR-004：单码整单/自动行级/免邮/三档并存 ≥4 场景断言 `SUM(amount)==discount_total` 与 breakdown 求和一致。
- AC-004 ← FR-005：多码券订单投影行 code=订单所用码；automatic 行 removable=false、coupon 行 removable=true；无促销→空数组。

### B 切换
- AC-005 ← FR-008：CartSerializer discounts 与投影输出一致（对同一订单逐行比对）。
- AC-006 ← FR-009：Order/Admin Order（expand discounts）与投影一致。
- AC-007 ← FR-010：CheckoutSerializer discounts 形状=Cart（含 name/code/promotion_id/breakdown），同一交易下与 Cart 逐行金额一致（parity）；含免邮/行级场景不漏。
- AC-008 ← FR-011：storefront 相关消费（CouponCode 已应用列表/移除、OrderTotals、邮件/webhook 字段）回归测试/静态核对通过；CouponCode 的移除仍按 code 工作。
- AC-009 ← FR-012：确认无序列化路径调用 `OrderPromotion#amount`（代码检索/测试 QueryCounter）。

### C 校验
- AC-010 ← FR-013：新增契约测试全绿并纳入 quick profile；批次1 I1..I6 回归全绿。
- AC-011 ← FR-014：QueryCounter 断言（订单+3 促销）Cart/Order 序列化查询数不随促销数线性增长（上限断言）。
- AC-012 ← FR-015：未改金额写入路径；`git diff` 不含 Promotion/Action/Adjustment 写入逻辑变更（review 检查项）。

---

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 关键词 | 找到 | 满足？ |
|---|---|---|---|---|
| App | backend/app | promotion | 仅 TS 类型 | 无需宿主改动 |
| Core | pallastrade_core/app | order_promotion/order_updater/order_checkout view | `OrderPromotion#amount`(未过滤)、`CheckoutView#discounts`(order级)、updater 口径(批次1已固) | 主改动区（新增投影 + 修 CheckoutView） |
| API | pallastrade_api/app | cart_serializer/order_serializer/checkout_serializer/discount_serializer | Cart/Order `many :discounts`→order_promotions；CheckoutSerializer discounts 形状不一致 | 切换区 |
| Admin | pallastrade_admin/app | order discounts | Admin OrderSerializer(api层) 用之；Admin 页面显示 order_promotions 摘要 | 跟随 api 切换，UI 不改 |
| Storefront | storefront/src | coupon/discount | CouponCode/OrderTotals/邮件/webhook 消费 discounts 字段 | 核对/微调 |
| Platform | platform/packages | sdk discount/promotion 类型 | Cart/Order type 已含 discounts | Checkout 若入 OpenAPI 则再生 |

**结论**：能力在 core+api；本批次新建 core 投影服务并把 4 个序列化点切到它；无新表/无金额写入。

---

## 7. 技术影响

- 新增：`PallasTrade::Promotions::Projection::DiscountProjection`（+ DTO）+ spec。
- 修改：`OrderCheckout::CheckoutView`、Cart/Order/Admin Order/Checkout 序列化器 discounts 数据源；storefront 若读取 checkout discounts 变化处；API 文档（checkout discounts 形状对齐）+ 可能 SDK 类型再生。
- 不涉及：数据库、Promotion/Adjustment 写入、Redemption。
- 风险：Checkout API discounts 载荷变化（新增字段属 additive）；Cart/Order 保持兼容；需跑全量相关回归。

## 8. 测试计划

| 文件 | 覆盖 |
|---|---|
| `backend/spec/services/pallastrade/promotions/discount_projection_spec.rb`（新） | AC-001..004、AC-009/010 |
| `backend/spec/services/pallastrade/promotions/projection_parity_spec.rb`（新） | AC-005..007、AC-011 |
| `storefront/src/components/checkout/__tests__/UnifiedCheckout.test.tsx`（更新） | AC-008（若字段读取变化） |
| 既有批次1 contract spec | 回归（AC-010） |

运行：backend rspec（容器）；storefront vitest；`harness check --profile quick`；API 有变时 `generated:check`。

## 9. 文档同步清单（知识同步门）

- [x] `pallastrade-promotions` SKILL：新增“Discount projection & API contract”条目（投影来源/字段/不变量/hide_prices/已废弃旧路径）。
- [x] **API 变更记录（方案A）**：Checkout `discounts` 对齐 Cart（见 §11 兼容与迁移说明）→ `backend/public/api-docs/{store,admin}.yaml` 已由 `rake api:docs:schemas` 再生（新增 `DiscountLine` 组件；Cart/Order/AdminOrder/StoreCheckoutCheckout 的 `discounts` 均为 `array of DiscountLine`），`platform/docs/api-reference/` 副本已同步，`platform/packages/sdk` 类型已再生（`rake typelizer:generate`），`api:docs:schemas:check` 报告 clean。
- [x] 场景库：新增 `GS-082`（Unified discount projection & API contract）。
- [x] `docs/prd/README.md` 索引 + 本 PRD 状态（done）。

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-09 | 0.1 | 初稿（承接批次1 A0 口径与契约安全网） | AI |
| 2026-09-10 | 0.2 | 细化 FR/AC 编号与切换面 | AI |
| 2026-09-10 | 0.3 | approved：用户选定方案A（Checkout 对齐 Cart 全字段，含 id/粒度语义变更与兼容说明） | AI |
| 2026-09-10 | 1.0 | done：DiscountProjection + DiscountRendering 落地；4 个序列化点切换；新增 2 个 spec（18 例）+ 前端兼容用例；全量 Store 请求回归 188 例 0 失败；契约产物再生（DiscountLine）；Skill/场景库/PRD 索引同步 | AI |

## 11. 兼容与迁移说明（方案A，API 消费方必读）

Checkout API `GET /api/v3/store/checkout`（及同构 CheckoutSerializer 输出）的 `discounts[]` 由
`{ id, amount, currency }` 对齐为 Cart/Order 的规范折扣行。**破坏点只有两处**：

| 字段/行为 | 变更前 | 变更后 | 迁移动作 |
|---|---|---|---|
| `discounts[].id` | `adj_…`（Adjustment id） | `discount_…`（OrderPromotion id；缺失时回退 `promo_…`） | 不要把 id 当作 Adjustment id 使用；需要 Adjustment 明细请用 Admin API |
| 行粒度 | 每个 order 级 Adjustment 一行（漏行级/免邮） | **每个促销一行**，聚合 order/line-item/shipment 三档（只计 eligible） | 客户端按 `promotion_id` 去重即可；金额仍可直接求和 |

新增（additive，无需迁移）：`promotion_id`、`name`、`description`、`code`、`kind`、`display_amount`、
`breakdown { items, order, shipping }`、`removable`。移除：`currency`（币种在订单顶层 `currency` 字段，
行内金额与顶层同币种）。`hide_prices` 下整个字段为 `null`（与其余金额字段一致）。

不变量保证：`SUM(discounts[].amount) == discount_total`，且每行 `amount == breakdown 三档求和`。
