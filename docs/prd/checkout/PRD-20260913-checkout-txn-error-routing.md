# PRD-20260913-checkout-txn-error-routing

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-13 |
| 来源 | 修复：Checkout 交易错误落点分流（quote 变化 / 库存 / 已收款恢复）〔用户指令「根据 RESEARCH-20260913 开始实施，PRD 要更细」（2026-09-13）；来源规格 §9.1/§9.2 P0-c〕 |
| 分类 | checkout（自动判定） |
| 关联 Skill | pallastrade-storefront |
| 关联 REQ | REQ-20260913-checkout-error-routing-and-money-contract.md |
| 关联 PRD | N/A（全新） |
| 需求类型 | Bug 修复 |

## 1. 背景与目标

- **一句话需求原文**：修复：Checkout 交易错误落点分流（quote 变化 / 库存 / 已收款恢复）
- **背景**：现状 `UnifiedCheckout#handlePayNow` 对"提交后"**任何**带 `order_id` 的错误一律 `router.replace` 到 `/payment-result/{or_}`；该页在无支付会话时恒判定为 `pending`（"处理中"）。后果：
  1. `quote_changed` / `checkout_version_conflict`（报价已变，需用户重新确认）→ 用户看不到"金额已更新"，看到的是模糊的"处理中"；
  2. `INSUFFICIENT_STOCK` / `INVENTORY_CHANGED` / `RESERVATION_EXPIRED`（**未产生任何 PSP 扣款**）→ 同样显示"处理中"，与源规格 §26/§27 要求（"商品不可用 + 返回购物车"，**禁止**"支付失败"字样）不符；
  3. `INVENTORY_RECOVERY_REQUIRED`（已扣款、待恢复）→ 通用 pending 页无"无需重复支付"的警示，存在**重复支付诱导**（违反源规格 §33）。
- **目标**：不改后端与 BFF 契约，仅在前端按错误 `code` 分流到正确页面 / 页内提示，并给出正确 CTA。
- **成功指标**：5 类错误码 100% 有专属落点与文案；库存类错误页面不出现"支付失败/Payment failed"；恢复态页面无重试支付入口；分流分支 100% 单测覆盖。

## 2. 用户故事 / 场景

- 作为顾客，我希望支付失败时被告知**真实原因和下一步动作**，以便不重复付款、不迷失。
- 场景（正常）：Pay Now 成功 → Stripe 内联确认 → `/payment-result`（**不变**）。
- 场景（异常，本 PRD 范围）：
  1. 报价变化（409）→ 去 `or_` 页重新确认金额；
  2. 库存不足 / 库存变化 / 预保留过期 → 页内提示"商品不可用" + 返回购物车；
  3. 已收款待恢复 → 结果页"已收到付款，订单确认中；无需重复支付"；
  4. 交易不可支付态（processing）→ 结果页"订单处理中"；
  5. checkout 未就绪 → 页内提示（无跳转）。
- 场景（边界）：错误无 `order_id`（如 BFF 422 `payment_method_unavailable`）→ 页内 toast（现状保持）；未知 `code` 且有 `order_id` → 保留现状跳结果页（防回归）。

## 3. 功能需求（FR）

- **FR-001｜错误码提取**：新增 `lib/errors.ts#extractErrorCode(value)`，从 `{ error: { code } }` 与 `{ code }` 提取 `code`；展示文案仍一律经 `normalizeErrorMessage`（防 React #31）。
- **FR-002｜quote 变化**：`code ∈ {quote_changed, checkout_version_conflict}` 且存在 `order_id` → `router.replace(/{basePath}/checkout/{order_id}?notice=quote_changed)`；**不得自动支付**；`or_` 页读取 `notice` 渲染可关闭横幅（`checkout.quoteUpdatedBanner`），金额以服务端最新 `CheckoutView` 为准。
- **FR-003｜库存类**：`code ∈ {INSUFFICIENT_STOCK, INVENTORY_CHANGED, RESERVATION_EXPIRED}` → **停留当前页**渲染 `role="alert"` 错误面板：标题 `checkout.stockUnavailableTitle` + 服务端原始 message + CTA `checkout.returnToCart`（Link → `/{country}/{locale}/cart`）；**不得**跳 `payment-result`；不得出现"支付失败"表述。
- **FR-004｜已收款恢复**：`code === INVENTORY_RECOVERY_REQUIRED` → `router.replace(/{basePath}/payment-result/{order_id}?notice=recovery)`；结果页在 `notice=recovery` 时强制展示 `paymentResult.recoveryTitle / recoveryDescription`，**不渲染** `retryPayment` 与 `refreshStatus` 按钮。
- **FR-005｜不可支付态**：`code === transaction_not_payable` → `router.replace(/{basePath}/payment-result/{order_id}?notice=processing)`；结果页在 `notice=processing` 时强制展示 `paymentResult.processingNoticeTitle / processingNoticeDescription`，不渲染重试按钮。
- **FR-006｜未就绪**：`code === checkout_not_ready` → 页内错误面板（标题 `checkout.checkoutNotReady` + 服务端 message；无 CTA）。
- **FR-007｜默认回归**：其他 `code` 且有 `order_id` → 保持现状跳结果页；无 `order_id` → toast（现状）。HTTP 非 2xx 但响应无结构化 code（如 `checkout_failed`）同样走默认分支。
- **FR-008｜i18n（5 语言）**：`storefront/messages/{de,en,es,fr,pl}.json` 新增：`checkout.stockUnavailableTitle`、`checkout.returnToCart`、`checkout.quoteUpdatedBanner`、`paymentResult.recoveryTitle`、`paymentResult.recoveryDescription`、`paymentResult.processingNoticeTitle`、`paymentResult.processingNoticeDescription`。
- **FR-009｜可访问性**：错误面板 `role="alert"`；横幅关闭按钮有可访问名称；CTA 使用可真键盘访问的 `Link` + `Button`。
- **FR-010｜契约约束**：不改后端 / BFF / SDK；成功路径**不得**跳 `checkout/or_`（仅错误分流路径跳转）；不改支付幂等（`operation_key`）语义。

## 4. 非功能需求（NFR）

- 无新增运行时依赖；纯客户端改动（`use client` 组件 + RSC 页面读 `searchParams`）。
- 错误展示必须经 `normalizeErrorMessage`（历史 React #31 白屏事故防线）。
- 兼容既有测试（`chk-p1-4b-storefront` / `chk-p1-4c-storefront` 全绿）。

## 5. 验收标准（AC，与测试一一映射）

| AC | ← FR | 判定条件 | 测试 |
|---|---|---|---|
| AC-001 | FR-002 | mock 409 `{code:"quote_changed", order_id:"or_123"}` → `replace` 到 `/us/en/checkout/or_123?notice=quote_changed`；未调 `confirmPayment` | `UnifiedCheckout.test.tsx` |
| AC-002 | FR-003 | mock `INSUFFICIENT_STOCK` → 面板 `checkout-error-notice` 可见；未跳 `payment-result`；`Return to cart` 链接为 `/us/en/cart` | 同上 |
| AC-003 | FR-003 | `INVENTORY_CHANGED` / `RESERVATION_EXPIRED` 同 AC-002（参数化） | 同上 |
| AC-004 | FR-004 | mock `INVENTORY_RECOVERY_REQUIRED` → `replace` 到 `/us/en/payment-result/or_123?notice=recovery` | 同上 |
| AC-005 | FR-004 | 结果页 `?notice=recovery` → 渲染 recovery 文案；无 `Retry payment` / `Refresh status` | `payment-result/[id]/__tests__/page.test.tsx` |
| AC-006 | FR-005 | 结果页 `?notice=processing` → processing 文案；无重试按钮 | 同上 |
| AC-007 | FR-002 | `or_` 页带 `?notice=quote_changed` → 横幅可见；缺省不渲染 | `OrderPaymentContent.test.tsx` |
| AC-008 | FR-006 | mock `checkout_not_ready` → 面板可见、无 CTA、无跳转 | `UnifiedCheckout.test.tsx` |
| AC-009 | FR-007 | 未知 `code` + `order_id` → 仍跳 `/payment-result/or_123`（回归） | 同上 |
| AC-010 | FR-008 | 5 语言文件均含 7 个新键 | review 证据（grep） |

## 6. 跨层搜索记录（6 层）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | error/quote/INVENTORY/checkout | 无宿主层实现（本改动 storefront-only） | 否 |
| Core | `pallastrade_gems/pallastrade_core/app/` | 同上 | `transactions/start.rb`（quote_changed / INSUFFICIENT_STOCK / INVENTORY_CHANGED；INV-P3-2 Reserve-before-PaymentSession）、`payment_sessions/start.rb`（checkout_version_conflict / checkout_not_ready）、`terminal_transaction_for`（INVENTORY_RECOVERY_REQUIRED / transaction_not_payable） | 错误码权威来源（只读） |
| API | `pallastrade_gems/pallastrade_api/app/` | 同上 | `concerns/error_handler.rb`（ERROR_CODES、409 映射）、`orders/transactions_controller.rb`、`orders/payment_sessions_controller.rb` | BFF 契约已具备（只读） |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | checkout | 无相关面 | 否 |
| Storefront | `storefront/src/` | 同上 | `UnifiedCheckout.tsx`（handlePayNow 默认跳结果页）、`OrderPaymentContent.tsx`（409→toast+refreshView）、`payment-result/[id]/page.tsx`、`lib/errors.ts`、`messages/*.json` | **改动点** |
| Platform | `platform/packages/` | 同上 | SDK 类型（CheckoutView/Order 含 raw+display；错误类型不含枚举） | 否 |

**结论**：改动集中 storefront 前端（3 组件/页 + errors 工具 + i18n）；后端与 SDK 无需变更；与既有 PRD 无重复（`harness prd new` 查重通过）。

## 7. 技术影响

- **修改**：`storefront/src/lib/errors.ts`（+extractErrorCode）、`storefront/src/components/checkout/UnifiedCheckout.tsx`、`storefront/src/components/checkout/OrderPaymentContent.tsx`、`storefront/src/app/[country]/[locale]/(checkout)/payment-result/[id]/page.tsx`、`storefront/messages/*.json` ×5。
- 接口 / 数据库 / 迁移：无。

## 8. 测试计划

- 更新（新增用例）：`storefront/src/components/checkout/__tests__/UnifiedCheckout.test.tsx`（AC-001..004、008、009）；`storefront/src/components/checkout/__tests__/OrderPaymentContent.test.tsx`（AC-007）；`storefront/src/app/[country]/[locale]/(checkout)/payment-result/[id]/__tests__/page.test.tsx`（AC-005、006）。
- 用例内标注 `PRD-20260913-checkout-txn-error-routing AC-xxx`。
- 验证器：`npx harness verify chk-p1-4b-storefront --task <T>`、`npx harness verify chk-p1-4c-storefront --task <T>`。

## 9. 文档同步清单（知识同步门）

| 资产 | 结论 | 证据 |
|---|---|---|
| `ai/skills/pallastrade-storefront/SKILL.md` | ✅ 已更新（Checkout 章节新增“交易错误落点分流”规则 + Changelog 条目） | 本次实施变更 |
| 场景库 `harness/scenarios/scenarios.json` | ✅ 已新增 **GS-111**（提交后错误按 code 分流） | 同上 |
| `pallastrade-prd` Skill / `AGENTS.md` / `.github/copilot-instructions.md` | ✅ 已评估，无需更新（仅按既有约定新增 PRD/REQ，机制未变） | `sync-check` 评估结论 |
| 组件测试 | ✅ 已更新（`UnifiedCheckout.test.tsx` +7；`OrderPaymentContent.test.tsx` +2） | `chk-p1-4b-storefront`（41 用例绿） |
| API 文档 / SDK 类型 | ✅ 不涉及（无接口变更） | — |
| `docs/prd/README.md` 索引 | ✅ 已登记 | — |

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-13 | 0.1 | 初稿：按 RESEARCH-20260913 §9.2 细化到 code 级 FR/AC | AI |
| 2026-09-13 | 0.2 | 实施完成（错误分流 + i18n 5 语言 + 测试）；知识同步结论登记于 §9 | AI |
