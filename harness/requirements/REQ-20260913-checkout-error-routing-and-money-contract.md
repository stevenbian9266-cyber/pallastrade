# REQ-20260913-checkout-error-routing-and-money-contract — Checkout 交易错误落点分流 + Money 契约

> 关联 PRD：`PRD-20260913-checkout-txn-error-routing`、`PRD-20260913-checkout-money-contract`（均 approved）
> 来源：用户指令「根据 `docs/research/RESEARCH-20260913-checkout-plan-review-and-decision.md` 开始实施，PRD 要更细」（2026-09-13）
> 上游依据：`RESEARCH-20260913-checkout-plan-review-and-decision.md` §9.1（P0-a/P0-c）、§9.2（错误分流规则表）、源规格 §16/§26/§27/§33
> Task：`TASK-20260913151241-be854171`；Gate：`GATE-2026-09-13T15-13-06`（bugfix）
> 产出：storefront 错误分流 + Money 契约修复（含测试与 Skill 同步）

## Step 0：跨层搜索（已执行）

| 层 | 路径 | 关键词 | 结果 | 已满足？ |
|---|---|---|---|---|
| App | `backend/app/` | error / quote / INVENTORY / checkout | 无宿主层实现（本次 storefront-only） | 否 |
| Core | `pallastrade_core/app/` | 同上 | 错误码权威：`transactions/start.rb`（quote_changed / INSUFFICIENT_STOCK / INVENTORY_CHANGED；INV-P3-2 Reserve-before-PaymentSession）、`payment_sessions/start.rb`（checkout_version_conflict / checkout_not_ready）、`terminal_transaction_for`（INVENTORY_RECOVERY_REQUIRED / transaction_not_payable）；`DisplayMoney`（raw+display 双轨） | 只读权威 |
| API | `pallastrade_api/app/` | 同上 | `error_handler.rb`（ERROR_CODES / 409）、`checkout_serializer`（raw + display 字段齐备） | 契约已具备 |
| Admin | `pallastrade_admin/app/` | checkout | 无相关面 | — |
| Storefront | `storefront/src/` | `parseFloat(.*display_` / handlePayNow / notice | `UnifiedCheckout.tsx`（默认跳结果页；savings 合并）、`OrderPaymentContent.tsx`（L112/L118 display 判逻辑）、`payment-result/[id]/page.tsx`、`lib/errors.ts`、`messages/*.json`（5 语言） | **本次改动点** |
| Platform | `platform/packages/` | display_ / CheckoutView | SDK 类型含 raw+display；无逻辑 | — |

**结论**：改动全部落在 storefront 展示/路由层；后端/SDK/BFF 契约无需变更；`harness prd new` 查重通过（2 份全新 PRD）。

## Step 1：Skill 咨询

| Skill | 状态 | 关键结论引用 |
|---|---|---|
| `pallastrade-storefront` | ✅ 已读（Checkout 章节 + Changelog + BFF 错误契约 + 5 语言 i18n + 客户端组件规则） | ① 错误展示必须经 `lib/errors.ts#normalizeErrorMessage`（React #31 白屏事故防线）；② `cart_` 主流程"Never redirect to checkout/or_ for a second Pay"（仅错误分流跳转，成功路径不动）；③ totals 以 API 字段为准；④ BFF 错误信封 `{ error: { code, message } }` + 顶层 `order_id` 是权威契约 |
| `pallastrade-prd` | ✅ 已读 | PRD → 用户确认 → gate → REQ → AC↔测试映射（`prd verify`）→ 知识同步门（`sync-check --ack`） |

## 需求标题

把"提交后"交易错误按 `code` 分流到正确落点与文案（quote / 库存 / 恢复 / 不可支付 / 未就绪），并修复 Money 契约（raw 判逻辑 / display 仅渲染）与节省口径。

## 任务类型

Bug 修复（storefront-only）

## 验收标准（AC）

见两份 PRD §5（AC-001..010 / AC-001..006），全部映射到 vitest 用例或 review 证据。

## 影响面

- **修改**：`storefront/src/lib/errors.ts`、`components/checkout/UnifiedCheckout.tsx`、`components/checkout/OrderPaymentContent.tsx`、`app/[country]/[locale]/(checkout)/payment-result/[id]/page.tsx`、`messages/{de,en,es,fr,pl}.json`、`lib/emails/order-confirmation.tsx`、`lib/webhooks/handlers.ts`
- **测试**：`components/checkout/__tests__/{UnifiedCheckout,OrderPaymentContent}.test.tsx`、`payment-result/[id]/__tests__/page.test.tsx`
- **文档**：`ai/skills/pallastrade-storefront/SKILL.md`、`docs/prd/README.md`、本 REQ
- 接口 / 数据库 / 迁移：**无**

## 实施结果（2026-09-13 完成）

| 项 | 结果 |
|---|---|
| 错误分流（PRD-A FR-001..010） | ✅ `lib/errors.ts#extractErrorCode`；`UnifiedCheckout` 按 code 分流；`OrderPaymentContent` `?notice=quote_changed` 横幅；`payment-result` `?notice=recovery\|processing` 覆盖文案 + 抑制重试入口 |
| Money 契约（PRD-B FR-001..005） | ✅ `OrderPaymentContent` raw 判逻辑（`delivery_total`/`tax_total`）；邮件 `order-confirmation` raw 入参 + 调用方传 raw；TOTAL SAVINGS 仅促销折扣 |
| i18n | ✅ 5 语言 × 8 键（`checkout`×4 + `paymentResult`×4） |
| 测试 | ✅ 新增/更新 15 用例 + 2 守护测试；`prd verify` 两份 PRD **全部 AC 有测试覆盖** |
| 知识同步 | ✅ Skill 更新（错误分流 + Money 契约 + Changelog）、场景库 GS-111/GS-112、`sync-check --ack` ×2、知识环 7/7 |

## 验证与证据

| 证据 | ID / 结果 |
|---|---|
| `chk-p1-4b-storefront`（checkout 组件） | `EVD-20260913153246-801c516e43` ✅ |
| `chk-p1-4c-storefront`（payment-result 页面） | `EVD-20260913153257-d371e9e980` ✅ |
| `storefront-test`（全量 vitest） | `EVD-20260913153340-f4b87d378f` ✅ |
| `prd verify` | `PRD-20260913-checkout-txn-error-routing` 全部 AC ✅；`PRD-20260913-checkout-money-contract` 全部 AC ✅ |
| `sync-check --ack` | 两份 PRD 均已确认 |

## 后续任务

| # | 类型 | 内容 |
|---|---|---|
| PRD-3 | 优化 | 报价确认闭环（`cart_` 页 Pay Now 携带 expected versions + 409 页内确认）——**feature gate，需用户确认后实施** |
| PRD-4 | 需求 | 优惠码断面（`cart_` 阶段端点决策 + legacy 观测）——**需用户决策** |
