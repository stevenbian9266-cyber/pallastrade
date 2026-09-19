# REQ-20260919-checkout-remove-items-block-mobile-summary-meta

> 任务：`TASK-20260919054611-630d8f1f` ｜ Gate：`GATE-2026-09-19T05-46-35`（feature）｜ 风险：quick（paths 因子被并行会话未提交后台文件抬为 critical → 已 `--override quick` 并建 recovery）

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

关键词：`items` / `order summary` / `showOrderSummary` / `setSummaryContent` / `item_count` / `item_total`（含同义词：Artikel、Bestellübersicht、商品清单、订单摘要）。

| 层 | 搜索路径 | 找到的文件 | 是否满足需求？ |
|---|---|---|---|
| App — models/controllers/views | `backend/app/` | 无（宿主应用不承载结账页渲染） | 否（也无需改） |
| Core Gem — models/services | `backend/pallastrade_gems/pallastrade_core/app/` | `models/pallastrade/order.rb`（`item_total`）、`models/pallastrade/cart.rb`（`money_methods :item_total`）、`services/pallastrade/order_checkout/view.rb`（`item_total display_item_total`） | 已有金额事实，**无 UI** |
| API Gem — serializers/controllers | `backend/pallastrade_gems/pallastrade_api/app/` | `serializers/.../shopping_cart_serializer.rb`（`item_count` / `item_total` / `display_item_total`；注释：运费税费在订单阶段计算）、`cart_serializer.rb`、`order_serializer.rb`、`store/checkout/checkout_serializer.rb` | ✅ **字段已齐**（`item_count` + `display_item_total`），无需后端改动 |
| Admin Gem — controllers/views | `backend/pallastrade_gems/pallastrade_admin/app/` | `presenters/pallastrade/admin/order_summary_presenter.rb`（后台自有摘要口径） | 无关（后台独立呈现） |
| Storefront | `storefront/src/` | `components/checkout/UnifiedCheckout.tsx`（左栏 Items 区块 `:1230-1256`；`UnifiedOrderSummary` `:129-260`；摘要发布 `:655-663`）、`app/[country]/[locale]/(checkout)/layout.tsx:83-139`（`MobileSummaryToggle`）、`contexts/CheckoutContext.tsx:15`（`setSummaryContent`）、`components/checkout/OrderPaymentContent.tsx:375`（另一处摘要发布方） | ✅ **本需求全部在前台**，左栏与右栏确实重复 |
| Platform | `platform/packages/` | `sdk/src/types/generated/ShoppingCart.ts`（`item_count` / `display_item_total` / `items`）、`zod/generated/ShoppingCart.ts` | 类型已有；platform 无结账 UI，**无需改动** |

### 搜索结论

- **无需任何后端/契约改动**：件数与金额字段在 `ShoppingCartSerializer` + SDK 生成类型中已存在。
- 重复确凿：左栏 `UnifiedCheckout` Items 区块与右栏 `UnifiedOrderSummary` 渲染同一批 `cart.items`。
- 移动端空窗确凿：右栏摘要在 `lg` 以下被 `MobileSummaryToggle` 折叠，其文案仅 `showOrderSummary` / `hideOrderSummary`（`checkoutLayout` 命名空间），无件数/金额。
- 变更面 = storefront 3 个源码文件 + 5 个文案文件 + 2 个测试 + 文档同步。

## Step 1：Skill 文件咨询（功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 优先级「**Settings → Configuration → Events → Dependencies → Admin / Ransack APIs → Generators → Decorators → Extensions**」；本次属**前台呈现层结构调整**，不涉及后端定制模式 → 不引入装饰器/订阅者/新资源 |
| `ai/skills/harness-prd/SKILL.md` | ✅ 已读 | 一句话需求 → `prd new`（自动分类+查重>0.3 阻止）→ 模板扩充 → 用户确认 → gate → 实施 → `prd verify` → 文档同步 → evidence/finish；REQ 判定「改动 ≤5 文件且无逻辑变更 → 简版」，本次跨源码+文案+测试 **>5 文件** → 用完整版 |
| `ai/skills/pallastrade-storefront/SKILL.md` | ✅ 已读 | Checkout 章节：Unified checkout 的 main column = 「email + `AddressFormFields` + **itemized lines** + delivery-method radio + payment-method radio」，order summary 通过 `CheckoutContext#setSummaryContent` 发布到 desktop sticky sidebar；**money 契约**：raw 判逻辑、`display_*` 仅渲染；**CI 红线**：改 storefront 必须同时跑 `pnpm check`(biome, lineWidth 80) + `pnpm typecheck` |

**按需 Skill（本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-checkout` | ✅ | ✅ 已读 | 两段语义（Prepare → Order 权威报价 → Pay）与 `quote_changed` 页内确认区（`checkout-quote-diff`）均在主列顶部：**删除 Items 区块不得影响这两处顺序**（TopExpressPay → quote diff → 各 section） |
| `pallastrade-testing` | ✅ | ✅ 已读 | storefront 用 vitest（jsdom）；组件测试通过 `vi.mock("next-intl")` + `vi.mock("next/navigation")` 隔离；动态导入片段需显式放宽等待预算（`{ timeout: 10000 }`），**断言不放宽** |
| `pallastrade-i18n` | ✅ | ✅ 已读 | 文案一致性：五语言键集必须齐备；新增键必须同步 `checkout-i18n-keys.test.ts` REQUIRED 表（缺键运行时渲染成 key 本身） |
| `pallastrade-api-v3` / `pallastrade-decorators` / `pallastrade-events-webhooks` / `pallastrade-dependencies` | ❌ | — | 本需求零后端、零事件、零依赖注入 |

---

## 需求标题

结账页左栏移除重复 Items 区块；移动端 order summary 折叠按钮显示件数与金额。

## 任务类型

功能优化（前台呈现层 + 文案）。

## 需求描述

统一下单页左栏的商品清单与右栏订单摘要内容重复，删除左栏那一份，只保留右栏订单摘要作为唯一商品明细。因为移动端右栏摘要默认收起、按钮上只有「Show order summary」，删掉左栏后首屏会看不到商品信息，所以折叠按钮需要显示「几件 + 多少钱」。

## 影响范围

- 前端：`UnifiedCheckout.tsx`、`(checkout)/layout.tsx`、`CheckoutContext.tsx`
- 文案：`messages/{en,de,es,fr,pl}.json`（`checkoutLayout.showOrderSummaryWithMeta`）
- 测试：`UnifiedCheckout.test.tsx`、新增 `mobile-summary-toggle.test.tsx`、`checkout-i18n-keys.test.ts`
- 文档：`docs/prd/**`（本 PRD）、`ai/skills/pallastrade-storefront/SKILL.md`、`harness/scenarios/scenarios.json`
- **零**后端 / 契约 / SDK / 数据库改动

## 技术方案（初步）

1. `CheckoutContext` 增加 `summaryMeta: { itemCount, displayTotal } | null` + `setSummaryMeta`（可选字段，默认 null）。
2. `UnifiedCheckout`：删除左栏 Items `<section>`；在既有的「发布摘要」effect 中一并发布 `{ itemCount: cart.item_count, displayTotal: cart.display_item_total }`，清理函数中同时置空。
3. `(checkout)/layout.tsx`：`MobileSummaryToggle` 读取元数据；收起态文案 = `showOrderSummaryWithMeta(count, amount)`（无金额时回退 `showOrderSummary`），展开态 = `hideOrderSummary`；组件导出以便单测。
4. 新增文案键（ICU 复数；pl 提供 one/few/many/other）。
5. 测试：更新 `UnifiedCheckout.test.tsx` 既有断言（左栏无 items 标题、商品名恰 1 次）；新增折叠按钮测试覆盖 4 个分支。

## 验证方案（AC 映射）

| AC | 命令/测试 |
|---|---|
| AC-001 / AC-002 | `npx harness verify storefront-test --task TASK-20260919054611-630d8f1f`（含 `UnifiedCheckout.test.tsx`） |
| AC-003 ~ AC-006 | 同上（含新增 `mobile-summary-toggle.test.tsx`） |
| AC-007 | 同上（含 `checkout-i18n-keys.test.ts`） |
| 格式化/类型 | `pnpm -C storefront check`、`pnpm -C storefront typecheck` |

## 用户确认

✅ 已确认（2026-09-19）——用户原话：「**先优化第一项，建议按钮文案改为 `Show order summary · 3 items · $129.99` 采纳建议**」（方案与文案均经用户明确采纳）。
