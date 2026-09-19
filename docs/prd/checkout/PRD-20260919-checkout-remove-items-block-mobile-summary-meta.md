# PRD-20260919-checkout-remove-items-block-mobile-summary-meta

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-19 |
| 来源 | 优化：checkout 页面左侧主区去掉 items 区块（用户同时采纳建议：移动端折叠按钮文案 `Show order summary · 3 items · $129.99`） |
| 分类 | checkout |
| 关联 Skill | `pallastrade-storefront` / `pallastrade-checkout` / `pallastrade-customization` |
| 关联 REQ | REQ-20260919-checkout-remove-items-block-mobile-summary-meta.md |
| 关联 PRD | 五条结账优化清单第 1 项（其余 4 项各自独立 PRD） |
| 需求类型 | 优化迭代（纯前台结构 + 文案） |

> **用户决策（2026-09-19）**：① 去掉左栏 Items 区块；② **采纳**「移动端 order summary 折叠按钮显示件数与金额」建议，目标文案形如 `Show order summary · 3 items · $129.99`。用户原话：「先优化第一项，建议按钮文案改为 `Show order summary · 3 items · $129.99` 采纳建议」。

## 1. 背景与目标

- **背景**：
  1. 统一下单页（`UnifiedCheckout`）**左栏**渲染了商品清单（标题 `checkout.items` + 逐行缩略图/名称/数量/金额），而**右栏** sticky `UnifiedOrderSummary`（经 `CheckoutContext#setSummaryContent` 发布）已经渲染同一批商品行 + 小计/合计 —— 信息完全重复、页面冗长。
  2. 移动端（`lg` 以下）右栏摘要被收进 `MobileSummaryToggle`（`(checkout)/layout.tsx`），默认收起且**只有「Show order summary」文字**；一旦删掉左栏商品区块，移动端首屏将完全看不到商品件数与金额。
- **目标**：① 删除左栏重复 Items 区块，商品明细**只保留右栏一处**；② 移动端折叠按钮显示「件数 + 金额」，让折叠态即可获得关键信息（对齐 Shopify 同类交互）。
- **成功指标**：结账页商品明细在 DOM 中只出现 1 处；移动端首屏可见「N items · $X」；右栏摘要与支付链路零回归。

## 2. 用户故事 / 场景

1. 作为**买家（桌面）**，我希望右栏一处就能看到全部商品与金额，不必在左栏再读一遍同样的清单。
2. 作为**买家（移动端）**，我希望折叠的 order summary 按钮上直接看到「几件、多少钱」，以便不必展开就知道购物车概况。
3. **边界**：购物车有 1 件商品 → 文案为单数（`1 item`）；`display_item_total` 缺失（异常响应）→ 回退为纯「Show order summary」，不得出现空占位或 `undefined`。
4. **异常**：`or_` 订单支付页（`OrderPaymentContent`）发布自己的摘要但**不发布件数/金额元数据** → 折叠按钮回退为纯文案（不报错、不显示占位）；`order-placed` / `payment-result` 页清空摘要 → 折叠按钮整体不渲染（既有行为不变）。

## 3. 功能需求（FR）

| # | 需求 |
|---|---|
| FR-001 | **删除左栏 Items 区块**：`UnifiedCheckout` 主列不再渲染 `checkout.items` 标题与商品行；商品明细仅由右栏 `UnifiedOrderSummary` 呈现 |
| FR-002 | **移动端折叠按钮显示件数与金额**：摘要收起时文案 = 「展示摘要」+ 件数 + 金额（例：`Show order summary · 3 items · $129.99`）；展开时保持原「Hide order summary」文案 |
| FR-003 | **数据来源为服务端权威**：件数取 `ShoppingCart.item_count`，金额取 `ShoppingCart.display_item_total`（均为既有契约字段，**不新增**后端/契约）；发布通道 = `CheckoutContext` 新增的摘要元数据 |
| FR-004 | **优雅回退**：未发布元数据或无金额 → 折叠按钮回退为纯文案；摘要内容为空 → 折叠按钮不渲染 |
| FR-005 | **五语言文案齐备**：`checkoutLayout.showOrderSummaryWithMeta` 在 en/de/es/fr/pl 齐备（含 ICU 复数形态；pl 需 one/few/many/other） |

## 4. 验收标准（AC）

| # | 验收标准 | 覆盖 FR |
|---|---|---|
| AC-001 | 渲染结账页后，左栏**不再出现** `checkout.items` 标题；商品名在整页 DOM 中**恰出现 1 次**（右栏摘要） | FR-001 |
| AC-002 | 右栏 `unified-order-summary` 仍渲染商品行、小计与合计（回归） | FR-001 |
| AC-003 | 摘要收起 + 已发布元数据时，折叠按钮文案含件数与金额（`showOrderSummary` + `count` + `display_item_total`） | FR-002 / FR-003 |
| AC-004 | 摘要展开时按钮文案为 `hideOrderSummary` 且**不含**件数/金额 | FR-002 |
| AC-005 | 未发布元数据（或金额为空）时按钮回退为纯 `showOrderSummary`，DOM 中不出现 `undefined`/空占位 | FR-004 |
| AC-006 | 摘要内容为空（`setSummaryContent(null)` 场景）时折叠按钮不渲染 | FR-004 |
| AC-007 | 5 语言 `checkoutLayout.showOrderSummaryWithMeta` 齐备（`checkout-i18n-keys` 守护扩展） | FR-005 |

## 5. 技术影响

| 区域 | 变更 |
|---|---|
| `storefront/src/contexts/CheckoutContext.tsx` | 新增 `summaryMeta` / `setSummaryMeta`（`{ itemCount, displayTotal }`） |
| `storefront/src/components/checkout/UnifiedCheckout.tsx` | 删除左栏 Items `<section>`；摘要发布 effect 内同时发布元数据（清理时置空） |
| `storefront/src/app/[country]/[locale]/(checkout)/layout.tsx` | `MobileSummaryToggle` 读取元数据拼装收起文案；导出以便单测 |
| `storefront/messages/{en,de,es,fr,pl}.json` | 新增 `checkoutLayout.showOrderSummaryWithMeta` |
| `storefront/src/lib/__tests__/checkout-i18n-keys.test.ts` | REQUIRED 表新增 `checkoutLayout` 条目 |
| 后端 / 契约 / SDK | **无变更**（`item_count` / `display_item_total` 已在 `ShoppingCartSerializer` 与生成类型内） |

**Money 契约**：金额仅用于**渲染**，取自 `display_item_total`（既有 `display_*` 字段），不参与任何比较/计算。

## 6. 测试计划（AC ↔ 测试映射）

| AC | 测试 |
|---|---|
| AC-001 / AC-002 | `storefront/src/components/checkout/__tests__/UnifiedCheckout.test.tsx`（左栏无 items 标题；商品名恰 1 次；右栏摘要仍渲染） |
| AC-003 / AC-004 / AC-005 / AC-006 | 新增 `storefront/src/app/[country]/[locale]/(checkout)/__tests__/mobile-summary-toggle.test.tsx` |
| AC-007 | `storefront/src/lib/__tests__/checkout-i18n-keys.test.ts`（既有守护扩展） |

**验证命令**：`npx harness verify storefront-test --task <TASK-ID>`（含 vitest 全量）+ `pnpm -C storefront check`（biome，CI 红线）+ `pnpm -C storefront typecheck`。

## 7. 非目标（Non-goals）

- 不改右栏**费用口径**（运费占位 / 缺费用项 —— 属五条清单第 5 项，单独 PRD）。
- 不改 `or_` 订单支付页的摘要元数据发布（后续可扩展；本 PRD 只要求回退正确）。
- 不改任何后端接口、契约或数据库。

## 8. 风险

| 风险 | 处置 |
|---|---|
| 删除左栏商品后移动端信息缺失 | 本 PRD FR-002 已补齐（折叠按钮显示件数与金额） |
| `CheckoutContext` 扩展影响其他消费方 | 新增字段为可选（默认 `null`），消费方仅新增读取点；`OrderPaymentContent` / `order-placed` 未发布时回退纯文案 |
| 格式化/类型导致 CI 红 | 实施后跑 biome（`node node_modules/@biomejs/biome/bin/biome check --write <本批文件>`）+ `pnpm typecheck` |

## 9. 知识同步清单

| 资产 | 动作 | 评估结论（2026-09-19） |
|---|---|---|
| `pallastrade-storefront Skill` | **更新** | ✅ 已更新：Checkout 章节改写「main column」组成（删除 itemized lines）+ 新增「移动端摘要折叠按钮」段落（`CheckoutSummaryMeta` / 回退规则 / `or_` 页无需改动） |
| `组件测试` | **更新** | ✅ 已更新：`UnifiedCheckout.test.tsx`（商品名恰 1 次 + 元数据探针）+ 新增 `mobile-summary-toggle.test.tsx`（收起/展开/回退/清空四分支） |
| `场景库` | **更新** | ✅ 已更新：新增 **GS-189**（`eval-ai --scenarios` → 190/190 valid） |
| `scenarios.json` | **更新** | ✅ 已更新：同上（文件本体） |
| `pallastrade-prd Skill` | 已评估，无需更新 | 本次严格按既有 PRD 工作流执行，流程与规则未变 |
| `AGENTS.md` | 已评估，无需更新 | 未引入新验证器/新规范/新反模式；§6 中「UI component / style」行已覆盖 storefront 变更 |
| `copilot-instructions.md` | 已评估，无需更新 | R0–R9 规则不受前台布局/文案调整影响 |

## 10. 变更日志

| 日期 | 变更 |
|---|---|
| 2026-09-19 | 初稿（draft）：用户已确认方案与文案（`Show order summary · 3 items · $129.99`） |
| 2026-09-19 | 状态 → `approved`（用户采纳）；实现完成：`CheckoutSummaryMeta` 发布通道 + 左栏 Items 删除 + 折叠按钮文案；验证：`storefront-test` 全绿、`pnpm check`(biome) exit 0、`pnpm typecheck` exit 0、`check:locales` 同步；知识同步门 7/7 已评估（4 更新 / 3 无需变更） |
| 2026-09-19 | 状态 → `done`：提交 `d0595674` 部署至 dev（镜像 `412f0682`），实测 ① 桌面：H1 → Express checkout → 1 Contact → 2 Shipping Address → 3 Shipping Method（Items 区块已消失）、右栏摘要商品行完好；② 移动端 EN：`Show order summary · 1 item · $129.99`；③ 移动端 DE：`Bestellübersicht anzeigen · 1 Artikel · $129.99`；④ 未 hydration 前回退纯文案（无占位/undefined） |
