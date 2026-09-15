# PRD-20260915-checkout-checkout-收尾收敛-b4-express-钱包-canonicalize-legacy-会话-transacti

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-15 |
| 来源 | 需求：Checkout 收尾收敛 B4 —— Express 钱包 canonicalize（legacy 会话 → Transaction 链） |
| 分类 | checkout（自动判定，见 `harness/policies/prd-categories.json`） |
| 关联 Skill | `pallastrade-storefront`（主）、`pallastrade-payments`（Transaction→Reserve→Payment 不变量）、`pallastrade-api-v3`（Store API 错误码） |
| 关联 REQ | REQ-20260915-checkout-b4-express-canonicalize.md（实施时回填） |
| 关联 PRD | 同系列 B1/B2/B3 的后续批次（`prd new` 查重命中系列相似度 → `--force` 新建，节奏表见 B1 PRD §1.1） |
| 需求类型 | 重构 / 一致性收敛（storefront 消费既有 canonical 契约；无后端变更） |

> 📌 本 PRD 为「Checkout 收尾收敛」系列第 **B4** 批，依据《商城前台 Checkout + Transaction + Promotion + 履约完整方案》§29（Express / Apple Pay / Google Pay）、§45（P0-7 Legacy Migration Matrix 的 `/carts/:id/payment_sessions` 行）与 §46（usage metric）；总体节奏表见 B1 PRD §1.1。

---

## 1. 背景与目标

- **一句话需求原文**：需求：Checkout 收尾收敛 B4 —— Express 钱包 canonicalize（legacy 会话 → Transaction 链）
- **背景**：方案 §29 明确「Express 不能再次成为第二条 Checkout Flow」，钱包必须走 `Order Checkout → Transaction → Reserve → Payment`，**不允许** `new Cart → legacy carts/payment_sessions`。当前实现正好违反这一条：
  - `storefront/src/lib/data/express-checkout-flow.ts` 文件头自述 **“P0-7 (FR-070/FR-071): LEGACY / COMPATIBILITY ONLY”**，其 `expressCheckoutCreateSession` → `carts.paymentSessions.create`、`expressCheckoutFinalize` → `carts.paymentSessions.complete`（经 `lib/data/payment.ts`）——**购物车抽屉的 Apple/Google Pay 入口正在 legacy 会话链上创建支付会话**（后端会记 `payment.legacy_flow.used` 指标）。
  - 而统一结账页（`UnifiedCheckout` → BFF `/api/checkout/start`）已经是 canonical：`carts.update` → `carts.submit` → **`orders.transactions.create`（Transactions::Start → Reserve → PaymentSessions::Start）** → `orders.paymentSessions.complete` → `/payment-result`。
  - 另一处 canonical 缺口：钱包确认后的落地页仍是 `/order-placed/{id}`（旧完成页），而 canonical 结果是 `/payment-result/{id}`（含 B3 的履约摘要与 recovery 语义）；redirect-required（3DS/钱包挑战）时 `return_url` 指向 legacy 的 `/confirm-payment/{id}`。
- **目标**：
  1. 钱包（Express）确认路径改走 canonical 链：`POST /api/checkout/start`（cart update → idempotent submit → `orders.transactions.create`）→ Stripe confirm → `PATCH /api/checkout/start`（`orders.paymentSessions.complete`）→ `/payment-result/{orderId}`。
  2. Express 路径**零** `carts.paymentSessions.*` 调用（legacy 会话不再由钱包产生）。
  3. redirect-required 的 `return_url` 指向 canonical 结果页（不再进 `confirm-payment`）。
  4. 钱包错误分流与 B3 语义一致：`INVENTORY_RECOVERY_REQUIRED` → 结果页 recovery（禁止重付）；库存/报价/不可支付 → 抽屉内提示且不扣款、不跳转。
  5. 金额/行项目继续取服务端 `express_payment`（P0-4 不变量不动）。
- **成功指标**：
  - Express 流程测试断言：成功路径只发生 `POST /api/checkout/start` + `PATCH /api/checkout/start`，且 **`carts.paymentSessions.create/complete` 调用次数为 0**；
  - 钱包落地页为 `/payment-result/{orderId}?session=…`（非 `/order-placed`、非 `/confirm-payment`）；
  - dev 日志观察窗口内不新增 `payment.legacy_flow.used`（钱包入口）。

## 2. 用户故事 / 场景

- 作为**用 Apple Pay 一键付款**的顾客，我希望这次下单和普通结账一样经过同一套库存预留与交易链路，以便不会出现「扣款了但库存/订单没走同一路径」的隐患。
- 作为**钱包支付遇到库存不足**的顾客，我希望看到与结账页一致的原因与下一步，而不是一个泛化的失败提示。
- 作为**钱包支付后需要 3DS/挑战**的顾客，我希望回到统一结果页看到「订单确认中/支付处理中」，而不是落到另一套旧页面。
- 场景列表：
  1. 正常：钱包确认 → canonical 会话 → 支付成功 → `/payment-result?session=…`（结果页成功 + 履约摘要）。
  2. 正常：redirect-required（钱包挑战/3DS）→ `return_url` = 结果页 → 结果页轮询服务端状态。
  3. 异常：库存不足 / 库存变化 / 预留过期 → 抽屉内错误提示（钱包可不关闭），**不产生 PSP 扣款**、不跳转。
  4. 异常：已收款待恢复（`INVENTORY_RECOVERY_REQUIRED`）→ 结果页 recovery，**无重试入口**（防二次扣款）。
  5. 异常：报价漂移（`quote_changed` / `checkout_version_conflict`）→ 抽屉内提示重新确认（不自动再次扣款）。
  6. 边界：无 `client_secret`（网关未返回）→ 不调用 Stripe confirm，提示 + 释放确认锁。
  7. 边界：best-effort `PATCH` 失败 → 不阻塞导航（结果页以服务端状态为准）。

## 3. 功能需求（FR）

- **FR-001 canonical 开启**：钱包 confirm 改为调用 BFF `POST /api/checkout/start`，body 携带 `cart_id` / `payment_method_id` / `payment_mode: "payment_intent"` / `checkout`（email、shipping_address、billing_address、billing_mode、shipping_method_id）——即把「地址准备 + 会话创建」合并为一次 canonical 调用；响应中的 `order` / `transaction` / `session`（`payment_execution`）为唯一权威。
- **FR-002 legacy 收口**：删除 Express 路径对 `carts.paymentSessions.create/complete` 的使用（`expressCheckoutCreateSession` / `expressCheckoutFinalize` 两个包装不再存在或以 canonical 实现替代）；Express 流程不得再出现 `payment.legacy_flow.used` 来源。
- **FR-003 完成链路**：支付确认后 best-effort 调用 BFF `PATCH /api/checkout/start`（`{ order_id, session_id }` → `orders.paymentSessions.complete`），随后**统一** `router.push('/{country}/{locale}/payment-result/{orderId}?session={sessionId}')`；不再跳 `/order-placed`。
- **FR-004 redirect 语义**：`stripe.confirmPayment` 的 `return_url` 改为 canonical 结果页（`/payment-result/{orderId}?session={sessionId}`），不再使用 `/confirm-payment/{orderId}`。
- **FR-005 错误分流**（复用 B3 语义）：`INVENTORY_RECOVERY_REQUIRED` → 结果页 `?notice=recovery`；`INSUFFICIENT_STOCK` / `INVENTORY_CHANGED` / `RESERVATION_EXPIRED` / `quote_changed` / `checkout_version_conflict` / `transaction_not_payable` / `payment_method_unavailable` → 抽屉内错误提示（不导航、不扣款），文案经 `normalizeErrorMessage` 归一。
- **FR-006 金额不变量**：钱包展示金额/行项目继续取服务端 `express_payment`（`expressAmount` / `expressLineItems`），前端不重算（P0-4）。
- **FR-007 失败安全**：`PATCH` 失败仅 `console.warn` 不阻塞导航（后端 webhook / `Transactions::OnPaymentSuccess` 会收尾）；无 `client_secret` 时不得调用 confirm。
- **FR-008 i18n（评估：无新增键）**：钱包失败提示**复用服务端 `message`**（由 `normalizeErrorMessage` 归一，与 B3 结果页/结账页同口径），文案无需前端新增；既有 `expressCheckout.*` 键（`finalizingPayment` / `or` / `shipping`）保持不动 → 五语言文件零改动。
- **FR-009 可测性**：canonical 编排抽到客户端安全模块（`lib/checkout/express-canonical.ts`：`startExpressCheckout` / `completeExpressCheckout` / `expressErrorRoute`），便于单测断言「无 legacy 调用 + 错误分流」。
- **FR-010 组合支付 canonical（§45 同行）**：多订单收银台不再用 `carts.paymentSessions.complete`——`completeCombinationSession` 改调 **Order 域** `orders.paymentSessions.complete(session.order_id, session.id)`；后端 `Store::Orders::PaymentSessionsController#complete` **已内置组合分支**（TXN-P2：txn 化组合 → `Transactions::OnPaymentSuccess`，legacy 组合 → `Complete` 适配器），故**无需新端点**；未覆盖的 Order 域组合完成补一条请求规格。
- **FR-011 legacy 消费者删除**：钱包与组合改道后，删除仅剩的 cart 域 legacy 消费者：`confirm-payment/[id]` 页面（及其旧重定向入口）、`lib/data/payment.ts` 的 `confirmPaymentAndCompleteCart` / `createCheckoutPaymentSession` / `completeCheckoutPaymentSession`（先全仓 grep 确认零调用），同步删除/调整相关单测。
- **FR-012 非目标**：后端 legacy 端点删除与 §46 usage metric 退役阈值（属 P2 legacy convergence 的后续切片）；`carts/payment_sessions` 控制器本身保留（存量兼容 + 观测）。

## 4. 非功能需求（NFR）

- **一致性 / 不变量**：钱包与结账页走**同一条**链（同一 BFF、同一 `Transactions::Start`、同一 Reserve 门），杜绝第二条 Checkout Flow（§29）。
- **安全**：客户端不接触 SDK 凭据（BFF 持有 publishable key + guest/customer token）；错误信封经 `normalizeErrorMessage`（React #31 防线）。
- **可回滚性**：改动集中在 storefront 钱包入口 + 一个新的客户端编排模块；回滚 = 还原 ExpressCheckoutButton 的调用序列（无数据迁移）。
- **可观测性**：不再产生 legacy 会话流量（可通过后端 `payment.legacy_flow.used` 指标验证）。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001 ← FR-001**：成功路径调用顺序为 `POST /api/checkout/start` → Stripe confirm → `PATCH /api/checkout/start`（断言两次 fetch 的 URL/方法/关键 body 字段）。
- **AC-002 ← FR-002**：Express 流程中 `carts.paymentSessions.create` / `.complete` **调用次数为 0**（SDK mock 断言）。
- **AC-003 ← FR-003**：支付确认后导航目标为 `/{country}/{locale}/payment-result/{orderId}?session={sessionId}`。
- **AC-004 ← FR-004**：`confirmPayment` 收到 `return_url` = canonical 结果页 URL。
- **AC-005 ← FR-005**：`INVENTORY_RECOVERY_REQUIRED` → 导航到 `?notice=recovery`（且不显示「支付失败」）。
- **AC-006 ← FR-005**：库存/报价/不可支付类错误 → 不导航、调用 `event.paymentFailed`（当未扣款时）、展示归一化后的错误文案。
- **AC-007 ← FR-007**：无 `client_secret` → 不调用 `stripe.confirmPayment`，提示错误并释放确认锁。
- **AC-008 ← FR-007**：`PATCH` 失败（500）→ 仍导航结果页（不抛错、不阻塞）。
- **AC-009 ← FR-006**：钱包金额/行项目仍取 `express_payment`（既有单测保持绿）。
- **AC-010 ← FR-008**：i18n **无新增键**（评估结论）——失败文案取服务端 `message`；五语言既有键守护测试 `checkout-i18n-keys.test.ts` 保持绿（缺键回归防线不退化）。
- **AC-011 ← FR-010**：`completeCombinationSession` 调用 **Order 域** 完成端点（断言 SDK 调用为 `orders.paymentSessions.complete`，且 `carts.paymentSessions.complete` 为 0 次）。
- **AC-012 ← FR-010**：后端规格：`PATCH /api/v3/store/orders/:order_id/payment_sessions/:id/complete` 能完成组合支付（成员订单全部 completed、组合 succeeded）。
- **AC-013 ← FR-011**：storefront 全仓不再存在 `carts.paymentSessions.` 调用（grep + 测试双重守护）。
- **AC-014 ← FR-011**：`confirm-payment` 页面与其数据层旧函数删除后，`pnpm typecheck` / `biome` / 全量测试保持绿。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | `express` / `payment_session` | 仅生成类型产物 | ⚠️ 无业务代码（本批不涉） |
| Core | `pallastrade_gems/pallastrade_core/app/` | `payment_sessions` / `transactions` | `services/pallastrade/transactions/{start,reserve_inventory}.rb`（canonical 链：Start → Reserve → PaymentSessions::Start）、`checkout/add_store_credit.rb` 等 | ✅ canonical 链已存在（钱包直接复用） |
| API | `pallastrade_gems/pallastrade_api/app/` + `config/routes.rb` | `payment_sessions` / `transactions` | 路由：`orders/:id/transactions`（create）、`orders/:id/payment_sessions`（create/show/update）、`carts/:id/payment_sessions`（**legacy** create/show/update）；`error_handler` 错误码表 | ✅ Order 域端点齐备；cart 域为待退役 legacy |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | `transactions` | `admin/transactions_controller.rb`（recovery/manual_review 运营视图） | ✅ 本批零改动 |
| Storefront | `storefront/src/` | `express` / `carts.paymentSessions` | `lib/data/express-checkout-flow.ts`（**显式 LEGACY**：create/finalize 走 cart 域）、`components/checkout/ExpressCheckoutButton.tsx`（confirm 编排 + 跳 `/order-placed`、`return_url` → `/confirm-payment`）、`lib/data/payment.ts`（legacy 包装）、`app/api/checkout/start/route.ts`（canonical BFF：update→submit→**transactions.create**→PATCH complete） | **否 → 本批实现**（钱包改走 BFF） |
| Platform | `platform/packages/` | `transactions` / `paymentSessions` | `sdk/src/store-client.ts`：`orders.transactions.create`、`orders.paymentSessions.{create,complete}`、`carts.paymentSessions.*`（legacy 仍在，供 legacy consumer 使用） | ✅ 无需 SDK 改动 |

**结论**：本批为 **storefront 重接线 + 1 条后端补齐规格**：canonical 链与 BFF 都已就绪，钱包只是接错了入口；组合支付的 canonical 完成分支**后端已存在**（Order 域 complete 内置组合分支），仅缺测试。防重复判定：无既有 PRD 覆盖「钱包 → canonical」；`PRD-20260914-checkout-…-b1/b2/b3` 分别覆盖结账页投影、购物车抵扣、库存错误与结果页，本批是 §45 矩阵中 `/carts/:id/payment_sessions` 行的**全部 storefront consumer 收敛**。

## 7. 技术影响

- **storefront**：`components/checkout/ExpressCheckoutButton.tsx`（confirm 编排改 canonical；**移除 `stripe.createPaymentMethod`**——canonical 会话创建不接受网关侧 PM id，`payment_mode: payment_intent` 由后端建会话）、新增 `lib/checkout/express-canonical.ts`（客户端安全编排 + 错误路由）与其单测、`lib/data/express-checkout-flow.ts`（移除 legacy 会话包装；保留地址/费率准备）、`lib/data/payment-combination.ts`（组合完成改 Order 域）、`lib/data/payment.ts`（删 legacy 包装）、删除 `app/[country]/[locale]/(checkout)/confirm-payment/**`、相关单测调整；`messages/*.json` **零改动**（见 FR-008 评估）。
- **backend**：`spec/requests/api/v3/store/payment_combinations_controller_spec.rb` 追加「Order 域 complete 完成组合」规格（控制器无新端点）；**不涉及** DB、序列化器、路由。

## 8. 测试计划

- **新增**：`storefront/src/lib/checkout/__tests__/express-canonical.test.ts` → AC-001/002/003/004/005/006/007/008（mock `fetch` 与 SDK 客户端；断言 URL/方法/body 与「零 legacy 会话调用」）
- **新增/扩展**：`storefront/src/components/checkout/__tests__/ExpressCheckoutButton.test.tsx`（Stripe Elements 以 mock 注入；断言导航目标与 `return_url`）→ AC-003/004/006
- **保持**：`storefront/src/lib/utils/__tests__/express-checkout.test.ts`（金额不变量）→ AC-009
- **保持（无新增）**：`storefront/src/lib/__tests__/checkout-i18n-keys.test.ts` → AC-010（i18n 评估为无变更）
- **扩展（后端）**：`backend/spec/requests/api/v3/store/payment_combinations_controller_spec.rb` → AC-012（该文件已在注册 verifier `p1-order-flow-rspec` 命令内，无需改 harness 配置）
- **新增（守护）**：`storefront/src/lib/data/__tests__/legacy-payment-sessions-guard.test.ts`（① 全仓源码零 `carts.paymentSessions` 调用（注释行豁免）；② 已删除面保持删除）→ AC-012/AC-013
- **调整**：`storefront/src/lib/data/__tests__/payment.test.ts` 随 legacy 包装一并删除 → AC-011/014
- **回归**：`pnpm -C storefront test` / `check` / `typecheck` 三绿
- **AC ↔ 测试映射**：见上逐条标注；测试文件内同行写 `# PRD-<本PRD-ID> AC-xxx` 供 `prd verify` 校验

## 9. 文档同步清单（知识同步门）

- [x] Skill：`ai/skills/pallastrade-storefront/SKILL.md` —— 新增「Express 钱包 canonicalize（B4）」小节（固定 onConfirm 五步 + 禁止清单）与 Changelog B4 条目 + 通配符路径踩坑记录
- [x] 场景库：`harness/scenarios/scenarios.json` 新增 **GS-123**（钱包同链 + 零 legacy 会话 + 结果页落地 + best-effort 完成），`harness eval-ai --scenarios` → **124/124 valid**
- [x] 本 PRD 状态（`done`）+ `docs/prd/README.md` 索引（`prd-status-sync --fix/--check` → 135 份 / 135 行一致）
- [x] REQ：`harness/requirements/REQ-20260915-checkout-b4-express-canonicalize.md`
- [x] **已评估，无需更新**（sync-check 逐条结论）：
  - **包 / SDK 能力**（`platform/packages/sdk/dist/**`）：本批**零 SDK 源码改动**，仅消费既有 `orders.paymentSessions.complete`；dist 变化来自 B1–B3 的手写类型扩展（其批次已同步 `pallastrade-typescript-sdk` Skill）→ 无需再改
  - **UI 组件 / 页面**：`pallastrade-storefront` Skill 已更新（见上）；组件测试已补；场景库已补 → 无遗漏
  - **Skill / PRD 机制**（`pallastrade-prd` / `AGENTS.md` / `copilot-instructions.md`）：本批照 R8 流程执行，无机制变更 → 无需更新
  - API 文档 / `pallastrade-payments` Skill（服务端链未变）、`.env.example`（无新配置）→ 无需更新

## 9.1 风险与已知取舍

- **外部深链**：删除 `/confirm-payment/[id]` 后，历史 3DS `return_url`（旧会话已签发的 URL）会 404；现行钱包与结账页的 `return_url` 均已指向 `/payment-result`。存量影响仅限「已打开旧页面/旧邮件链接」的极少数会话，且真实资金状态以 webhook / 结果页轮询为准（后端不存在依赖该页的完成链路）。
- **`Cart` 无 `shipping_method_id`**：canonical start 不传该字段；若未来后端要求显式传参，需先在 SDK 手写类型补字段（当前 BFF 从车阶段选定费率推导）。

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-15 | 0.1 | 初稿：B4 范围（钱包 canonicalize）+ FR-001..010 / AC-001..010 / 跨层搜索 / 测试与同步计划；`prd new` 查重命中系列相似度 → `--force` 新建并记录理由 | AI |
| 2026-09-15 | 0.2 | 用户决策：① 钱包落地页统一 `/payment-result`；② 钱包错误抽屉内提示不跳转；③ **把 B5 边界（组合支付与 `confirm-payment` 的 legacy 会话）并入本批**。核查后：Order 域 complete **已内置组合分支** → 无需新端点，仅补规格；FR-010/011/012 与 AC-011..014 随之新增 | AI |
| 2026-09-15 | 0.3 | 实施期修正（均已在 AC/§7/§8 同步）：① FR-008 评估为 **i18n 无新增键**（失败文案用服务端 `message`）；② 移除 `stripe.createPaymentMethod`（canonical 会话创建不收网关 PM id）；③ start body **不传 `shipping_method_id`**（`Cart` 类型无该字段；配送费率已在车阶段经 `expressCheckoutSelectRates` 服务端入账）；④ 补容器组件测试 `ExpressCheckoutButton.test.tsx` 与守护测试 `legacy-payment-sessions-guard.test.ts`；⑤ 删除 `confirm-payment` 页后，**外部深链**（历史 3DS return_url）由 `/payment-result` 承接，旧链接对应 404 属预期（§10 风险已记） | AI |
