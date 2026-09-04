# CHK-P1-5 — Checkout Quote-Conflict 409（expected_version / expected_price_version）

> 日期：2026-09-04 ｜ PRD：`PRD-20260903-checkout-chk-p1-1...`（§12 CHK-P1-2/3 DEFERRED 落地）
> Task：`TASK-20260903164013-b775db8f`；Gate：`GATE-2026-09-03T16-41-09`
> 范围（用户确认 2026-09-04）：顶层参数；Refresh 后比对；409 details = compact latest quote。

## 1. 语义

- 客户端在创建支付会话时携带所见 quote 期望值：`expected_version`（checkout_version）/ `expected_price_version`（price_version），均为可选顶层参数。
- quote-active 标准流订单（P1-3 gate 同域）：过期先自动 Refresh（既有 P1-3）→ 就绪校验 → **Refresh 后比对**；任一不匹配 → `failure`，不建会话。
- 不提供 expected → 行为与 P1-3 完全一致（无 quote/legacy/completed 直通；幂等/reuse/operation_key 不变）。

## 2. 409 契约

- `HTTP 409` + `{ error: { code: 'checkout_version_conflict', message, order_id, latest: { version, price_version, expires_at, amount_due, display_amount_due } } }`。
- `error_handler` 结构化分支：`checkout_version_conflict` → `:conflict`（其余 code 维持默认 status）；`code/message` 之外键（order_id/latest）经既有 details 透传。
- 客户端收到 409 → 展示最新金额/内容 → 重新 GET checkout 确认 → 带新 expected 重试。

## 3. 实现

- core `PaymentSessions::Start#call` 增可选 `expected_version:/expected_price_version:`；`ensure_fresh_quote` 重构为 refresh→readiness→conflict 顺序，新增 `quote_conflict?`/`latest_quote`。
- api `orders/payment_sessions_controller#create`：permit 增 `expected_version`/`expected_price_version`（`payment_session_attributes + [..]`）并传参。
- api `error_handler`：`ERROR_CODES[:checkout_version_conflict]` + 409 映射。
- 测试：start_spec +5（匹配/version 冲突/price 冲突/过期后 version 冲突/过期后仅 price 期望放行）；request spec +2（201 匹配 / 409 形状）。

## 4. 测试结果

- P1-5 集 + 回归：start 17 + order_payment_sessions 7 + cart_payment_sessions + checkout_controller + versioning 全绿（RuboCop 0）。

## 5. DEFERRED

- 前端消费 409（OrderPaymentContent/收银台「价格已更新」提示 + 带 expected 重试）→ P1-4B/4C。
