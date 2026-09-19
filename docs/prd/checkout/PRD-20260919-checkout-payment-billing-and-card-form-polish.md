# PRD-20260919-checkout-payment-billing-and-card-form-polish

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-19 |
| 来源 | 优化：① checkout 支付区 Name on card 应为选填（当前校验必填）；② Billing 文案感知差 + 作用域与闭环一期 |
| 分类 | checkout |
| 关联 Skill | `pallastrade-storefront` / `pallastrade-checkout` / `pallastrade-i18n` |
| 关联 REQ | REQ-20260919-checkout-payment-billing-and-card-form-polish.md |
| 关联 PRD | 五条清单第 3 项 + 第 4 项**一期**（二期 = Stripe `billing_details.address` + 钱包 `billingDetails` 采纳，**本 PRD 不做**） |
| 需求类型 | 优化迭代（纯前台 + 文案） |

> **用户决策（2026-09-19）**：原话「**实施：第3项 第4项的一期**」。

## 1. 背景与目标

- **第 3 项（Name on card）**：`CardPaymentForm#validate()` 强制要求持卡人姓名（`cardholderRequired`），但输入框占位文案已写 "Name on card (optional)" —— **校验与文案自相矛盾**；提交侧本就支持可选（仅非空时才传 `billing_details.name`），Stripe 该字段亦为可选。
- **第 4 项一期（Billing 语义与作用域）**：勾选框文案只有 "Same as shipping address"，**缺少「Billing address」语境**；控件只存在于**卡支付分支内**（钱包/其它方式看不到）；下单前的报价确认区**不回显账单地址**，用户无从确认自己的选择是否生效。
- **目标**：① 姓名真正选填；② 账单区块对**所有支付方式**可见（钱包给出来源说明），文案为「Billing address + Same as shipping address」结构；③ 确认区回显账单地址（同配送 / 自定义地址摘要）。

## 2. 用户故事 / 场景

1. 作为**买家（卡支付）**，我不想被告知"姓名必填"，因为表单自己写着可选。
2. 作为**买家**，我看到的是「Billing address」标题 + 「Same as shipping address」勾选项，而不是一句没有语境的话。
3. 作为**用钱包支付的买家**，我被告知账单地址由钱包提供（而不是面对一个不起作用的勾选框）。
4. 作为**买家**，在最终确认区我能看到账单地址是"与配送相同"还是我填的地址。
5. **边界**：未勾选「同配送」且地址不完整 → 保留既有拦截（`billingAddressIncomplete`），且提交不发请求。

## 3. 功能需求（FR）

| # | 需求 |
|---|---|
| FR-001 | **Name on card 选填**：`validate()` 不再要求持卡人姓名；姓名非空时才随 `billing_details.name` 提交（既有行为保留）；错误键 `cardholderRequired` 清理 |
| FR-002 | **Billing 区块结构**：加粗标题 `Billing Address` + 勾选项 `Same as shipping address`（不再是单句、不再只在卡分支） |
| FR-003 | **作用域**：账单区块渲染于支付方式表单之后、**对所有支付方式可见**；钱包入口改为展示说明「账单地址由钱包提供」（新增键 `billingFromWallet`），不显示无效勾选框 |
| FR-004 | **确认区回显**：`order-quote-confirm` 内新增账单行 —— 同配送 → `Same as shipping address`；自定义 → 地址摘要（address1 / city / postal_code / country），带 `data-testid="quote-billing"` |
| FR-005 | **文案五语言齐备** + i18n 守护登记（新增 `billingFromWallet`；`cardholderRequired` 删除） |

## 4. 验收标准（AC）

| # | 验收标准 | 覆盖 FR |
|---|---|---|
| AC-001 | 持卡人姓名为空时 `validate()` 返回 `true`；非空时仍随 `billing_details.name` 提交 | FR-001 |
| AC-002 | 支付区存在 `Billing Address` 标题与 `billing-use-shipping` 勾选项；未勾选时渲染账单地址字段 | FR-002 |
| AC-003 | 勾选项不再位于"仅卡支付"分支：选用非卡入口（如钱包）时，展示 `billingFromWallet` 说明且不渲染勾选框 | FR-003 |
| AC-004 | 报价确认区渲染账单行：默认（同配送）→ `Same as shipping address`；取消勾选并填写后 → 地址摘要 | FR-004 |
| AC-005 | 五语言新增 `billingFromWallet`；`cardholderRequired` 从五语言移除；i18n 守护通过 | FR-005 |

## 5. 技术影响

| 区域 | 变更 |
|---|---|
| `storefront/src/components/checkout/CardPaymentForm.tsx` | 删除姓名必填校验分支 |
| `storefront/src/components/checkout/UnifiedCheckout.tsx` | 账单区块重构（标题 + 勾选 + 钱包说明）并移出卡分支；确认区新增账单行 |
| `storefront/messages/{en,de,es,fr,pl}.json` | 新增 `billingFromWallet`；删除 `cardholderRequired` |
| `storefront/src/lib/__tests__/checkout-i18n-keys.test.ts` | REQUIRED 表登记新键 |
| 后端 / 契约 / SDK | **无变更**（`billing_mode` / `billing_address` 链路既有） |

## 6. 测试计划（AC ↔ 测试映射）

| AC | 测试 |
|---|---|
| AC-001 | `CardPaymentForm.test.tsx`（姓名可空 → 校验通过；非空 → 传给 `confirmCardPayment`） |
| AC-002 / AC-003 | `UnifiedCheckout.test.tsx`（标题 + 勾选 + 字段；钱包分支渲染说明） |
| AC-004 | `UnifiedCheckout.test.tsx`（确认区账单行两种取值） |
| AC-005 | `checkout-i18n-keys.test.ts` |

**验证命令**：`npx harness verify storefront-test --task <TASK-ID>` + `pnpm -C storefront check` + `typecheck` + `check:locales`。

## 7. 非目标（Non-goals）

- **第 4 项二期**：不把账单地址透传进 Stripe `billing_details.address`；不采纳钱包返回的 `billingDetails` 覆盖页面选择（需支付契约与风控评估）。
- 不改 `billing_mode` 服务端语义与校验（`same_as_shipping` / `custom` 保持不变）。
- 不改左栏/右栏结构与费用读模型（第 1、5 项已收口）。

## 8. 风险

| 风险 | 处置 |
|---|---|
| 移出卡分支后钱包用户误以为勾选生效 | FR-003 用说明行替代勾选框（不给无效控件） |
| 姓名可选后 Stripe 侧缺 name | Stripe `billing_details.name` 本为可选；风控所需地址信息属二期 |
| 回显地址格式随语言差异 | 摘要用「地址字段拼接」而非模板句子，避免复数/语序问题 |

## 9. 知识同步清单

| 资产 | 动作 | 结论（2026-09-19） |
|---|---|---|
| `pallastrade-storefront Skill` | **更新** | Checkout 章节记录：Name on card 选填、Billing 区块结构与作用域、确认区账单回显 |
| `组件测试` | **更新** | 新增/调整 CardPaymentForm 与 UnifiedCheckout 用例 |
| `场景库` / `scenarios.json` | **更新** | 新增 GS-192 |
| `pallastrade-prd Skill` / `AGENTS.md` / `copilot-instructions.md` | 已评估，无需更新 | 流程与规则未变 |

## 10. 变更日志

| 日期 | 变更 |
|---|---|
| 2026-09-19 | 初稿（approved）：用户指定实施第 3 项 + 第 4 项一期 |
| 2026-09-19 | 实施完成（verifying）：姓名校验放宽（空值省略 `billing_details`）；`cardholderRequired` 五语言键删除；账单区块`billing-block`（标题 + 同配送勾选）对全部支付方式可见，钱包改 `billing-wallet-hint` 说明；确认区 `quote-billing` 回显同配送/自定义摘要；测试：CardPaymentForm（姓名可空 + 非空传递）、UnifiedCheckout（标题/切换/钱包分支/两种回显）、i18n 键守护；`prd verify` 全 AC 覆盖，`storefront-test` 通过 |
| 2026-09-19 | **dev 验证通过（done）**：提交 `d889e960` → 镜像 `sha256:a2d5185a…` 已上线（`/opt/pallastrade/.pull-deploy-state-dev` 校验 `d889e960… / sha256:a2d5185a…`，健康检查 + nginx smoke 全绿）。浏览器验证（`/de/de/checkout/cart_ARKs1igzRC`）：① 账单区块可见且文案为「Rechnungsadresse｜Wie Lieferadresse」，默认 `aria-checked=true`；② 取消勾选 → `aria-checked=false` 且展开 `bill-first_name/address1/city/state` 表单（标题保留），重新勾选恢复 `true`；③ 卡表单姓名框 `required=false`、占位「Name auf der Karte (optional)」，旧必填文案页面中已不可见；④ 卡选中时无 `billing-wallet-hint`（分支正确）；旧键 `cardholderRequired` 在部署产物中零命中 |
