# PRD-20260913-checkout-money-contract

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-13 |
| 来源 | 修复：Checkout Money 契约（raw 判逻辑 / display 仅渲染）与节省口径〔用户指令「根据 RESEARCH-20260913 开始实施，PRD 要更细」（2026-09-13）；来源规格 §9.1 P0-a〕 |
| 分类 | checkout（自动判定） |
| 关联 Skill | pallastrade-storefront |
| 关联 REQ | REQ-20260913-checkout-error-routing-and-money-contract.md |
| 关联 PRD | N/A（全新） |
| 需求类型 | Bug 修复 |

## 1. 背景与目标

- **一句话需求原文**：修复：Checkout Money 契约（raw 判逻辑 / display 仅渲染）与节省口径
- **背景**：
  1. `OrderPaymentContent`（`or_` 支付页）用 `parseFloat(read.display_delivery_total) > 0` 与 `parseFloat(read.display_tax_total) > 0` 判断运费/税行是否渲染；`display_*` 含货币符号（如 `$8.00`）→ `parseFloat` 得 `NaN` → **运费/税行永远不渲染**（金额展示缺行）。
  2. 邮件模板 `order-confirmation.tsx` 同样对 `displayDiscountTotal / displayTaxTotal` 做 `replace(/[^0-9.-]/g,"")` 后判数值——显示串参与逻辑判断。
  3. 购物车页 `UnifiedOrderSummary` 的 "TOTAL SAVINGS" 把 促销折扣 + 礼品卡 + 店铺余额**合并**为一个数字，与交易语义不符（源规格 §16：节省只统计促销节省）。
- **目标**：确立并执行 Money 契约 —— **raw 字段只用于比较/计算/条件；`display_*` 只用于渲染**；修正节省口径。
- **成功指标**：`or_` 页在 `delivery_total>0 / tax_total>0` 时正确渲染对应行；storefront 全仓不再有 `parseFloat/Number(...display_*)` 形态的逻辑判断；"TOTAL SAVINGS" 数值 == `|discount_total|`。

## 2. 用户故事 / 场景

- 作为顾客，我希望订单摘要**始终显示完整的金额构成**（小计 / 运费 / 税 / 总额），且"节省"只代表促销优惠，以便判断价格是否合理。
- 场景：`or_` 页金额行渲染（有运费/有税/二者皆有/皆无）；购物车页已应用促销码与礼品卡时节省徽标的数值；订单确认邮件中的折扣/税行渲染。

## 3. 功能需求（FR）

- **FR-001｜`or_` 页读模型扩展**：`OrderPaymentContent` 的 `CheckoutReadModel` 增加 raw 字段 `delivery_total` / `tax_total`（来自 `CheckoutView`，缺失时回退 Order 快照同名字段）。
- **FR-002｜`or_` 页行渲染条件改用 raw**：`parseFloat(read.display_*)` → `safeParseFloat(read.delivery_total) > 0`、`safeParseFloat(read.tax_total) > 0`；`display_*` 仅用于渲染字符串。
- **FR-003｜邮件模板**：`OrderConfirmationEmail` 新增可选 raw 入参（`taxTotal` / `discountTotal`），折扣/税行显示条件改为对 raw 判数值；调用方 `lib/webhooks/handlers.ts` 传入 `order.tax_total / order.discount_total`；`display_*` 仅渲染。
- **FR-004｜节省口径**：`UnifiedCheckout` 的 `savings` 只取 `|discount_total|`（移除 gift card / store credit 计入）；文案键 `checkout.totalSavings` 保持。
- **FR-005｜回归纪律**：`storefront/src/` 不得新增 `parseFloat(/Number(...display_*)` 形态逻辑；本次一并清除既有 2+1 处（`OrderPaymentContent` ×2、`order-confirmation.tsx` ×2 处判断）。

## 4. 非功能需求（NFR）

无新增依赖；不改 API/BFF/DB；显示格式完全由 `display_*` 决定（不引入前端货币格式化）；兼容既有 `chk-p1-4b-storefront` / `chk-p1-4c-storefront` 测试。

## 5. 验收标准（AC，与测试一一映射）

| AC | ← FR | 判定条件 | 测试 |
|---|---|---|---|
| AC-001 | FR-001/002 | `delivery_total="8.00"`（display 含符号）→ `Shipping` 行渲染 | `OrderPaymentContent.test.tsx` |
| AC-002 | FR-001/002 | `tax_total="5.00"` → `Tax` 行渲染；`delivery_total="0.00"` → 不渲染运费行（边界） | 同上 |
| AC-003 | FR-004 | 折扣 `-10` + 礼卡 `-5` → savings 徽标显示 `$10.00`（不含礼卡） | `UnifiedCheckout.test.tsx` |
| AC-004 | FR-004 | 仅有礼卡（无折扣）→ 不渲染 savings 徽标 | 同上 |
| AC-005 | FR-003 | 邮件模板：`taxTotal=0` → 不渲染 Tax 行；`taxTotal=5` → 渲染（raw 判定） | 邮件组件测试（新增或 review） |
| AC-006 | FR-005 | `grep -n "parseFloat(\|Number(" storefront/src --include=*.tsx` 无 `display_` 参与逻辑命中 | review 证据 |

## 6. 跨层搜索记录（6 层）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | display_/tax_total/delivery_total | 无宿主层实现 | 否 |
| Core | `pallastrade_gems/pallastrade_core/app/` | money_methods/DisplayMoney | `PallasTrade::DisplayMoney`（raw + display_* 双轨的权威定义；本次不改） | 权威只读 |
| API | `pallastrade_gems/pallastrade_api/app/` | money_attributes | `checkout_serializer.rb` / `order_serializer.rb`（raw `delivery_total/tax_total/discount_total` + `display_*` 均已在响应中） | 已有字段（只读） |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | 同上 | 无相关面 | 否 |
| Storefront | `storefront/src/` | `parseFloat(.*display_\|Number(.*display_` | `components/checkout/OrderPaymentContent.tsx` L112/L118、`lib/emails/order-confirmation.tsx` L157-165；`components/checkout/UnifiedCheckout.tsx` L111-115（savings 合并） | **改动点** |
| Platform | `platform/packages/` | display_ | SDK 类型含 raw+display | 否 |

**结论**：字段已全部由 API 提供（raw + display 双轨），无需后端/SDK 变更；改动集中 storefront 展示层 3 个文件。

## 7. 技术影响

- **修改**：`storefront/src/components/checkout/OrderPaymentContent.tsx`、`storefront/src/components/checkout/UnifiedCheckout.tsx`、`storefront/src/lib/emails/order-confirmation.tsx`、`storefront/src/lib/webhooks/handlers.ts`（传 raw 入参）。
- 接口 / 数据库 / 迁移：无。

## 8. 测试计划

- 更新：`storefront/src/components/checkout/__tests__/OrderPaymentContent.test.tsx`（AC-001/002）、`storefront/src/components/checkout/__tests__/UnifiedCheckout.test.tsx`（AC-003/004）。
- 新增（可选，若时间允许）：邮件组件单测（AC-005），否则以 review 证据（渲染逻辑改 raw + 调用方传 raw）。
- 验证器：`npx harness verify chk-p1-4b-storefront --task <T>`（组件）+ 全量 `storefront-test`（如可运行）。
- AC 标注：`PRD-20260913-checkout-money-contract AC-xxx`。

## 9. 文档同步清单（知识同步门）

| 资产 | 结论 | 证据 |
|---|---|---|
| `ai/skills/pallastrade-storefront/SKILL.md` | ✅ 已更新（Money 契约：raw 判逻辑 / display 仅渲染 + Changelog 条目） | 本次实施变更 |
| 场景库 `harness/scenarios/scenarios.json` | ✅ 已新增 **GS-112**（raw/display money contract） | 同上 |
| `pallastrade-prd` Skill / `AGENTS.md` / `.github/copilot-instructions.md` | ✅ 已评估，无需更新 | `sync-check` 评估结论 |
| 组件测试 | ✅ 已更新（`UnifiedCheckout.test.tsx` +2 savings 口径；`OrderPaymentContent.test.tsx` +2 raw 行渲染） | 验证器全绿 |
| API 文档 / SDK | ✅ 不涉及 | — |

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-13 | 0.1 | 初稿：按 RESEARCH-20260913 §9.1 P0-a 细化到渲染行级 FR/AC | AI |
| 2026-09-13 | 0.2 | 实施完成（raw 判逻辑 / savings 口径 / 邮件 raw 入参）；知识同步结论登记于 §9 | AI |
