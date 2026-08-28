# PRD-20260828-checkout-p8-前置校验-库存-风控-订单服务增强-flag-灰度

| 元数据 | 值 |
|---|---|
| 状态 | draft |
| 创建日期 | 2026-08-28 |
| 来源 | 需求：P8 前置校验 / 库存 / 风控 / 订单服务增强（flag 灰度） |
| 分类 | checkout（自动判定） |

> ⚠️ AI：请按 docs/prd/_TEMPLATE.md 完整扩充本文档（背景/FR/AC/跨层搜索/测试计划/文档同步清单），再进入用户确认。

---

# PRD-20260828-checkout-p8-前置校验-库存-风控-订单服务增强-flag-灰度

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-08-28 |
| 来源 | 需求：P8 前置校验 / 库存 / 风控 / 订单服务增强（flag 灰度） |
| 分类 | checkout（自动判定） |
| 关联 Skill | pallastrade-checkout / pallastrade-data-model / pallastrade-security / pallastrade-testing |
| 关联 REQ | REQ-20260828-order-lifecycle-p8.md |
| 关联 PRD | N/A（全新需求，`prd new` 新建） |
| 需求类型 | 新功能 |

> 🔁 **查重回写**：`prd new` 未命中相似 PRD（P8 为订单服务增强独立阶段）。

## 1. 背景与目标

- **一句话需求原文**：需求：P8 前置校验 / 库存 / 风控 / 订单服务增强（flag 灰度）
- **背景**：P0-P7 已完成父子单/拆单/合并支付/售后闭环。当前下单链路缺**统一前置校验**（黑名单、风控规则）、**防刷单**、以及**锁库存时机控制**（下单时 vs 支付时）。备注（`internal_note` / `customer_note`=special_instructions）与状态时间线（`StateChange`）已存在，本次不重复实现。
- **目标**：新增 `PallasTrade::Risk` 规则引擎 + `Checkout::Preflight` 前置校验服务（黑名单 + 登录强制 + 防刷单）接入 `Carts::Complete`；锁库存支持 `:order | :payment` 双模式。全程 flag/preference 灰度，默认关闭/现状零变化。
- **成功指标**：
  - 黑名单/风控/防刷单命中 → 统一 `code + message` 业务错误（无裸 422）
  - `:payment` 锁存模式下支付确认后库存锁定、cart 操作只校验
  - 全默认关闭时单笔下单流程零行为变化

## 2. 用户故事 / 场景

- 作为运营，我希望把恶意/违约用户拉黑（`users.blacklisted_at`），其下单被拦截并返回明确错误。
- 作为运营，我希望通过可配置规则（风控/防刷单）拦截异常下单（同用户高频下单）。
- 作为平台，我希望选择锁库存时机（下单时 `:order` 或支付确认时 `:payment`）。
- 场景列表：
  - 正常：普通用户下单不受影响（flag 关闭或规则未命中）
  - 异常：黑名单用户 → `user_blacklisted`；guest + guest_checkout 关 → `authentication_required`；超频 → `order_frequency_limit`；自定义规则命中 → 规则 code
  - 边界：`stock_reservation_strategy=:payment` 时 cart 操作不锁库存（仅校验）、支付确认后锁定

## 3. 功能需求（FR）

- FR-001：**前置校验服务** `PallasTrade::Checkout::Preflight`：`call(order:)` 依次检查——登录强制（guest 且 guest_checkout 关 → `authentication_required`）、`PallasTrade::Risk.evaluate`（黑名单/防刷单/自定义规则）→ 任一命中返回 `failure(order, { code:, message: })`，全过 `success(order)`。
- FR-002：**Risk 规则引擎** `PallasTrade::Risk`：`rules` 可注册（`PallasTrade::Risk.rules << RuleClass`，默认空）；内置 `BlacklistRule`（`user.blacklisted_at` 命中 → `user_blacklisted`）与 `OrderFrequencyRule`（同用户 N 分钟完成订单数 > `order_frequency_limit` → `order_frequency_limit`）；`evaluate(order:, user:, store:)` 返回首个命中的 `{ code:, message: }` 或 nil。
- FR-003：**接线** `Carts::Complete`：flag `checkout_preflight_enabled`（store preference 回退 Config，默认 false）开启时，在支付处理前调用 Preflight，失败即返回（不推进完成）。
- FR-004：**锁库存双模式** `Config[:stock_reservation_strategy]`（`:order` 默认 / `:payment`）：`:order` = 现状（cart 操作时 Reserve）；`:payment` = cart 操作只**校验库存**不落 reservation（`Reserve` 新增 `validate_only` 选项），支付确认后（`Carts::Complete` 支付成功后）真正 Reserve。
- FR-005：**数据/配置**：迁移 `users.blacklisted_at`（datetime，可空，可 down）；preferences：`checkout_preflight_enabled`（boolean false）、`order_frequency_limit`（integer nil=关）、`stock_reservation_strategy`（string 'order'）。

## 4. 非功能需求（NFR）

- 性能：Preflight 与 Reserve 均单事务内完成；规则评估纯内存（无网络）。
- 安全：黑名单/风控结果统一 `code + message`，不泄露内部细节；所有查询过 `current_store`。
- 兼容：全默认关闭/现状；`:order` 模式与 P0-P7 完全一致。
- 可维护：Risk 规则引擎开放注册（自定义规则可扩展）；Preflight 单一入口。

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：黑名单用户（`user.blacklisted_at` 设置）下单 → Preflight `failure { code: 'user_blacklisted' }`；flag 关闭时 Preflight 不被调用。
- AC-002 ← FR-001：guest 订单 + guest_checkout 关闭 → `failure { code: 'authentication_required' }`。
- AC-003 ← FR-002：注册自定义 Risk 规则并命中 → 返回规则 `{ code:, message: }`；多规则取首个命中。
- AC-004 ← FR-003：`order_frequency_limit` 设置后同用户 N 分钟内完成订单数超限 → `failure { code: 'order_frequency_limit' }`；默认 nil 不拦截。
- AC-005 ← FR-004：`:order`（默认）cart 操作建 reservation（现状）；`:payment` 时 cart 操作不建 reservation 且库存不足仍报错，支付确认后建 reservation。
- AC-006 ← FR-005：全默认（flag false / limit nil / strategy order）下单流程与 P7 前一致（回归）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | blacklist / risk / preflight | 无相关业务代码 | ❌ 无需在此层实现 |
| Core | `pallastrade_core/app/` | blacklisted_at / Risk / StockReservations / StateChange / internal_note | `users.blacklisted_at` **不存在**（需新增列）；`PallasTrade::Risk` **不存在**（需新建）；`StockReservations::Reserve/Release/Extend` 已存在（Reserve 在 cart 操作调用，`reserve_stock_on` preference 已有 'checkout'/'cart'）；`StateChange` 模型已有（状态时间线）；`Order#internal_note`（rich_text）+ `customer_note`（=special_instructions 别名）已有 | ❌ 需新建：blacklisted_at 列 + Risk 引擎 + Preflight 服务 + Reserve validate_only |
| API | `pallastrade_api/app/` | carts complete / preflight | `store/carts_controller.rb#complete`（调 `Carts::Complete`）；错误走 `render_service_error` | ❌ Carts::Complete 加 Preflight 接线（API 无需改） |
| Admin | `pallastrade_admin/app/` | internal_note / user | `orders/_internal_note` partial 已有；用户管理页无黑名单操作（后续增强） | ❌ P8 不改 Admin（黑名单展示后续） |
| Storefront | `storefront/src/` | checkout | 下单流程走 API | ❌ 不涉及 |
| Platform | `platform/packages/` | sdk | 无相关能力 | ❌ 不涉及 |

**结论**：黑名单列、Risk 引擎、Preflight 服务、Reserve validate_only 均为新建；库存/备注/时间线已存在（复用）。**不重复实现**现有备注/时间线能力。

## 7. 技术影响

- **pallastrade_core**：
  - 迁移 `.../add_blacklisted_at_to_users.rb`（datetime 可空）
  - 新增 `lib/pallastrade/risk.rb`（规则引擎）+ `lib/pallastrade/risk/blacklist_rule.rb` + `lib/pallastrade/risk/order_frequency_rule.rb`
  - 新增 `services/pallastrade/checkout/preflight.rb`
  - `services/pallastrade/stock_reservations/reserve.rb`（+`validate_only`）
  - `services/pallastrade/carts/complete.rb`（Preflight + :payment 模式支付后 Reserve）
  - `services/pallastrade/cart/{add_item,set_quantity,update,remove_line_item}.rb`（:payment 模式传 validate_only）
  - `configuration.rb`/`store.rb`/`initializers/pallastrade.rb`：3 个 preference
- **数据库**：迁移 `users.blacklisted_at`
- **API/Admin/Storefront/Platform**：无改动（错误经既有 `render_service_error`）
- **影响面**：`harness affected --base origin/main`（实施时运行）

## 8. 测试计划

- 新增测试文件：
  - `backend/spec/services/pallastrade/checkout/preflight_spec.rb`（AC-001/002/003/004/006）
  - `backend/spec/lib/pallastrade/risk_spec.rb`（规则注册/评估/首个命中）
  - `backend/spec/services/pallastrade/stock_reservations/reserve_strategy_spec.rb`（AC-005）
- 更新测试文件：`carts/complete_spec.rb` 相关回归（如存在）。
- 覆盖的 AC 映射：AC-001~004 → preflight_spec；AC-005 → reserve_strategy_spec；AC-006 → 回归。

## 9. 文档同步清单（知识同步门）

- [x] Skill 文档：`pallastrade-checkout`（前置校验/Risk/锁存双模式）、`pallastrade-data-model`（users.blacklisted_at）、`pallastrade-security`（下单风控规则）
- [x] 升级方案 `docs/research/RESEARCH-20260826-order-lifecycle-upgrade-plan.md` P8 段标记完成
- [x] 本 PRD 状态 done + `docs/prd/README.md` 索引
- [x] API 文档：无新端点（错误经既有 render_service_error，reviewed-no-change）
- [x] 反模式库 / 任务规则 / 场景库：评估无需更新
- [x] `pallastrade-testing`：沿用既有 RSpec 模式，无新增约定

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-28 | 0.1 | 初稿：P8 前置校验 / 库存 / 风控 / 订单服务增强（flag 灰度）；6 层跨层搜索完成 | AI |
| 2026-08-28 | 0.2 | 实施完成：`PallasTrade::Risk` 规则引擎（BlacklistRule + OrderFrequencyRule）+ `Checkout::Preflight`（Carts::Complete 前置接线）+ `render_service_error` 支持 ResultError/Hash 结构化错误 + `stock_reservation_strategy` 双模式（Reserve validate_only + :payment 支付后锁）+ 迁移 users.blacklisted_at + 3 组 preferences；后端 47 例回归全绿；quick/generated:check 通过；同步 checkout/data-model/security Skill + 升级方案 | AI |
