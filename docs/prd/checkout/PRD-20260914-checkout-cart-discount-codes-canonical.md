# PRD-20260914-checkout-cart-discount-codes-canonical

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-14 |
| 来源 | research `RESEARCH-20260913` §9.1 P0-e / §5.1 / §11 PRD-4 行（用户确认项：端点方向）—— 用户指令「继续」授权按本 PRD 决策实施 |
| 分类 | checkout |
| 关联 Skill | pallastrade-promotions / pallastrade-api-v3 / pallastrade-storefront |
| 关联 REQ | REQ-20260914-checkout-cart-discount-codes-canonical.md |
| 关联 PRD | 关联 PRD-20260913-checkout-txn-error-routing（错误码口径）；无重复 PRD |
| 需求类型 | 需求（断链修复 + 端点收敛） |

## 1. 背景与目标

- **实测事实（dev，2026-09-14）**：`POST /api/v3/store/carts/cart_GpMUcnUYI5/discount_codes` → **403 `access_denied`**。原因：该端点用 legacy `CartResolvable#find_cart!`（`current_store.carts` = 旧 `PallasTrade::Order` 关联），解析不到 `pallastrade_carts`（`cart_` 前缀）——即 **`cart_` 页的优惠码功能当前是坏的**（storefront BFF `/api/checkout/coupon` 正是打这个 URL）。
- **结构缺口**：`PallasTrade::Cart` **无 `coupon_code` 字段**；`Carts::Submit` **完全不携带优惠码** → 即使解析能过，cart 阶段的码也无法流入订单金额管线。权威套用样例 = `Orders::Create#apply_coupon`（`order.coupon_code=` + `PromotionHandler::Coupon.new(order).apply`）。
- **目标**：① `cart_` 阶段优惠码**立即可用**（修 403）；② 码在「购物车 → 提交」链路上**可追溯地生效**；③ legacy 路径保持兼容 + 加观测标记，为收敛留数据。
- **成功指标**：`cart_` 端点不再 403；有效码 → cart 上可见且提交后 `order.discount_total` 反映折扣；无效/过期码 → 结构化错误码（不静默丢失）；legacy 端点行为零变化。

## 2. 用户故事 / 场景

- 作为**顾客**，我在购物车页输入优惠码，希望立刻被接受（或在金额变化时得到明确解释），而不是报 403。
- 作为**运营**，我希望应用码不消耗码（占用发生在下单核销）；码在购物车与提交之间失效时必须**明确报错**，而不是静默按原价下单。
- 场景：① 有效码 → 接受；② 无效码 → `coupon_code_not_found`；③ 过期码 → `coupon_code_expired`；④ 移除码（幂等）；⑤ 购物车带码提交 → 订单折扣命中；⑥ 提交时码已失效 → **提交失败、不落单**；⑦ legacy 购物车（旧 Order 型）→ 行为不变。

## 3. 功能需求（FR）

- **FR-001**（解析）：`Store::Carts::DiscountCodesController` 支持双类型解析 —— `cart_` 前缀 → `current_store.shopping_carts`（含用户/guest token 作用域）；否则沿用 legacy `find_cart!`。
- **FR-002**（应用）：新增 `PallasTrade::Carts::ApplyDiscountCode`：规范化（去空格/大小写不敏感）、校验存在且未过期（`store.promotions.with_coupon_code`），成功则写入 `cart.private_metadata['discount_code']` 并保存；失败返回 `coupon_code_not_found` / `coupon_code_expired`。
- **FR-003**（移除）：`DELETE .../discount_codes/:code` 清除 cart 上的码（幂等：无码也成功）。
- **FR-004**（提交携带）：`Carts::Submit` 在金额管线前套用码（镜像 `Orders::Create#apply_coupon`）；成功 → 订单折扣命中；**失败 → 提交失败并返回 `coupon_code_*`（不落单、不静默按原价）**。
- **FR-005**（legacy 观测）：legacy 解析分支加 `Rails.logger.info('[legacy-discount-codes] …')` 观测标记（行为不变），为 legacy 收敛提供依据。
- **FR-006**（契约与知识）：OpenAPI ×2（`POST/DELETE /carts/{id}/discount_codes` 标注双解析 + 错误码）、storefront Skill（cart_ 优惠码可用 + 错误口径）、scenarios GS 条目。
- **FR-007**（范围外）：`gift_cards` / `store_credits` 的 `cart_` 端点（另开 PRD）；`or_` 阶段 `POST /orders/:id/checkout/promotions`；后台促销管理。

## 4. 非功能需求（NFR）

- **不静默丢码**：任何阶段失败必须返回结构化错误（金额相关不允许“悄悄变贵”）。
- **码不消耗**：应用码只写意图；占用/核销仍由 `PromotionRedemption`（reserve/commit/release）负责。
- **兼容**：legacy 请求路径与响应形状不变；`cart_` 为增量能力。
- **数据**：**不新增数据库列**（用 `cart.private_metadata['discount_code']`）。
- **并发**：提交链路已有的 `with_order_lock` / cart 行锁语义不变。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001** ← FR-001/002：`POST /carts/{cart_xxx}/discount_codes`（有效码）→ 2xx 且 `cart.private_metadata['discount_code']` = 规范化码（请求 spec）。
- **AC-002** ← FR-002：无效码 → 422 `coupon_code_not_found`；过期码 → 422 `coupon_code_expired`（请求 spec）。
- **AC-003** ← FR-003：`DELETE` 清除码且幂等（请求 spec ×2）。
- **AC-004** ← FR-004：购物车带码提交 → `order.discount_total` 反映折扣（服务 spec）；无码提交 → 不变（回归）。
- **AC-005** ← FR-004：提交时码失效 → 提交失败且 **Order 未创建**（服务 spec）。
- **AC-006** ← FR-005：legacy 分支仍可解析（既有 spec 回归绿）+ 观测日志标记存在。
- **AC-007** ← FR-006：OpenAPI 两份同步 + Skill/场景库同步（doc 证据）。

> 🔁 **查重回写**：`harness prd new` 自动查重（相似度 > 0.3 阻止新建）。
> 若本需求命中相似 PRD，用 `harness prd update --path <原PRD> --title "<需求>"` 回写原 PRD，
> 并在原文档内完整更新（背景/FR/AC/变更记录），**不得新建重复 PRD**；确属全新需求才 `--force`。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | coupon / discount | 无宿主层实现 | — |
| Core | `pallastrade_core/app/` | coupon_code / PromotionHandler | `models/pallastrade/order.rb` L124（`attr_reader :coupon_code`）、`services/pallastrade/orders/create.rb` L37/L139-150（**权威套用样例**）、`models/pallastrade/promotion_handler/coupon.rb`（错误码 `coupon_code_not_found`/`_expired`）、`promotion.rb`（`with_coupon_code`、`coupon_codes`）、`services/pallastrade/carts/submit.rb`（**无 coupon 处理**）、`models/pallastrade/cart.rb`（**无 coupon_code 列**，有 `private_metadata`） | 部分（需新增 cart 侧套用） |
| API | `pallastrade_api/app/` | discount_codes / CartResolvable | `store/carts/discount_codes_controller.rb`（`find_cart!` → **403 根因**）、`concerns/cart_resolvable.rb`、`store/carts_controller.rb`（`find_shopping_cart_for_association` 可复用解析形态） | **本次改动点** |
| Admin | `pallastrade_admin/app/` | promotions admin | 不涉（FR-007 范围外） | — |
| Storefront | `storefront/src/` | coupon BFF | `app/api/checkout/coupon/route.ts`（`carts.discountCodes.apply/remove`，打同一 URL，**无需改动**） | 是（受益方） |
| Platform | `platform/packages/sdk/` | discountCodes | `carts.discountCodes.apply/remove` 已存在，**无需改** | 是 |

**结论**：修复点在 API 层解析 + Core 层 cart 侧套用；storefront/SDK 零改动即可恢复功能。

## 7. 技术影响

- **修改**：`pallastrade_api/app/controllers/pallastrade/api/v3/store/carts/discount_codes_controller.rb`（双解析 + 观测）、`pallastrade_core/app/services/pallastrade/carts/submit.rb`（携带码）、`backend/public/api-docs/store.yaml` + `platform/docs/api-reference/store.yaml`、`ai/skills/pallastrade-storefront/SKILL.md`、`harness/scenarios/scenarios.json`
- **新增**：`pallastrade_core/app/services/pallastrade/carts/apply_discount_code.rb`、`pallastrade_core/app/services/pallastrade/carts/remove_discount_code.rb`（或并入前者）、spec（服务 + 请求）
- **数据库**：无迁移（`private_metadata` 承载码）
- **接口**：`POST/DELETE /api/v3/store/carts/{id}/discount_codes` 语义扩展（兼容 legacy），错误码沿用 promotion 体系

## 8. 测试计划

- **新增**：`backend/spec/services/pallastrade/carts/apply_discount_code_spec.rb`（AC-002）、`backend/spec/requests/api/v3/store/carts/discount_codes_spec.rb`（AC-001/002/003）
- **更新**：`backend/spec/services/pallastrade/carts/submit_spec.rb`（AC-004/005）
- **验证器**：`p1-order-flow-rspec`（含 carts 请求规格）/ `backend-rspec`
- **AC 映射**：见 §5 逐条标注（测试内以 `PRD-20260914-checkout-cart-discount-codes-canonical AC-xxx` 注释关联）

## 9. 文档同步清单（知识同步门）—— 结论

| 资产 | 状态 | 结论 |
|---|---|---|
| OpenAPI ×2（`backend/public/api-docs/store.yaml` + `platform/docs/api-reference/store.yaml`） | ✅ 已更新 | `POST`/`DELETE /carts/{cart_id}/discount_codes`：双解析语义 + 码持久化位置 + **应用不消耗码** + 提交时失效即失败 + 移除幂等 |
| `ai/skills/pallastrade-api-v3/SKILL.md` | ✅ 已更新 | 新增该端点的「双解析 + 意图持久化 + 提交兑现（失败不落单）」条目 |
| `harness/scenarios/scenarios.json` | ✅ 已更新 | 新增 **GS-114**（canonical 解析 / 意图持久化 / 应用不消耗 / 提交拒绝且不落单 / 契约与测试同步） |
| `ai/skills/pallastrade-promotions/SKILL.md` | ✅ 已评估，无需更新 | 本次未改变核销/占用语义（仍由 `PromotionRedemption` 负责），仅复用既有 `PromotionHandler::Coupon` |
| `ai/skills/pallastrade-storefront/SKILL.md` | ✅ 已评估，无需更新 | storefront BFF 与 SDK 零改动（`carts.discountCodes.*` 本就打该 URL） |
| `platform/packages/sdk` | ✅ 已评估，无需更新 | 端点与类型未变化 |
| `docs/prd/README.md` 索引 + 本 PRD 状态 | ✅ 已更新 | 状态 → `done`；索引由 `prd-status-sync --check` 校验 |
| 反模式库 / 任务规则 | ✅ 已评估，无需更新 | 未引入新的禁止模式（无 `permit!`、无未白名单参数、无新 DB 列） |
| `harness generated:check`（OpenAPI → SDK 类型） | ✅ 通过 | `no drift detected`（端点类型未变化，SDK 无需重建） |
| `ai/skills/pallastrade-prd/SKILL.md` / `AGENTS.md` / `.github/copilot-instructions.md` | ✅ 已评估，无需更新 | 本次未改变 PRD 流程或治理规则；变更类型仍落在既有约束内（gate/证据/知识环照常） |

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-14 | 0.1 | 初稿：dev 实测 403 确认断链；决策 = 双解析 canonical 端点 + cart 侧意图持久化 + 提交携带（失败即报错不静默）；待实施 | AI |
| 2026-09-14 | 1.0 | 实施完成：双解析（`cart_` → `shopping_carts`，legacy 分支加观测日志）、`Carts::ApplyDiscountCode`/`RemoveDiscountCode`（`private_metadata['discount_code']`）、`Carts::Submit` 提交前套用码（失败回滚不落单）；新增请求 spec（含过期码）与 submit spec 两例（15 例 0 失败）；OpenAPI ×2 + api-v3 Skill + GS-114 同步 | AI |
| 2026-09-14 | 1.1 | FR-005 观测增强（PRD-20260914-checkout-cart-store-credits-canonical FR-007 同波次）：legacy 分支日志由裸字符串升为统一结构化指标 `cart.legacy_flow.used`（`flow_type: legacy_cart_discount_codes`，保留 `[legacy-discount-codes]` 标记与 `requested_cart_id` 字段），使五个 legacy cart 端点的真实流量可按同一个 message 计数（payment_sessions 保持历史 key）；请求 spec 断言同步 | AI |
