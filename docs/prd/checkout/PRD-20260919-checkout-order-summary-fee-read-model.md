# PRD-20260919-checkout-order-summary-fee-read-model

| 元数据 | 值 |
|---|---|
| 状态 | approved |
| 创建日期 | 2026-09-19 |
| 来源 | 优化：checkout 页面右侧 order summary 的 Shipping 显示异常且缺少其它费用项，需结合当前交易架构给出升级方案 |
| 分类 | checkout |
| 关联 Skill | `pallastrade-storefront` / `pallastrade-checkout` |
| 关联 REQ | REQ-20260919-checkout-order-summary-fee-read-model.md |
| 关联 PRD | 五条结账优化清单第 5 项（用户选定方案 A；**A1 不可行性已复核**，本轮实施 A2，A1 设计要点见 `docs/research/RESEARCH-20260919-checkout-cart-level-quote-feasibility.md`） |
| 需求类型 | 优化迭代（右栏读模型 + 文案；零后端改动） |

> **用户决策（2026-09-19）**：第 5 项选**方案 A**（真实费用项）。用户随后授权「**自主决定**」→ 依可⾏性复核结果，本轮实施 **A2**（等价落地版），A1 出设计要点待立项。

## 1. 背景与目标

- **背景（四处取证）**：
  1. **运费行显示占位句**：`UnifiedOrderSummary` 把 `t("shippingCalculatedAtSubmit")`（"Shipping cost is calculated when you submit your order."）当**值**渲染 → 观感异常。
  2. **费用项缺失**：折扣/税/礼品卡行是**条件渲染**，依赖 legacy `Cart`（`discountCart`）——而它只在用户**本次**操作优惠码/礼品卡后才被赋值（`setDiscountCart` 仅出现在 3 个 handler），**页面加载不拉取** → 已应用折扣码/礼品卡的车刷新后，行全消失。
  3. **Total 误导**：`discountCart?.display_total ?? cart.display_item_total` —— 无折扣时用**小计冒充 Total**（未含运费/税）。
  4. **数据源割裂**：明细来自新 `cart_` 实体（`display_item_total`），折扣/税来自 legacy Cart，两套口径混排。
- **架构事实（A1 复核结论）**：新 Cart 实体仅 `item_total`，无任何定价能力；权威金额只在 Order 上产生（`Carts::Submit` → `OrderUpdater`），车阶段无报价端点（`shipping_methods_controller` 注释明写「权威运费在提交订单时计算」）→ **真·A1（车级权威报价）需要后端定价 dry-run 改造**，本轮不做（见设计要点文档）。
- **目标**：右栏摘要的费用口径**语义正确、来源单一、缺失可解释**；并在 `Prepare` 拿到 Order 权威报价后，把**真实运费/折扣/税费/应付**同步进用户最常看的右栏。
- **成功指标**：右栏不再出现"占位句当金额"；已应用抵扣的车刷新后费用行仍在；有权威报价时右栏显示权威金额且与主列确认区一致。

## 2. 用户故事 / 场景

1. 作为**买家**，我希望运费行不要显示一长句说明，而是明确「提交订单时计算」或真实金额。
2. 作为**已应用折扣码/礼品卡**的买家，刷新结账页后我仍能看到这些抵扣项（金额待提交时计算）。
3. 作为**买家**，点过一次 Pay（进入确认阶段）后，我希望右栏直接看到权威运费/折扣/应付，而不必去主列找。
4. **边界**：`display_item_total` 缺失 → 不显示金额、不崩；未发布权威报价 → 总额标注为"预估"。
5. **异常**：无任何抵扣 → 只显示小计/运费/税（含"待计算"语义），不虚构 0 元行。

## 3. 功能需求（FR）

| # | 需求 |
|---|---|
| FR-001 | **运费行**：值为权威 `display_delivery_total`（有报价时）；无报价时值为短标签「提交订单时计算」（新增 `checkout.calculatedAtSubmit`），不再把整句说明当值 |
| FR-002 | **费用行始终可见（有意图即渲染）**：`cart.discount_code` / `cart.gift_card` / `cart.store_credit` 存在时，折扣行/礼品卡行**必须渲染**（金额未知时显示待计算），修复"刷新后消失" |
| FR-003 | **税费行**：有权威报价 → `display_tax_total`；否则沿用可得的计算值；两者皆无 → 不渲染（不虚构 0） |
| FR-004 | **总额语义**：有权威报价 → 标签 `checkout.totalDue` + `display_amount_due`；无报价 → 标签 `checkout.estimatedTotal` + **预估计算值**（legacy 计算值优先，含已应用折扣；无则为小计），绝不用未折扣小计冒充含折扣总额 |
| FR-005 | **底部注记**（无报价时）：一句 `checkout.feesCalculatedAtSubmit`（运费与税费在提交订单时计算），取代原来的整句占位值 |
| FR-006 | **权威报价同步**：`Prepare` 成功后，把 Order 权威报价（运费/折扣/税费/应付）传入右栏摘要渲染（与主列确认区同源、同值） |
| FR-007 | **报价快照扩展**：BFF `readQuote` 增补 `tax_total` / `display_tax_total`（`CheckoutView` 已下发，属**消费既有字段**，无后端/契约改动） |

## 4. 验收标准（AC）

| # | 验收标准 | 覆盖 FR |
|---|---|---|
| AC-001 | 无权威报价时，运费行值为短标签（≠ 原整句）；底部出现"提交订单时计算"注记 | FR-001 / FR-005 |
| AC-002 | `cart.discount_code` 存在（无 legacy 计算值）时折扣行仍渲染，金额位为待计算标签 | FR-002 |
| AC-003 | `cart.gift_card` 存在时礼品卡行渲染（待计算或已计算值） | FR-002 |
| AC-004 | 无权威报价时总额标签为 `estimatedTotal`，值为 `display_item_total` | FR-004 |
| AC-005 | 有权威报价（Prepare 成功）时，右栏显示权威运费/折扣/税费/应付，且总额标签为 `totalDue` | FR-004 / FR-006 / FR-007 |
| AC-006 | 无任何抵扣与税费 → 不渲染折扣/礼品卡行（不虚构 0 元行） | FR-003 |
| AC-007 | 五语言新增键齐备：`calculatedAtSubmit` / `estimatedTotal` / `totalDue` / `feesCalculatedAtSubmit` | 全部 |

## 5. 技术影响

| 区域 | 变更 |
|---|---|
| `storefront/src/components/checkout/UnifiedCheckout.tsx` | `UnifiedOrderSummary` 增加 `quote` prop 与"意图行"渲染；摘要发布 effect 依赖加入 `preparedOrder` |
| `storefront/src/lib/checkout/server.ts` | `readQuote` 增补 `tax_total` / `display_tax_total` |
| `storefront/src/lib/checkout-quote.ts` | `CheckoutQuote` 类型/归一化补 tax 字段 |
| `storefront/messages/{en,de,es,fr,pl}.json` | 新增 4 键；`shippingCalculatedAtSubmit` 若不再使用则删除 |
| 后端 / 契约 / SDK | **无变更**（消费 `CheckoutView` 既有字段） |

## 6. 测试计划（AC ↔ 测试映射）

| AC | 测试 |
|---|---|
| AC-001 / AC-004 / AC-005 | `storefront/src/components/checkout/__tests__/UnifiedCheckout.test.tsx`（新增：无报价与有报价两组摘要断言） |
| AC-002 / AC-003 / AC-006 | 同上（意图行渲染条件） |
| AC-007 | `storefront/src/lib/__tests__/checkout-i18n-keys.test.ts`（REQUIRED 表新增 4 键） |

**验证命令**：`npx harness verify storefront-test --task <TASK-ID>` + `pnpm -C storefront check` + `typecheck` + `check:locales`。

## 7. 非目标（Non-goals）

- **不做 A1**（车级权威报价 / 定价 dry-run）：需后端改造，另有设计要点文档；本轮不加任何后端定价旁路。
- 不改物流方式区块（第 2 项已收口）、不改左栏结构（第 1 项已收口）。
- 不改 `Prepare` 触发时机（仍是点 Pay 时建单，不由浏览行为触发建单）。

## 8. 风险

| 风险 | 处置 |
|---|---|
| 误把"待计算"当 0 元 | 未知一律渲染标签而非 `0`/`—` 数字；AC-006 守护不虚构行 |
| 双数据源（cart 意图 vs legacy 计算值）口径混淆 | 权威报价 > legacy 计算值 > 待计算标签，三级优先，注释写明 |
| 摘要发布 effect 依赖遗漏导致不刷新 | 依赖显式加入 `preparedOrder`，并有 AC-005 测试守护 |

## 9. 知识同步清单

| 资产 | 动作 | 结论（2026-09-19） |
|---|---|---|
| `pallastrade-storefront Skill` | **更新** | Checkout 章节补「右栏费用读模型三级优先 + 权威报价同步」 |
| `组件测试` | **更新** | 新增无报价/有报价两组摘要用例 |
| `场景库` / `scenarios.json` | **更新** | 新增 GS-191 |
| `pallastrade-prd Skill` / `AGENTS.md` / `copilot-instructions.md` | 已评估，无需更新 | 流程与规则未变 |

## 10. 变更日志

| 日期 | 变更 |
|---|---|
| 2026-09-19 | 初稿（approved）：用户选方案 A → 复核后 A1 不可行，落实 A2；A1 设计要点另文 |
