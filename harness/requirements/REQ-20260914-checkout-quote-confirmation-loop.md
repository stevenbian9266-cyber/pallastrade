# REQ-20260914-checkout-quote-confirmation-loop — cart_ 报价确认闭环（expected versions + 409 页内差异确认）

> 关联 PRD：`docs/prd/checkout/PRD-20260914-checkout-quote-confirmation-loop.md`（implementing）
> 来源：用户指令「同时做1和2」→ ②（research §9.1 P0-d / §11 PRD-3 行）
> Task：`TASK-20260914022332-329e9c99`；Gate：`GATE-2026-09-14T02-23-40`（feature）
> 产出：BFF 透传 `expected_*` 并回传 quote；`cart_` 页 409 → 页内差异确认（零跳转、零自动扣款）

## Step 0：跨层搜索（已执行）

| 层 | 路径 | 结果 |
|---|---|---|
| App | `backend/app/` | 无宿主层实现 |
| Core | `pallastrade_core/app/` | `transactions/start.rb`（`expected_price_version` → `quote_changed` 带 order_id）、`payment_sessions/start.rb`（`ensure_fresh_quote` → `checkout_version_conflict` + compact 最新 quote） |
| API | `pallastrade_api/app/` | `error_handler.rb` 错误码汇集；无契约变更 |
| Admin | `pallastrade_admin/app/` | 无 |
| Storefront | `storefront/src/` | `app/api/checkout/start/route.ts`（未传 `expected_*`）、`components/checkout/UnifiedCheckout.tsx`（`quote_changed`/`checkout_version_conflict` → `router.replace(or_?notice=quote_changed)`）、`messages/*.json` ×5 |
| Platform | `platform/packages/sdk/` | `src/types/index.ts` L93-94 已含 `expected_checkout_version` / `expected_price_version` |

**结论**：后端 + SDK 已就绪，缺口在 storefront BFF 与 UI（无重复实现）。

## Step 1：Skill 咨询

| Skill | 状态 | 关键结论 |
|---|---|---|
| `pallastrade-storefront` | ✅ 已读 | Checkout 错误分流按 `code`；`normalizeErrorMessage` 为唯一文案格式化入口；Money 契约（raw 判逻辑 / display 渲染）；五语言键须齐备 |
| `pallastrade-api-v3` | ✅ 已读 | BFF 错误信封 `{ error: { code, message } }` + 顶层 `order_id`；409 语义由后端权威 |
| `pallastrade-customization` | ✅ 已读 | 决策树：本次为 storefront BFF/UI 扩展，不涉 core 定制（无需 decorator/dependency） |
| `pallastrade-prd` | ✅ 已读 | PRD → 用户确认 → gate → REQ → AC↔测试 → 知识同步门 |

## 需求标题

`cart_` 页 Pay Now 携带客户端所见报价版本（`expected_checkout_version` / `expected_price_version`）；冲突时**留在页内**展示逐步差异并要求重新点击。

## 任务类型

优化迭代（storefront-only；消费既有后端能力）

## 验收标准（AC）

见 PRD §5（AC-001..AC-009）。

## 影响面

- **修改**：`storefront/src/app/api/checkout/start/route.ts`、`storefront/src/components/checkout/UnifiedCheckout.tsx`、`storefront/messages/{de,en,es,fr,pl}.json`
- **知识**：`ai/skills/pallastrade-storefront/SKILL.md`、`harness/scenarios/scenarios.json`（GS-111）
- **测试**：`components/checkout/__tests__/UnifiedCheckout.test.tsx`、`lib/__tests__/checkout-i18n-keys.test.ts`
- **数据库 / 后端 / API 契约 / SDK**：无变更

## 实施结果（2026-09-14 完成）

| 项 | 结果 |
|---|---|
| BFF 透传 + quote 回传（FR-001..003） | ✅ `CheckoutStartBody.expected_*` 顶层透传；`readQuote()`（`orders.checkout.get` → version/price_version + delivery/discount/amount_due raw+display）；成功与冲突响应均附 `quote` |
| UI 快照 + 页内差异（FR-004..006） | ✅ `lib/checkout-quote.ts`（sessionStorage 快照、`expectedVersions`、`diffQuotes`）；`UnifiedCheckout` 渲染 `checkout-quote-diff`（Shipping/Promotion/Amount due 旧→新），**零跳转、零自动重试**；降级：无快照/无 quote 时仍页内提示 |
| i18n 五语言（FR-007） | ✅ `quoteChangedTitle` / `quoteChangedBody` / `quoteConfirmAgain` / `quoteRowShipping` / `quoteRowPromotion` / `quoteRowAmountDue` |
| 知识同步（FR-008） | ✅ storefront Skill（Checkout 错误分流段改写） + scenarios GS-111（mustDo 改为页内确认 + expected 快照） |

## 验证与证据（2026-09-14）

| 证据 | 结果 |
|---|---|
| 定向 vitest（UnifiedCheckout + i18n 键） | ✅ 33 passed（含 AC-001..005/007；旧 `or_` 断言已按新行为改写） |
| `pnpm check`（biome） | ✅ 0 error |
| `pnpm typecheck` | ✅ exit 0 |
| 全量 storefront 套件（验证器） | ⏳ 见任务证据 |
| `harness prd verify` / `sync-check --ack` | ⏳ 见任务证据 |

## 后续任务

| # | 内容 |
|---|---|
| PRD-4 | 优惠码断面（`cart_` 阶段端点决策 + legacy 观测）——需用户决策 |
| 后续 | `or_` 页的 `?notice=quote_changed` 横幅保留为兜底；若未来 `or_` 也需页内差异，可复用本 PRD 的差异组件 |
