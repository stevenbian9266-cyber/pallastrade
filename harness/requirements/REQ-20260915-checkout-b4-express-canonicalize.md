# REQ-20260915-checkout-b4-express-canonicalize

> 关联 PRD：`docs/prd/checkout/PRD-20260915-checkout-checkout-收尾收敛-b4-express-钱包-canonicalize-legacy-会话-transacti.md`
> 关联任务：TASK-20260915010631-5c616a13 · Gate `GATE-2026-09-15T01-06-43`
> 前置批次：B1（CheckoutView）、B2（购物车抵扣）、B3（库存四态 + 履约结果页），均已 done

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | `express` / `payment_session` | 仅生成类型产物 | 否（无需改动） |
| Core Gem — services | `pallastrade_core/app/services/pallastrade/` | `transactions` / `payment_sessions` | `transactions/{start,reserve_inventory,finalize,recover}.rb`（canonical：Start → Reserve → PaymentSessions::Start；失败不建会话）、`payments/payment_combinations/*` | 是（canonical 链已就绪，钱包直接复用） |
| API Gem — 路由与控制器 | `pallastrade_api/config/routes.rb` + `app/controllers/` | `payment_sessions` / `transactions` | `orders/:id/transactions`（create，TXN-P2-6 起为会话创建入口）、`orders/:id/payment_sessions`（create/show/update）、`carts/:id/payment_sessions`（**legacy**）、`payment_combinations`（仅 create/show） | 是（Order 域齐备；cart 域 legacy 待退役；组合缺 canonical 完成端点 → B5） |
| Admin Gem | `pallastrade_admin/app/` | `transactions` | `admin/transactions_controller.rb`（recovery/manual_review 运营视图） | 是（本批零改动） |
| Storefront | `storefront/src/` | `express` / `carts.paymentSessions` / `checkout/start` | `lib/data/express-checkout-flow.ts`（**文件头自述 LEGACY/COMPATIBILITY ONLY**；create→`carts.paymentSessions.create`、finalize→`carts.paymentSessions.complete`）、`components/checkout/ExpressCheckoutButton.tsx`（confirm 编排；跳 `/order-placed`；`return_url` → `/confirm-payment`）、`lib/data/payment.ts`（legacy 包装 + `confirmPaymentAndCompleteCart`）、`app/api/checkout/start/route.ts`（**canonical BFF**：carts.update → carts.submit → `orders.transactions.create` → PATCH `orders.paymentSessions.complete`） | **否 → 本批实现**（钱包改接 BFF） |
| Platform | `platform/packages/` | `transactions` / `paymentSessions` | `sdk/src/store-client.ts`：`orders.transactions.create` / `orders.paymentSessions.{create,complete}` / `carts.paymentSessions.*`（legacy 保留给 legacy consumer） | 是（无需 SDK 改动） |

### 搜索结论

- canonical 链（Order → Transaction → Reserve → PaymentSession）与 BFF `/api/checkout/start` **都已就绪**；钱包只是走错了入口（cart 域 legacy 会话），本批为**纯 storefront 重接线**，零后端/契约变更。
- 防重复：无既有 PRD 覆盖「钱包 → canonical」；B1/B2/B3 分别覆盖结账页投影、购物车抵扣、库存错误与结果页。
- 明确留到 B5（并记录理由）：`confirm-payment` 的 legacy 完成、组合支付 `completeCombinationSession`（后端缺 canonical 组合完成端点）、legacy 端点删除与 §46 退役阈值。

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 定制优先级：本批不新增定制模式（消费既有 canonical 端点 + 既有 BFF），属最稳层级 |
| `ai/skills/harness-prd/SKILL.md` | ✅ 已读 | 阶段 0-5：`prd new`（查重 >0.3 阻止 → 本批为系列新批次，`--force` 并在 PRD 记录理由）→ 模板扩充 → **用户确认** → gate → 实施 → AC↔测试 → 知识同步门 |

**按需 Skill（勾选本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-storefront` | ✅ | ✅ 已读 | ① 客户端组件不得直接 `getClient()`；canonical 下单必须走同源 BFF `POST /api/checkout/start`（避免 Server Action 的 RSC 刷新打断 Stripe 确认）；② 统一支付结果页是唯一落点（success/failure/cancel/pending 都去 `/payment-result`）；③ 改 storefront 必须 `pnpm test` + `check` + `typecheck` 三绿 |
| `pallastrade-payments` | ✅ | ✅ 已读 | 不变量：**Reserve 失败不得创建 PaymentSession**；PSP success + local incomplete = `recovery_required`（不是 payment failed）；重试必须落在同一订单/交易；会话创建唯一 canonical 入口是 `orders.transactions.create`（PaymentSessions::Start 绑定 transaction） |
| `pallastrade-api-v3` | ✅ | ✅ 已读 | 错误响应统一 `{ error: { code, message } }`；错误码语义（含库存四态）与「客户端永不自行判断库存/支付状态」；BFF 透传 code/message/order_id |
| `pallastrade-testing` | ✅ | ✅ 已读 | storefront 侧 vitest（组件/数据层/纯函数），断言环境无关；SDK 调用以 vi.mock 断言「调用/未调用」 |
| `pallastrade-events-webhooks` | ⛔ | ⛔ | 无事件/订阅者改动（`Transactions::OnPaymentSuccess` 已有，由后端驱动收尾） |
| `pallastrade-data-model` | ⛔ | ⛔ | 无模型/字段改动 |

---

## 需求标题

Checkout 收尾收敛 B4：Express 钱包 canonicalize（legacy `carts.payment_sessions` → `orders.transactions` 链）

## 任务类型

重构 / 一致性收敛（storefront 重接线；无后端变更）

## 需求描述

方案 §29/§45 要求「Express 不得成为第二条 Checkout Flow」且 `/carts/:id/payment_sessions` 不得被新流程使用；当前购物车抽屉的 Apple/Google Pay 入口恰恰走的是这条 legacy 链（`expressCheckoutCreateSession`/`expressCheckoutFinalize` → `carts.paymentSessions.*`），并落在旧完成页 `/order-placed`。本批把钱包确认路径接到 canonical BFF（`POST/PATCH /api/checkout/start`：cart update → idempotent submit → `orders.transactions.create` → `orders.paymentSessions.complete`），统一落到 `/payment-result`，并按 B3 语义做错误分流（recovery 禁止重付、库存/报价类抽屉内提示）。

## 影响范围（harness affected 输出）

受影响：storefront 钱包入口（`ExpressCheckoutButton`）、新增客户端编排模块与单测、`lib/data/express-checkout-flow.ts`（移除 legacy 会话包装）、`lib/data/payment-combination.ts`（组合完成改 Order 域）、`lib/data/payment.ts`（删 legacy 包装）、删除 `confirm-payment/**`、`expressCheckout` 文案（5 语言）、后端组合完成规格。
不涉及：DB、序列化器、路由、SDK。

## 技术方案（初步）

1. 新增 `lib/checkout/express-canonical.ts`（客户端安全）：`startExpressCheckout(body)` → `POST /api/checkout/start`；`completeExpressCheckout(orderId, sessionId)` → `PATCH`；`expressErrorRoute(code)` → `"recovery" | "inline"`（纯函数，便于单测）。
2. `ExpressCheckoutButton` 的 `handleConfirm`：地址/邮箱并入 start body（去掉 `expressCheckoutPreparePayment` 依赖）；不再调用 `expressCheckoutCreateSession/Finalize`；`return_url` → `/payment-result/{orderId}?session={sessionId}`；确认后 best-effort PATCH + `router.push('/payment-result/...')`。
3. 错误分流：`INVENTORY_RECOVERY_REQUIRED` → `payment-result?notice=recovery`；其余 canonical 错误 → 抽屉内提示（`event.paymentFailed` 当未扣款）+ 不导航。
4. **组合支付**：`completeCombinationSession` 改调 `orders.paymentSessions.complete(session.order_id, session.id)`（Order 域，已含组合分支）；后端补规格。
5. **legacy 删除**：`confirm-payment/[id]` 页 + 测试、`confirmPaymentAndCompleteCart`、`createCheckoutPaymentSession`、`completeCheckoutPaymentSession`（grep 零调用后删）及其单测。
6. 文案：`expressCheckout` 命名空间补键（recovery/库存/报价/不可支付），五语言一致。

## 风险点

- 最高风险：钱包是**真实扣款**路径 → 任何改动都可能造成「扣款但未收尾」。缓解：canonical 链本身幂等（`Carts::Submit` 幂等、`Transactions::Start` 幂等），best-effort PATCH 后以结果页服务端状态为准；测试断言「未扣款时不调用 Stripe confirm」。
- 兼容风险：`express_payment` 金额仍取服务端（P0-4），不改金额来源。
- 回归风险：`lib/data/payment.ts` 的 legacy 包装仍被 `confirmPaymentAndCompleteCart` 使用（B5）→ 本次**只删 Express 用的两个包装**，不动其余。

## 决策节点

> ⏸️ **等待用户确认**（R3/R7）：PRD 与 REQ 呈现后，用户明确「确认/实施」才清除 `user-confirmed` 并进入实施。
>
> 开放决策（AI 建议已在括号内）：
> 1. 钱包支付成功后的落地页：**`/payment-result/{orderId}?session=…`** vs 保留 `/order-placed` —— 建议统一结果页。
> 2. 钱包遇到库存/报价类错误：**抽屉内提示且不跳转** vs 跳回结账页 —— 建议抽屉内。
> 3. `confirm-payment` / 组合支付 legacy 收口：留 B5 vs 本批一并做 —— 建议留 B5（当时判断需后端新端点）。
>
> **用户已确认（2026-09-15）**：① 统一结果页；② 抽屉内提示不跳转；③ **本批一并做 legacy 收口（含后端切片）**。
> ③ 的核查结论（回写 PRD v0.2 FR-010）：后端 `Store::Orders::PaymentSessionsController#complete` **已内置组合分支**（TXN-P2：txn 组合 → `Transactions::OnPaymentSuccess`；legacy 组合 → `Complete` 适配器）→ **无需新端点**，仅补一条 Order 域组合完成规格；storefront 侧改调 Order 域完成并删除 `confirm-payment` 等遗留消费者。

---

## 阶段③：实施后验证（不可跳过）

> ⚠️ 每项改动都必须有对应的最低验证。

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| 前端（钱包编排） | `components/checkout/ExpressCheckoutButton.tsx`、`lib/checkout/express-canonical.ts` | `pnpm -C storefront test`（新单测断言 canonical 调用 + 零 legacy 调用） | 待执行 | ⬜ |
| 前端（legacy 包装收口） | `lib/data/express-checkout-flow.ts`、`lib/data/__tests__/payment.test.ts` | `pnpm -C storefront test` + `typecheck` | 待执行 | ⬜ |
| 文案 | `messages/{en,de,es,fr,pl}.json` | i18n 守护测试（五语言齐备） | 待执行 | ⬜ |
| 其它 | PRD/README 状态 | `node scripts/ci/prd-status-sync.mjs --check` | 待执行 | ⬜ |
| 声明无需验证 → 原因：_____ | — | — | — | — |

### 新增 admin 页面三要素检查（固定检查项，凡新增/改动 admin 页面必填）

**本批不涉及 admin 页面** —— 无 admin 视图/控制器改动，三项检查豁免（记录在案）。

### 验证结论

（实施后回填）
