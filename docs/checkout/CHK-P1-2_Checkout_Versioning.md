# CHK-P1-2 — Checkout Version / Price Version / Expiration / Recalculate / Refresh

> 日期：2026-09-03 ｜ PRD：`PRD-20260903-checkout-chk-p1-1...`（§12 CHK-P1-2）
> Task：`TASK-20260903130524-bf0493f2`（critical：含 migration）；Gate：`GATE-2026-09-03T13-05-36`
> 范围（用户确认选项 A）：版本/过期/refresh 本轮；Payment Start Gate 留 P1-3。

## 1. DB 变更（受控 migration，dev+test 已应用）

- `20260903140000_add_checkout_versioning_to_pallastrade_orders`：orders + `lock_version` / `price_version` / `checkout_expires_at`
- `20260903150000_fix_checkout_versioning_on_pallastrade_orders`：**移除 `lock_version`，改加 `checkout_version`**（integer default 0）
  - 原因：Order 的 AR `locking_column` 已被 state_machines 设为 `state_lock_version`（state 转换锁）——`lock_version` 不参与乐观锁；改用显式 `checkout_version` 自增列，由 OrderCheckout 统一维护（更贴合 PRD「正式版本语义，禁 updated_at/public_metadata 冒充」）。

最终列：`orders.checkout_version`(int, 内容版本，mutation/recalc/refresh 递增)、`orders.price_version`(string, 金额权威列 SHA256 指纹)、`orders.checkout_expires_at`(datetime 可空, 报价过期)。

## 2. 服务

| 服务 | 行为 |
|---|---|
| `OrderCheckout::Policies` | `quote_window`（默认 30min，ENV `CHECKOUT_QUOTE_WINDOW_MINUTES` 覆盖；不引入未注册 Config 键） |
| `OrderCheckout::Recalculate` | `with_lock` + `OrderUpdater.new(order).update`（幂等 recalc，含 AdjustmentsUpdater tax/promo）→ 重算并落 `price_version`（金额列指纹）+ `checkout_version +1` → `checkout_expires_at` 为空时初始化 now+window |
| `OrderCheckout::Refresh` | `!completed?` → Recalculate → 续期 `checkout_expires_at = now + window` → 最新 CheckoutView |
| `OrderCheckout::Expiration` | 只读 `expired?` / `expires_in`（无 expires_at 视为未过期，legacy 兼容；供 P1-3 支付闸门复用） |
| 接入 | `UpdateAddress`/`SelectShipping` 成功后调 Recalculate（补 tax/price_version）；`UpdateContact` 手动 `checkout_version +1`（email 无关金额不 recalc） |

## 3. API / View

- CheckoutView/`CheckoutSerializer` 正式输出：`version`(=checkout_version)、`price_version`、`expires_at`(=checkout_expires_at iso8601)。
- 并发冲突：Recalculate 在 `with_lock` 下串行；客户端 stale 检测（期望 version + CHECKOUT_VERSION_CONFLICT 409）为 P1-3/后续 API 能力（本包未实现——`lock_version` 乐观锁不可用的技术约束已记录）。

## 4. 测试结果

- 新增 P1-2 用例 + 1A/1B 全量：**55/55 绿**（versioning 10 + view 14 + mutation 7 + serializer 11 + controller 13）
- Order 域回归 28/28 绿（customer orders/shipping/order payment/parent-child/submit）；RuboCop 0
- migration 仅加列/删列，无破坏性变更

## 5. DEFERRED

- **Payment Start Gate**（expired 阻止开新 PaymentSession；PaymentSession 记录 price_version）→ P1-3
- Invalidation 图的状态化标记 / READY / CheckoutSnapshot → P1-3
- 客户端期望版本 + CHECKOUT_VERSION_CONFLICT 409 端点语义 → P1-3/后续
