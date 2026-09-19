# REQ-20260919-checkout-remove-shipping-change-placeholder-banner

> 任务：`TASK-20260919070345-9fbd1f71` ｜ Gate：`GATE-2026-09-19T07-03-55`（feature）｜ 风险：quick（paths 因子被并行会话未提交后台文件抬为 critical → `--override quick` + recovery）

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

关键词：`shippingOptionsChanged` / `shipping-options-changed` / `quote_changed` / `shipping options have changed`。

| 层 | 搜索路径 | 找到的文件 | 是否满足需求？ |
|---|---|---|---|
| App — models/controllers/views | `backend/app/` | 无（宿主不承载结账页渲染） | 否（也无需改） |
| Core Gem | `backend/pallastrade_gems/pallastrade_core/app/` | 无 `shipping_options_changed` 类信号（本轮复检 `grep -r` 零命中）；运费权威计算在 `Carts::Submit#build_fulfillment!`（`set_shipments_cost`） | ❌ 后端**不存在**该信号 → 提示框无从被驱动 |
| API Gem | `backend/pallastrade_gems/pallastrade_api/app/` | `store/shipping_methods_controller.rb`（注释明写「**权威运费在提交订单（Carts::Submit）时按所选方式在 Order 上计算**」）；报价漂移经 `quote_changed` / `checkout_version_conflict` 错误码下发 | ✅ 漂移信号已存在 |
| Admin Gem | `backend/pallastrade_gems/pallastrade_admin/app/` | 无关（后台不渲染结账页） | — |
| Storefront | `storefront/src/` | `UnifiedCheckout.tsx:1246-1260`（占位提示块，注释自述"占位，后端推送变更信号后驱动"）；`:1059-1093` 顶部 `checkout-quote-diff` 横幅（真实信号面）；`__tests__/UnifiedCheckout.test.tsx:873` 断言其存在 | ✅ **本需求全部在前台**；提示框为占位遗留 |
| Platform | `platform/packages/` | 无相关 UI/类型（SDK 无 `shippingOptionsChanged` 字段） | 否 |

### 搜索结论

- 后端**从未**提供 `shipping_options_changed`；提示框是恒显占位 → 删除是唯一正确修法（方案 A）。
- 真实运费漂移的既有呈现面 = 顶部 `checkout-quote-diff`（`quote-diff-shipping` 行），无需新增能力。
- 变更面 = 1 个组件 + 5 个文案文件 + 1 个测试 + 文档同步。

## Step 1：Skill 文件咨询（功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 优先级链「Settings → Configuration → Events → Dependencies → Admin/Ransack → Generators → Decorators → Extensions」；本次为**删除错误占位**（前台呈现层），最高优先级选择（不改任何后端行为） |
| `ai/skills/harness-prd/SKILL.md` | ✅ 已读 | 一句话需求 → `prd new` → 扩充 → 用户确认 → gate → 实施 → `prd verify` → 知识同步 → evidence；REQ 完整版判定（涉及源码 + 文案 + 测试 > 5 文件） |
| `ai/skills/pallastrade-storefront/SKILL.md` | ✅ 已读 | Checkout 章节：`UnifiedCheckout` 主列组成与两段语义；**money 契约**（raw 判逻辑 / `display_*` 仅渲染）；改 storefront 必须跑 `pnpm check`(biome 80) + `pnpm typecheck` |

**按需 Skill（本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-checkout` | ✅ | ✅ 已读 | 报价漂移经 `quote_changed`/`checkout_version_conflict` → 页内 `checkout-quote-diff`（`quoteRowShipping` 行）展示 before → after 并要求重新确认；本 PRD 不改该链路 |
| `pallastrade-i18n` | ✅ | ✅ 已读 | 删除键必须五语言同步删除；`checkout-i18n-keys.test.ts` 的 REQUIRED 表仅守护"必须存在"的键（本键不在表内，删除不需改守护表） |
| `pallastrade-api-v3` / `pallastrade-decorators` / `pallastrade-events-webhooks` / `pallastrade-dependencies` | ❌ | — | 零后端改动 |

---

## 需求标题

删除 checkout 物流方式区块中恒显的「配送选项已变化」占位提示。

## 任务类型

功能优化（前台结构 + 文案清理）。

## 需求描述

结账页第 3 节（Shipping method）里有一句固定的黄框提示「The shipping options have changed for your order. Review your selection.」。按现有交易链路，只有服务端真的改了运费/物流（报价漂移）时才该提示，而目前它在每次进页面时都显示。真实变化已经由页面顶部的报价差异横幅表达，因此删除这个占位提示框，并清理对应文案键。

## 影响范围

- 前端：`UnifiedCheckout.tsx`（删块）
- 文案：`messages/{en,de,es,fr,pl}.json`（删 `shippingOptionsChanged` 键）
- 测试：`UnifiedCheckout.test.tsx`（断言反转 + 漂移横幅回归）
- 文档：PRD/REQ、storefront Skill、场景库 GS-190
- **零**后端 / 契约 / SDK 改动

## 技术方案（初步）

删除 `UnifiedCheckout.tsx` 第 3 节内的 `div[data-testid="shipping-options-changed"]`（含图标与文案）；顶部 `checkout-quote-diff` 逻辑保持不变（唯一真实信号面）。五语言删除 `checkout.shippingOptionsChanged`。

## 验证方案（AC 映射）

| AC | 命令/测试 |
|---|---|
| AC-001 / AC-002 / AC-003 | `npx harness verify storefront-test --task TASK-20260919070345-9fbd1f71`（`UnifiedCheckout.test.tsx`：无占位元素 + 节标题/单选回归 + `checkout-quote-diff` 用例保持通过） |
| AC-004 | 同上（`checkout-i18n-keys.test.ts` 五语言键集一致） |
| 格式化/类型 | `pnpm -C storefront check`、`pnpm -C storefront typecheck`、`pnpm -C storefront check:locales` |

## 用户确认

✅ 已确认（2026-09-19）——用户原话：「**实施：第2项：方案A**」（在我的分析中，第 2 项方案 A = 删除占位提示，物流变化统一由顶部报价差异横幅表达）。
