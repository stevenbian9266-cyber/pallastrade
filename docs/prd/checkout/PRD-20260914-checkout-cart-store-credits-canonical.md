# PRD-20260914-checkout-cart-store-credits-canonical

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-14 |
| 来源 | research `RESEARCH-20260913` §9.3 P2「legacy 六端点收敛 + usage metric（P0-7 流量阈值驱动）」；切片 1（gift_cards）已完成（`PRD-20260914-checkout-cart-gift-cards-canonical`）；用户指令「实施收敛」 |
| 分类 | checkout |
| 关联 Skill | pallastrade-api-v3 / pallastrade-payments / pallastrade-testing |
| 关联 REQ | REQ-20260914-checkout-cart-store-credits-canonical.md |
| 关联 PRD | PRD-20260914-checkout-cart-gift-cards-canonical（同波次：礼品卡=外部资金工具，店铺余额=账户余额；查重 35% 为「双解析 + 意图」模式重合，非重复需求 → `--force` 成立） |
| 需求类型 | 优化（legacy 收敛切片 2） |

## 1. 背景与目标

- **实测缺陷（dev，2026-09-14）**：`POST /api/v3/store/carts/cart_xxx/store_credits` → **401**（`require_authentication!`）后即使带 JWT 也会 **404 `cart_not_found`**——该端点用 legacy `find_cart!`（`current_store.carts` = `PallasTrade::Order` 关联），解析不到 `pallastrade_carts`。语义与切片 1 的礼品卡完全同构。
- **结构差异（决定设计）**：legacy 的 `@cart` 就是 Order —— `PallasTrade.checkout_add_store_credit_service`（`Checkout::AddStoreCredit`）直接在订单上创建 store-credit payment（金额 = `min(amount, outstanding_balance)`）。canonical `pallastrade_carts` **没有 payments** → 车阶段只能承载**意图**，占用发生在提交生成 Order 之后（与切片 1 的礼品卡同一定式）。
- **权威约束（必须尊重）**：`GiftCards::Apply` 明确拒绝「同单混用礼品卡 + 店铺余额」（`:gift_card_using_store_credit_error`）→ 意图层就要互斥，避免提交时才炸。
- **收敛策略（research §9.3 P2 原文）**：legacy 端点收敛由 **P0-7 usage metric 流量阈值驱动**。本切片为仍需保留在 legacy 的两个订单域端点（`payments` / `fulfillments`）补统一观测日志，使残留流量可量化；`payment_sessions` 已有 `payment.legacy_flow.used`（不改）。
- **目标**：① `cart_` 店铺余额端点立即可用（修 404）；② 应用/移除语义与 legacy 一致 + 混用防护；③ 提交时兑现在**最终金额**上，失败即不落单；④ 余下 legacy 端点流量可观测（为后续「是否迁 canonical」提供数据）。
- **范围外**：`payments` / `fulfillments` 的 canonical 化本身（订单域语义，canonical 等价能力在 `/orders/...` 与 `PATCH /carts/:id`；是否迁由观测流量决定）。

## 2. 用户故事 / 场景

- 作为**登录顾客**，我在购物车页选择「使用账户余额」应当被接受（或得到明确错误），而不是 401/404 混淆。
- 作为**财务/运营**，我需要余额占用发生在**下单时**（金额副作用落在 Order/Transaction），车阶段不得凭空占用余额。
- 作为**平台工程师**，我需要知道还有多少真实流量打在 legacy 订单域端点上（`payments` / `fulfillments`），再决定是否迁移。
- 场景：① 未登录 → 401；② 无可用余额 → 明确错误；③ 指定金额 → 意图写入；④ `full`（用尽）→ 意图写入；⑤ 与礼品卡意图冲突 → 拒绝；⑥ 移除（幂等）；⑦ 带余额意图提交 → 订单占用至多 `outstanding_balance`；⑧ legacy 调用方行为不变 + 观测日志。

## 3. 功能需求（FR）

- **FR-001（双解析 + 观测）**：`carts/store_credits_controller.rb` 支持 `cart_` → `current_store.shopping_carts`（顾客/游客作用域，`active`）；否则沿用 legacy `find_cart!` 并记 `cart.legacy_flow.used`（flow_type=`legacy_cart_store_credits`）。`require_authentication!` 保留（余额属账户资产，游客无余额）。
- **FR-002（应用意图）**：新增 `PallasTrade::Carts::ApplyStoreCredit`：要求 `cart.user` 存在、用户在本店有**可用余额**（`store_credits.for_store(store).available.where(currency: cart.currency)`，没余额直接拒，与 legacy 同口径）、`amount` 合法（> 0；省略则固化当前可用余额合计）、且**未设置礼品卡意图**；通过则写 `cart.private_metadata['store_credit_amount']`（十进制字符串，提交时再按 `min(金额, outstanding_balance)` 收敛）。
- **FR-003（移除意图）**：新增 `PallasTrade::Carts::RemoveStoreCredit`：清除意图，幂等。
- **FR-004（提交兑现）**：`Carts::Submit` 在**金额管线跑完**（`order.update_with_updater!`）并完成礼品卡兑现后，调用权威 `PallasTrade.checkout_add_store_credit_service.call(order:, amount:)`；失败 → 提交失败（不落单、不静默）；零额订单跳过；随后再跑一次 updater 刷新 `payment_total` / `amount_due` / `payment_state`。
- **FR-005（互斥）**：`ApplyGiftCard` 在存在余额意图时拒绝（`gift_card_store_credit_conflict`）；`ApplyStoreCredit` 在存在礼品卡意图时拒绝（`store_credit_gift_card_conflict`）——镜像 `GiftCards::Apply` 的权威约束。
- **FR-006（可见性）**：购物车序列化器暴露 `store_credit`（`amount` + `display_amount`），供 UI 展示「已使用余额」；不改变车阶段 `amount_due` 语义（余额在提交时扣除）。
- **FR-007（余下 legacy 端点流量观测）**：`carts/payments_controller`、`carts/fulfillments_controller` 的 legacy 分支补 `cart.legacy_flow.used` 日志（共用 concern，含 `flow_type` / `entry_point` / `order_id`）。
- **FR-008（知识同步）**：OpenAPI 标注双解析与错误码；`pallastrade-api-v3` / `pallastrade-payments` Skill 记录「车阶段=意图、提交兑现、与礼品卡互斥」；场景库新增 GS-118；research §9.3 P2 更新切片 2 状态。

## 4. 非功能需求（NFR）

- **资金正确性**：车阶段**零资金副作用**（不建 payment、不占余额）；占用只发生在 Order 生成后，且以**最终** `order.total`/`outstanding_balance` 为准。
- **不静默**：任何阶段失败返回结构化错误（金额相关不允许「悄悄按原价」）。
- **兼容**：legacy 请求路径/响应形状不变；`cart_` 为增量能力。
- **数据**：不新增数据库列（`private_metadata` 承载）。
- **可观测**：legacy 分支统一日志（含 `payment_sessions` 既有 key 不变）。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001** ← FR-001/002：`POST /carts/{cart_xxx}/store_credits`（已登录 + 有余额 + 指定金额）→ 2xx 且 `cart.private_metadata['store_credit_amount']` = 规范化金额。
- **AC-002** ← FR-002：未登录 → 401；无可用余额 → 422 `store_credit_not_available`；非法金额（0/负数）→ 422 `store_credit_invalid_amount`。
- **AC-003** ← FR-002：`amount` 省略 → 意图 = 当前可用余额合计（同币种；固化为十进制字符串）。
- **AC-004** ← FR-003：`DELETE` 清除意图且幂等。
- **AC-005** ← FR-004：购物车带余额意图提交 → 订单产生 store-credit payment，金额 = `min(请求金额, 最终 outstanding_balance)`，`amount_due` 相应减少；提交时余额不可用 → **不落单**。
- **AC-006** ← FR-005：礼品卡意图与余额意图**互斥**（两个方向都拒绝）。
- **AC-007** ← FR-006：购物车载荷含 `store_credit.amount` / `display_amount`。
- **AC-008** ← FR-007：`payments` / `fulfillments` 的 legacy 分支写 `cart.legacy_flow.used` 日志（`cart_` 前缀不写）。

> 回归与知识同步属**验证证据**（见 §9），不单列 AC；`prd verify` 只对 AC-001..008 计测试覆盖。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 关键词 | 结果 | 是否满足 |
|---|---|---|---|---|
| App | `backend/app/` | store_credit | 无宿主层实现 | — |
| Core | `pallastrade_core/app/` | store_credit / AddStoreCredit | `services/pallastrade/checkout/add_store_credit.rb`（权威：`min(amount, outstanding_balance)` + 多张余额按优先级取用）、`models/pallastrade/store_credit.rb`（`amount_remaining` / `available` / `for_store`）、`models/pallastrade/order/store_credit.rb`、`lib/pallastrade/core/dependencies.rb`（`checkout_add_store_credit_service`） | **权威服务复用，不新写资金逻辑** |
| API | `pallastrade_api/app/` | store_credits | `store/carts/store_credits_controller.rb`（`require_authentication!` + `find_cart!` → **404 根因**）、`admin/orders/store_credits_controller.rb`（admin 侧，不受影响）、`shopping_cart_serializer.rb`（无 `store_credit` 字段 → 需补）、`carts/payments_controller.rb` / `carts/fulfillments_controller.rb`（**观测日志缺失点**） | **本次改动点** |
| Admin | `pallastrade_admin/app/` | store credit | `store_credits_controller` / `store_credit_categories`（admin 管店余额，走 Admin API） | 不受影响 |
| Storefront | `storefront/src/` | storeCredit | 仅展示（`OrderTotals` / `PaymentInfo` / order-placed 页文案），**不调用** `carts.storeCredits.*` | 受益方（零改动） |
| Platform | `platform/packages/sdk/` | storeCredits | `carts.storeCredits.apply/remove` 已存在（legacy 语义） | 无需改动 |

**结论**：改动集中在 Core（车侧意图服务 + 提交兑现）+ API（双解析 + 序列化 + 观测日志）；storefront/SDK 零改动。

## 7. 技术影响

- **修改**：`carts/store_credits_controller.rb`、`carts/payments_controller.rb`、`carts/fulfillments_controller.rb`、`carts/submit.rb`、`carts/apply_gift_card.rb`（互斥）、`shopping_cart_serializer.rb`、`ai/skills/pallastrade-*`、`harness/scenarios/scenarios.json`、`docs/research/RESEARCH-20260913-…` §9.3
- **新增**：`carts/apply_store_credit.rb`、`carts/remove_store_credit.rb`、`controllers/concerns/pallastrade/api/v3/legacy_flow_observable.rb`、spec（服务 + 请求 + 提交）
- **数据库**：无迁移
- **接口**：`POST/DELETE /api/v3/store/carts/{id}/store_credits` 语义扩展（兼容 legacy）；购物车载荷新增 `store_credit`

## 8. 测试计划

- **新增**：`spec/services/pallastrade/carts/store_credit_spec.rb`（AC-001/002/003/004/006 + NFR 零资金副作用）、`spec/requests/api/v3/store/carts/store_credits_spec.rb`（AC-001/002/003/004/007/008）
- **更新**：`spec/services/pallastrade/carts/submit_spec.rb`（AC-005：金额 = `min(请求, 最终 outstanding)`；不落单）
- **验证器**：`p1-order-flow-rspec` 扩入两个新 spec 文件（复用注册验证器，避免新建）
- **dev 实测**：`cart_` 无 JWT → 401（不再 404 `cart_not_found`）；有 JWT + 余额 → 201 且 `private_metadata` 落额；提交 → 订单 store-credit payment 金额正确

## 9. 文档同步清单（知识同步门）—— 结论

| 资产 | 状态 | 结论 |
|---|---|---|
| OpenAPI（`backend/public/api-docs/store.yaml` + platform 副本） | ✅ 已更新 | store_credits 双解析 + 车阶段意图 + 互斥 + 错误码；`ShoppingCart.store_credit` |
| `ShoppingCart` 类型（typelizer / SDK dist） | ✅ 已重生成 | `store_credit: unknown \| null`（契约产物由 `scripts/ci/contracts.sh` 两步生成） |
| `ai/skills/pallastrade-api-v3/SKILL.md` | ✅ 已更新 | store_credits 端点条目 + legacy 端点流量观测说明 |
| `ai/skills/pallastrade-payments/SKILL.md` | ✅ 已更新 | 店铺余额车阶段=意图 + 提交权威服务 + 互斥规则 |
| `ai/skills/pallastrade-typescript-sdk/SKILL.md` | ✅ 已更新 | `carts.storeCredits.apply/remove` 双解析语义 |
| `harness/scenarios/scenarios.json` | ✅ 已更新 | GS-118（双解析 + 意图 + 互斥 + 流量可观测） |
| `docs/research/RESEARCH-20260913-…` §9.3 | ✅ 已更新 | P2：切片 2 完成；余三端点按流量决定 |
| `platform/packages/README.md` | ✅ 已更新 | SDK 类型变更说明（`store_credit`） |
| 根 `README.md` | ✅ 已评估，无需更新 | 根 README 不承载 SDK 字段级契约 |
| 反模式库 / 任务规则 | ✅ 已评估，无需更新 | 未引入禁止模式；money 顺序与切片 1 一致 |

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-14 | 1.0 | 起草：切片 2 范围（store_credits canonical 化 + 余下 legacy 端点流量观测），含互斥规则与金额顺序约束（沿用切片 1 的 dev 教训） | AI |
| 2026-09-14 | 1.1 | 实施完成：`Carts::ApplyStoreCredit`/`RemoveStoreCredit`（意图；无余额/币种不符/金额非法/礼品卡冲突 → 明确错误码）；`Submit#apply_store_credit!`（金额管线之后兑现 + 零额跳过 + 按需建 `PaymentMethod::StoreCredit`）；控制器双解析 + 3 个新错误码（含 i18n）；`LegacyFlowObservable` concern + `payments`/`fulfillments` 观测；序列化 `store_credit`；规格 2 新文件 + submit 2 例；验证器扩入新 spec；契约重生成；知识同步（OpenAPI/Skill×3/GS-118/research §9.3/platform README） | AI |
| 2026-09-14 | 1.2 | 修复 GATE-2026-09-14T14-35-27（dev 提交实测暴露）：店铺已存在但**停用**的 store-credit 支付方式 → 原 ensure 仅 `save! if new_record?` → `active=false` 未落库 → `Checkout::AddStoreCredit` 的 `available` 作用域取不到 → `RuntimeError`（500）。改为**状态有变更即落库**；并且把权威服务的 raise 收敛为「提交失败、不落单」而不是 500；dev 实测：激活后提交成功产出 store-credit payment | AI |
