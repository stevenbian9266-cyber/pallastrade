# REQ-20260919-checkout-payment-billing-and-card-form-polish

> 任务：`TASK-20260919081652-95da9e2f` ｜ Gate：`GATE-2026-09-19T08-17-10`（feature）｜ 风险：quick（路径/描述触发 critical → `--override quick` + recovery）

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

关键词：`cardholderRequired` / `cardholderName` / `billing-use-shipping` / `sameAsShipping` / `billing_mode` / `billing_address`。

| 层 | 搜索路径 | 找到的文件 | 是否满足需求？ |
|---|---|---|---|
| App — models/controllers/views | `backend/app/` | 无（宿主不渲染结账页） | 否（无需改） |
| Core Gem — services | `backend/pallastrade_gems/pallastrade_core/app/services/pallastrade/carts/` | `update.rb#assign_billing_mode`（`same_as_shipping` 清空账单地址；`custom` 校验最小完整集后落库）、`submit.rb:103`（账单快照：显式优先，否则复制配送） | ✅ 服务端语义已完整，**无需改动** |
| API Gem | `.../pallastrade_api/app/controllers/.../store/carts_controller.rb` | `permitted_params` 含 `billing_mode` + `billing_address`（PALLAS-CUSTOM 注释：未 permit 时被静默丢弃） | ✅ 白名单齐备 |
| Admin Gem | `.../pallastrade_admin/app/` | `orders/billing_address_controller.rb`（后台可改账单地址，`same_as_shipping` 分支） | 无关（后台侧已闭环） |
| Storefront | `storefront/src/` | `CardPaymentForm.tsx:114-122`（姓名必填）、`UnifiedCheckout.tsx:772-786`（`billing_mode` 载荷）、`:753-760`（`billAddressComplete`）、`:850`（提交前拦截）、`:1398-1436`（账单区块**仅卡分支**）、`:1440+`（确认区**无账单行**） | ✅ **本需求全部在前台** |
| Platform | `platform/packages/` | 无相关 UI/类型 | 否（无需改） |

### 搜索结论

- 账单**服务端链路已闭环**（billing_mode/白名单/快照），缺口在前台：文案语境、控件作用域、确认回显。
- 姓名可选在提交侧**已然支持**（`CardPaymentForm.tsx:147-149` 仅非空才传 name），只需删除校验分支。
- 变更面 = 2 个前台组件 + 5 个文案文件 + 2 个测试文件 + 文档同步。

## Step 1：Skill 文件咨询（功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 优先级链最高档为"改设置"，最低档为"改契约/Gem"；本次仅动前台呈现与校验，**不触碰服务端语义** |
| `ai/skills/harness-prd/SKILL.md` | ✅ 已读 | 一句话需求 → PRD（背景/FR/AC/技术影响/测试计划/文档同步）→ 用户确认 → gate → 实施 → 知识同步 |
| `ai/skills/pallastrade-storefront/SKILL.md` | ✅ 已读 | Checkout 章节：账单语义 `billing_mode`（`same_as_shipping` / `custom`）+ 取消勾选需完整地址（`billingAddressIncomplete`）；money 契约；biome(80)+typecheck 红线 |

**按需 Skill（本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-checkout` | ✅ | ✅ 已读 | 两段语义：`Prepare`（`carts.update` + `carts.submit`）→ 页内确认区；账单语义随 `carts.update` 落库，确认区应与之同源展示 |
| `pallastrade-i18n` | ✅ | ✅ 已读 | 新增键五语言齐备 + `checkout-i18n-keys.test.ts` REQUIRED 登记；删除键前确认无其它引用 |
| `pallastrade-payments` | ✅ | ✅ 已读 | Stripe 侧 `billing_details.name` 可选；账号/卡表单文案属前台渲染面（Stripe Elements 语种已按站点语言跟随） |
| `pallastrade-api-v3` / `pallastrade-decorators` / `pallastrade-events-webhooks` / `pallastrade-dependencies` | ❌ | — | 零后端改动 |

---

## 需求标题

卡表单姓名改选填；账单区块加语境标题并对所有支付方式可见；确认区回显账单地址。

## 任务类型

功能优化（前台校验 + 结构与文案；零后端）。

## 需求描述

支付区的持卡人姓名现在必须填，但输入框写着"可选"，两者矛盾；账单部分只有一句"Same as shipping address"，没有"Billing address"的语境，而且这个勾选框只在刷卡表单里出现，用钱包时看不到；下单前的确认区也没有回显账单地址。本次把姓名改为真正可选、账单区块带上标题并对所有支付方式可见（钱包改为说明来源）、确认区把账单地址显示出来。

## 影响范围

- 前端：`CardPaymentForm.tsx`（校验）、`UnifiedCheckout.tsx`（账单区块 + 确认区）
- 文案：`messages/{en,de,es,fr,pl}.json`（+`billingFromWallet`，−`cardholderRequired`）
- 测试：`CardPaymentForm.test.tsx`、`UnifiedCheckout.test.tsx`、`checkout-i18n-keys.test.ts`
- 文档：PRD/REQ、storefront Skill、场景库 GS-192
- **零**后端 / 契约 / SDK 改动

## 技术方案（初步）

① 删除 `CardPaymentForm#validate()` 中姓名必填分支；② 把账单区块（标题 `Billing Address` + 勾选 `Same as shipping address` + 自定义地址字段）移到支付表单之后、`selectedMethod` 作用域内，使所有支付方式可见；钱包分支渲染 `billingFromWallet` 说明；③ 确认区新增 `quote-billing` 行（同配送 → 既有键；自定义 → 地址摘要）。

## 验证方案（AC 映射）

| AC | 命令/测试 |
|---|---|
| AC-001 | `npx harness verify storefront-test --task TASK-20260919081652-95da9e2f`（`CardPaymentForm.test.tsx`） |
| AC-002 ~ AC-004 | 同上（`UnifiedCheckout.test.tsx`：区块结构、钱包说明、确认区账单行） |
| AC-005 | 同上（`checkout-i18n-keys.test.ts`） |
| 格式化/类型 | `pnpm -C storefront check`、`pnpm -C storefront typecheck`、`pnpm -C storefront check:locales` |

## 用户确认

✅ 已确认（2026-09-19）——用户原话：「**实施：第3项 第4项的一期**」。
