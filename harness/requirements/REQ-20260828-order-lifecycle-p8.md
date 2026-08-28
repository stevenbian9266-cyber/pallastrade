# REQ-20260828-order-lifecycle-p8 — 前置校验 / 库存 / 风控 / 订单服务增强（flag 灰度）

> 对应 PRD：`docs/prd/checkout/PRD-20260828-checkout-p8-前置校验-库存-风控-订单服务增强-flag-灰度.md`
> Task：`TASK-20260828151459-00695a0d` ｜ Gate：`GATE-2026-08-28T15-15-12`（Risk: critical）

---

## Step 0：跨层搜索（已执行，详见 PRD §6）

**结论**：
- `users.blacklisted_at` **不存在**（需新增迁移）
- `PallasTrade::Risk` **不存在**（需新建规则引擎）
- `StockReservations::Reserve/Release/Extend` 已存在（cart 操作时调用）；`reserve_stock_on` preference 已有
- `StateChange` 模型已有（状态时间线）；`Order#internal_note`（rich_text）+ `customer_note`（=special_instructions）已有
- **不重复实现**现有备注/时间线能力

## Step 1：Skill 文件咨询

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读（本会话 P6/P7） | 决策树：Settings → Config → Events → Dependencies → Admin/Ransack → Generators → Decorators → Extensions。P8 用 Config/preference flag + Core 服务/模型新建。 |
| `ai/skills/pallastrade-checkout/SKILL.md` | ✅ 已读（P5/P6/P7 会话 + 本会话） | 订单完成链路（P2-P7 段已同步）；`Carts::Complete` 完成流程；P8 在其前置插 Preflight、支付后插 Reserve(:payment)。 |
| `ai/skills/pallastrade-prd/SKILL.md` | ✅ 已读（本会话 P6） | 阶段 0-1：prd new → 6 层搜索 → 模板扩充 → 用户"实施"确认。 |
| `ai/skills/pallastrade-security/SKILL.md` | ✅ 已读（本会话） | 危险操作/反模式约束；P8 的风控/黑名单为新增能力，不涉及现有安全钩子（§8 危险操作保持）。 |

**按需 Skill（本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-data-model` | ✅ | ✅（P1 会话已读） | Order/User 模型扩展规范；新增列走迁移（可 down）。 |
| `pallastrade-testing` | ✅ | ✅（既有约定） | RSpec service spec 模式。 |

---

## 需求标题

下单前置校验（黑名单/登录强制/风控规则/防刷单）+ 锁库存双模式（:order/:payment），flag 灰度。

## 任务类型

新功能（flag 默认关闭/现状零变化）

## 需求描述

1. **P8a 前置校验**：迁移 `users.blacklisted_at`（datetime 可空）；`PallasTrade::Risk` 规则引擎（`rules` 注册 + `evaluate`）；内置 `BlacklistRule` + `OrderFrequencyRule`；`Checkout::Preflight` 服务（登录强制 + Risk 评估）→ 统一 `{ code:, message: }`；`Carts::Complete` 前置接线（flag `checkout_preflight_enabled`）
2. **P8b 防刷单**：`order_frequency_limit`（integer，默认 nil 关闭）——同用户 N 分钟内完成订单数超限拦截
3. **P8c 锁库存双模式**：`Config[:stock_reservation_strategy]`（:order | :payment，默认 :order）；`Reserve` 加 `validate_only`；`:payment` 模式 cart 操作只校验、支付确认后（Carts::Complete 支付成功）真正 Reserve

## 验收标准

- AC-001~004 → `backend/spec/services/pallastrade/checkout/preflight_spec.rb` + `backend/spec/lib/pallastrade/risk_spec.rb`
- AC-005 → `backend/spec/services/pallastrade/stock_reservations/reserve_strategy_spec.rb`
- AC-006 → 回归

详见 PRD §5。

## 实施要点

- **pallastrade_core**：迁移 `add_blacklisted_at_to_users`；`lib/pallastrade/risk.rb` + `lib/pallastrade/risk/{blacklist_rule,order_frequency_rule}.rb`；`services/pallastrade/checkout/preflight.rb`；`services/pallastrade/stock_reservations/reserve.rb`（+validate_only）；`services/pallastrade/carts/complete.rb`（Preflight + :payment Reserve）；`services/pallastrade/cart/{add_item,set_quantity,update,remove_line_item}.rb`（:payment 传 validate_only）；3 个 preference（store.rb/configuration.rb/initializers）
- **API/Admin/Storefront/Platform**：无改动
- **错误**：经既有 `render_service_error`（code+message）

## 测试计划

- 新增 `preflight_spec.rb`、`risk_spec.rb`、`reserve_strategy_spec.rb`
- 回归 Carts::Complete 相关

## 文档同步

- Skill：checkout（Preflight/Risk/锁存双模式）、data-model（blacklisted_at）、security（风控规则）
- 升级方案 P8 段标记完成；PRD §9/§10；docs/prd/README.md 索引
