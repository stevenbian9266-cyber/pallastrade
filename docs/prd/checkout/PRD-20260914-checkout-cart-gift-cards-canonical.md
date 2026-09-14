# PRD-20260914-checkout-cart-gift-cards-canonical

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-14 |
| 来源 | research `RESEARCH-20260913` §9.3 P2「legacy 六端点收敛」（`RESEARCH-20260913` §45：`discount_codes / gift_cards / fulfillments / payments / payment_sessions / store_credits` 共享 legacy resolver）；用户指令「实施收敛」授权 |
| 分类 | checkout |
| 关联 Skill | pallastrade-api-v3 / pallastrade-payments / pallastrade-storefront |
| 关联 REQ | REQ-20260914-checkout-cart-gift-cards-canonical.md |
| 关联 PRD | PRD-20260914-checkout-cart-discount-codes-canonical（**同波次不同资源**：优惠码=促销折扣，礼品卡=资金占用；查重 31% 为"双解析+意图"模式重合，非重复需求 → `--force` 成立，依据参照 `PRD-20260912-payments-dsp-p7-3` 先例） |
| 需求类型 | 优化（legacy 收敛切片 1） |

## 1. 背景与目标

- **实测缺陷（dev，2026-09-14）**：`POST /api/v3/store/carts/cart_xxx/gift_cards` → **404 `cart_not_found`**。原因：该端点用 legacy `find_cart!`（`current_store.carts` = `PallasTrade::Order` 关联），解析不到 `pallastrade_carts`。storefront BFF `/api/checkout/coupon`（`kind: gift_card`）与 `CouponCode.tsx` 正是这么调用 → **购物车页礼品卡功能当前不可用**（与 PRD-20260914-checkout-cart-discount-codes-canonical 修掉的优惠码 403 同因）。
- **结构差异（决定设计）**：legacy 阶段 `@cart` 就是 Order —— `apply_gift_card` 会**直接创建 store-credit payment 并占用礼品卡余额**（`order.apply_gift_card` → `gift_card_apply_service`）。canonical `pallastrade_carts` **没有 payments**（资金只存在于 Order/Transaction）→ 礼品卡在 `cart_` 阶段只能承载**意图**，金额效果在**提交生成 Order 时**由既有 `PromotionHandler::Coupon` 的礼品卡分支落地（该分支已存在：`gift_cards_enabled? && load_gift_card_code` → `order.apply_gift_card`）。
- **目标**：① `cart_` 礼品卡端点立即可用（修 404）；② 应用/移除语义与 legacy 错误码一致；③ 提交时兑现，**失效即失败不静默**；④ legacy 分支行为不变 + 加观测日志（为收敛量化）。
- **范围外（后续切片）**：`store_credits` / `payments` / `payment_sessions` / `fulfillments` 四端点；`fulfillments` 属履约域需单独评估。

## 2. 用户故事 / 场景

- 作为**顾客**，我在购物车页输入礼品卡码应当被接受（或得到明确错误），而不是 404。
- 作为**运营**，我需要礼品卡占用在**下单时**发生（金额副作用落在 Order/Transaction），车阶段不得凭空占用余额。
- 场景：① 有效码 → 接受（意图写入购物车）；② 未知码 → `gift_card_not_found`；③ 过期码 → `gift_card_expired`；④ 已核销 → `gift_card_already_redeemed`；⑤ 移除（幂等）；⑥ 带礼品卡提交 → 订单占用礼品卡（经既有 apply_gift_card）；⑦ 提交时码已失效 → 提交失败、不落单；⑧ legacy 调用方行为不变。

## 3. 功能需求（FR）

- **FR-001（双解析）**：`carts/gift_cards_controller.rb` 支持 `cart_` → `current_store.shopping_carts`（顾客/游客作用域）；否则沿用 legacy `find_cart!` 并记 `[legacy-gift-cards]` 观测日志。
- **FR-002（应用）**：新增 `PallasTrade::Carts::ApplyGiftCard`：规范化码（strip/downcase）、在 `cart.store.gift_cards` 校验存在/未过期/未核销（错误码与 legacy 一致），通过则写 `cart.private_metadata['gift_card_code']` 并保存。
- **FR-003（移除）**：新增 `PallasTrade::Carts::RemoveGiftCard`：清除意图，幂等（无卡也成功）。
- **FR-004（提交兑现）**：`Carts::Submit` 在**金额管线跑完之后**（`order.update_with_updater!` 已落 `order.total`）把购物车上的礼品卡码交给既有 `order.apply_gift_card`（其内部调用 `GiftCards::Apply`，金额 = `min(remaining, order.total)`）；再跑一次 updater 重建 `payment_total / amount_due / payment_state`；**失败 → 提交失败（不落单、不静默）**；零额订单（全额折扣/免费商品 + 免运费）无款可付 → 不动礼品卡也不建 0 额 store credit。
- **FR-005（可见性）**：购物车序列化器暴露 `gift_card`（`code` + `display_amount_remaining`，来自服务端 Money 格式化），供 UI 展示"已应用/可移除"；不改变 `amount_due` 语义（车阶段不含礼品卡金额）。
- **FR-006（知识同步）**：OpenAPI ×2 标注双解析与错误码；api-v3 / payments Skill 记录"礼品卡车阶段=意图、金额在提交时兑现"；场景库新增 GS-117；research §9.3 P2 记录切片 1 完成、其余切片待办。

## 4. 非功能需求（NFR）

- **资金正确性**：车阶段**零资金副作用**（不创建 payment、不占用余额）；占用只发生在 Order 生成后。
- **不静默**：任何阶段失败返回结构化错误（金额相关不允许"悄悄按原价"）。
- **兼容**：legacy 请求路径/响应形状不变；`cart_` 为增量能力。
- **数据**：不新增数据库列（`private_metadata` 承载）。
- **可观测**：legacy 分支日志标记，为收敛量化提供数据。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001** ← FR-001/002：`POST /carts/{cart_xxx}/gift_cards`（有效码）→ 2xx 且 `cart.private_metadata['gift_card_code']` = 规范化码。
- **AC-002** ← FR-002：未知码 → 404 `gift_card_not_found`；过期 → 422 `gift_card_expired`；已核销 → 422 `gift_card_already_redeemed`。
- **AC-003** ← FR-003：`DELETE` 清除意图且幂等。
- **AC-004** ← FR-004：购物车带礼品卡提交 → 订单 `gift_card` 已占用（`order.gift_card_id` 命中）；提交时码失效 → **不落单**。
- **AC-005** ← FR-005：购物车载荷含 `gift_card.code`（含 `display_amount_remaining`）。
- **AC-006** ← FR-001：非 `cart_` id 仍走 legacy 解析并写观测日志。

> 回归与知识同步属**验证证据**（见 §9），不单列 AC；`prd verify` 只对 AC-001..006 计测试覆盖。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 关键词 | 结果 | 是否满足 |
|---|---|---|---|---|
| App | `backend/app/` | gift_card | 无宿主层实现 | — |
| Core | `pallastrade_core/app/` | `apply_gift_card` / gift_card_code | `models/pallastrade/order/gift_card.rb`（`apply_gift_card`/`remove_gift_card`/`recalculate_gift_card` + `gift_card_total`）、`promotion_handler/coupon.rb`（**礼品卡分支已存在**）、`PallasTrade::Cart` **无礼品卡建模** | 需新增车侧意图 |
| API | `pallastrade_api/app/` | gift_cards | `store/carts/gift_cards_controller.rb`（**修复点**：`find_cart!`）、`admin/orders/gift_cards_controller.rb`、`shopping_cart_serializer.rb`（**无 gift_card 字段** → 需补） | **本次改动点** |
| Admin | `pallastrade_admin/app/` | gift card | admin 订单礼品卡操作（`orders_controller` 等），走 Order 侧 API | 不受影响 |
| Storefront | `storefront/src/` | giftCards | BFF `app/api/checkout/coupon/route.ts`（`carts.giftCards.apply/remove`）、`CouponCode.tsx` | 受益方（零改动） |
| Platform | `platform/packages/sdk/` | giftCards | `carts.giftCards.apply/remove` 已存在 | 无需改动 |

**结论**：改动集中在 Core（车侧意图服务 + 提交兑现）+ API（双解析 + 序列化）；storefront/SDK 零改动即可恢复功能。

## 7. 技术影响

- **修改**：`carts/gift_cards_controller.rb`、`shopping_cart_serializer.rb`、`carts/submit.rb`、`ai/skills/pallastrade-api-v3/SKILL.md`、`ai/skills/pallastrade-payments/SKILL.md`、`harness/scenarios/scenarios.json`、`docs/research/RESEARCH-20260913-…` §9.3
- **新增**：`carts/apply_gift_card.rb`、`carts/remove_gift_card.rb`、spec（服务 + 请求 + submit 两例）
- **数据库**：无迁移
- **接口**：`POST/DELETE /api/v3/store/carts/{id}/gift_cards` 语义扩展（兼容 legacy）；购物车载荷新增 `gift_card` 字段

## 8. 测试计划

- **新增**：`spec/services/pallastrade/carts/apply_gift_card_spec.rb`（AC-002 + NFR-1 车阶段零资金副作用 + AC-003 移除幂等）、`spec/requests/api/v3/store/carts/gift_cards_spec.rb`（AC-001/002/003/005/006 —— AC-005 在此请求规格断言载荷，未单独建序列化器规格）
- **更新**：`spec/services/pallastrade/carts/submit_spec.rb`（AC-004 两例：带卡提交 → 订单占用；码失效 → 不落单）
- **验证器**：`p1-order-flow-rspec`（已扩入 `apply_gift_card_spec` + `carts/gift_cards_spec`）+ `backend-rspec`（全量）；契约产物由 `scripts/ci/contracts.sh` 重生成（typelizer + api:docs:schemas）
- **dev 实测**：`POST /carts/{cart_}/gift_cards`（未知码）→ 404 `gift_card_not_found`（不再是 `cart_not_found`）；用真实礼品卡码 → 201 且 `private_metadata` 落码

## 9. 文档同步清单（知识同步门）—— 结论

| 资产 | 状态 | 结论 |
|---|---|---|
| OpenAPI ×2（`backend/public/api-docs/store.yaml` + `platform/docs/api-reference/store.yaml`） | ✅ 已更新 | `gift_cards` 端点：双解析 + 车阶段意图语义 + 错误码 |
| `ai/skills/pallastrade-api-v3/SKILL.md` | ✅ 已更新 | 端点条目：车阶段=意图、提交时兑现、legacy 观测 |
| `ai/skills/pallastrade-payments/SKILL.md` | ✅ 已更新 | 礼品卡资金语义：占用在 Order 侧（`apply_gift_card` → store-credit payment） |
| `harness/scenarios/scenarios.json` | ✅ 已更新 | GS-117（双解析 + 意图 + 提交兑现 + 不静默） |
| `docs/research/RESEARCH-20260913-…` §9.3 | ✅ 已更新 | P2 legacy 收敛：切片 1（gift_cards）完成；剩余 4 端点待办 |
| SDK / platform 包 | ✅ 已评估，无需更新 | `carts.giftCards.*` 已存在，URL/类型不变 |
| `ai/skills/pallastrade-typescript-sdk/SKILL.md` | ✅ 已更新 | P1 扩展条目补 `carts.giftCards.apply/remove` 双解析 + 车阶段意图语义 |
| `platform/packages/README.md` | ✅ 已更新 | `ShoppingCart.gift_card` 类型变更说明 + 契约重生成指引（doc-impact 阻断项已消） |
| 根 `README.md` | ✅ 已评估，无需更新 | 根 README 不承载 SDK 字段级契约（由 `platform/packages/README.md` 承载） |
| `ai/skills/pallastrade-prd/SKILL.md` / `AGENTS.md` / `.github/copilot-instructions.md` | ✅ 已评估，无需更新 | 本次是 PRD **应用**而非 PRD 机制变更；`harness.config.mjs` 仅扩 `p1-order-flow-rspec` 命令（该验证器不在 AGENTS.md §6 表内，工作流文档同步由 scenarios.json 满足） |
| 反模式库 / 任务规则 | ✅ 已评估，无需更新 | 未引入禁止模式；车阶段零资金副作用与既有原则一致 |

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-14 | 1.0 | 实施：`Carts::ApplyGiftCard` / `RemoveGiftCard`（`private_metadata['gift_card_code']`）；`gift_cards` 端点双解析 + legacy 观测；`Carts::Submit` 经 `PromotionHandler::Coupon` 礼品卡分支兑现（失败不落单）；购物车序列化器暴露 `gift_card`；规格 3 文件 + Skill×2 + GS-117 + research §9.3 | AI |
| 2026-09-14 | 1.1 | 验证：3 个 spec 文件 23 examples 0 failures（绿）；契约产物重生成并同步 platform 副本（`ShoppingCart.gift_card`）；PRD 状态 → done | AI |
| 2026-09-14 | 1.2 | dev 实测（部署 `87cf3946`）：未知码 404 `gift_card_not_found`（原 `cart_not_found`）；真实码 201 + 载荷 `gift_card`；移除 200；`private_metadata` 落码且礼品卡 `amount_used=0.0`（车阶段零资金副作用实证） | AI |
| 2026-09-14 | 1.3 | 修复 GATE-2026-09-14T12-44-52：dev 真实提交暴露缺陷 —— 礼品卡在 `update_with_updater!` **之前**兑现 → `order.total` 尚未落库（dev 为 0）→ StoreCredit 金额 0 → 提交失败（`Amount must be greater than 0`）。改为“金额管线跑完 → 兑现 → 再跑 updater”，并加零额守卫；规格改为断言**金额语义**（`gift_card_total == min(面额, total)`、`amount_due == total - gift_card_total`、`amount_used` 同步）并补零额用例 | AI |
| 2026-09-14 | 1.4 | dev 提交兑现 E2E（部署 `a07db828`）：真实订单 `total 89.99` / `gift_card_total 25.0` / `amount_due 64.99` / store-credit payment `25.0` / 礼品卡 `amount_used 25.0`（修复前同一脚本 `Amount must be greater than 0`） | AI |
