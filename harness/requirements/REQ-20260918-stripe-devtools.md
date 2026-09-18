# REQ-20260918-stripe-devtools

> 关联 PRD：`docs/prd/payments/PRD-20260918-payments-隐藏-stripe-elements-开发者工具入口-测试模式右下角浮层.md`
> 任务：`TASK-20260918152638-594c23cf`（gate `GATE-2026-09-18T15-26-48`，类型 feature）

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | `developerTools` / `devtools` / `loadStripe` / `easel` | 无 | ❌ 后端不下发 Stripe.js 初始化参数 |
| App — views/decorators | `backend/app/` | 同上 | 无 | ❌ 不涉及 |
| Core Gem — models | `backend/pallastrade_gems/pallastrade_core/app/models/` | 同上 | 无 | ❌ 不涉及 |
| Core Gem — services | `backend/pallastrade_gems/pallastrade_core/app/services/` | 同上 | `Payments::Availability::*`（入口可用性，与本次无关） | ❌ 不涉及 |
| API Gem — controllers | `backend/pallastrade_gems/pallastrade_api/app/controllers/` | `client_config` / `devtools` | 无（`PaymentMethodSerializer` 只下发 publishable 级密钥） | ❌ 契约无需变更 |
| Admin Gem — controllers | `backend/pallastrade_gems/pallastrade_admin/app/controllers/` | `devtools` | 无（`pallastrade_dev_tools` gem 为 Rails 开发工具，与 Stripe 无关） | ❌ 不涉及 |
| Admin Gem — views | `backend/pallastrade_gems/pallastrade_admin/app/views/` | `devtools` | 无 | ❌ 不涉及 |
| **Storefront** | `storefront/src/` | `loadStripe(` / `developerTools` | **`src/lib/utils/stripe.ts`（`getStripePromise`，前台唯一实例化点）** | ✅ **主修点（FR-001）** |
| **Platform** | `platform/packages/` + `platform/payments/` | `loadStripe` / `@stripe/stripe-js` | **`platform/payments/pallastrade_stripe/app/javascript/pallastrade_stripe/controllers/stripe_button_controller.js`**（`loadStripe(...)` 与全局 `Stripe(...)` 两条分支） | ✅ **次修点（FR-002）** |

### 搜索结论

- 全仓存在**两处** Stripe.js 实例化点（前台 Next.js + platform Stimulus），必须同修，否则「修一个入口又从另一个入口冒出来」。
- 后端 / API / Admin **零改动**：`client_config`（D10）只负责密钥下发，Stripe.js 构造选项属于前端职责。
- 无重复实现：仓库内不存在任何针对该浮层的既有处理（无 CSS 补丁、无 DOM 移除逻辑）。

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树优先级 = **Settings → Configuration → Events → Dependencies → Admin/Ransack → Generators → Decorators → Extensions**；本任务既不新增模型/接口、也不改后端行为，属**前端集成参数**，因此**不走** decorator / subscriber / config 路径（避免过度定制） |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | 覆盖「新增 admin resource / 定制 sidebar / admin tables」；本任务无任何后台页面、导航或表格改动 → **不涉及** |
| `ai/skills/pallastrade-catalog/SKILL.md` | ✅ 已读 | 覆盖 catalog graph（Product/Variant/Category）；本任务不触碰商品域 → **不涉及** |

**按需 Skill（勾选本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-payments` | ✅ | ✅ 已读 | D10「前台密钥下发」：服务端在 `payment_methods[].client_config` 下发 publishable 级凭据，前端**先读 API、回落 `NEXT_PUBLIC_*`**；本次正是把**官方 `developerTools` 选项**加在该初始化点上（密钥来源不变） |
| `pallastrade-storefront` | ✅ | ✅ 已读 | checkout 支付区读服务端 `entries[]`、钱包行为由 `paymentMethods=always` + 设备能力两轴决定；本次只改 Stripe.js **构造选项**，不动 `entries`/元素渲染 |
| `pallastrade-testing` | ⬜ | ⬜ | — |
| `pallastrade-api-v3` | ⬜ | ⬜ | — |
| `pallastrade-decorators` | ⬜ | ⬜ | — |
| `pallastrade-dependencies` | ⬜ | ⬜ | — |
| `pallastrade-events-webhooks` | ⬜ | ⬜ | — |
| `pallastrade-i18n` | ⬜ | ⬜ | — |
| `pallastrade-prd` / `harness-prd` | ✅ | ✅ 已读 | PRD 流程：`prd new`（查重）→ 模板扩充 → **用户确认** → gate + REQ → AC↔测试映射 → 知识同步门；本 REQ 即为该流程的产物 |

---

## 需求标题

隐藏 Stripe Elements 开发者工具入口（测试模式右下角浮层）—— 通过官方 `developerTools` 构造选项关闭。

## 任务类型

功能优化（前端集成参数）

## 背景（证据链）

1. dev 使用测试密钥（`pk_test_…`），Stripe.js 在测试模式下注入悬浮「开发者工具」入口（Easel UI）。
2. Stripe 面板自述：*"It only shows in development—your customers should never see it."* + **How to disable** 链接。
3. Stripe.js 常量：`title.easel = "Stripe developer tools frame"`；aria-label `Open Stripe Developer Tools`。
4. 注入条件（主包）：`window.top === window` + `keyMode() === "test"` + 组件名单 + `developerToolsOptions.assistant.enabled`。
5. **官方开关**：`Stripe(pk, { developerTools: { assistant: { enabled: false } } })`；`@stripe/stripe-js` 的 `StripeConstructorOptions` 已公开声明该字段；内部逻辑 `void 0 !== e.assistant.enabled ? 采用用户值（上报 easel.user_set_easel_option）`。

## 设计要点

- 在 `getStripePromise()`（前台唯一 `loadStripe` 调用点）传入关闭选项，常量集中定义并写清「为什么关闭 / 如何恢复」。
- platform Stimulus 控制器两条实例化分支（`loadStripe` 与全局 `Stripe`）同步传入。
- **禁止**任何基于 DOM/CSS 的隐藏（Easel 类名 hash 随版本漂移，且同体系承载真实支付 UI）—— 写进 PRD AC-006 做机器断言。
- 不新增环境变量/后台开关（非目标），避免把「调试开关」做成产品配置面。

## 验收标准

见 PRD §5（AC-001~AC-007）。AC ↔ 测试/检查映射：

| AC | 落实 |
|---|---|
| AC-001 | `storefront/src/lib/utils/__tests__/stripe-client-config.test.ts` → “passes the official developerTools opt-out to loadStripe” |
| AC-002 | 同上 → “applies the opt-out for both key sources” |
| AC-003 | 同上 → “keeps the per-key cache and the same options”；既有两例断言补第二参 |
| AC-004 | 既有“未配置 → null”用例保留 |
| AC-005 | `git grep` 静态检查（命令见 PRD §8） |
| AC-006 | `git grep` 静态检查（命令见 PRD §8） |
| AC-007 | `harness verify storefront-test`（全量）+ dev 部署后浏览器复验 |

## 实施记录

- `storefront/src/lib/utils/stripe.ts`：新增 `STRIPE_DEVELOPER_TOOLS_DISABLED` 常量（PALLAS-CUSTOM 注释写清根因/为何不用 CSS/如何恢复）并在 `getStripePromise()` 传入。
- `platform/payments/pallastrade_stripe/app/javascript/pallastrade_stripe/controllers/stripe_button_controller.js`：新增 `DEVELOPER_TOOLS_DISABLED` 并传给 `loadStripe(...)` 与 `Stripe(...)` 两条分支。
- `storefront/src/lib/utils/__tests__/stripe-client-config.test.ts`：+3 例（AC-001/002/003），2 例既有断言补第二参。
- 文档：`ai/skills/pallastrade-payments/SKILL.md`（新增小节）、`ai/skills/pallastrade-storefront/SKILL.md`（D10 条目后追加）。

## 风险与回滚

- 风险：选项若被旧版 Stripe.js 忽略 → 行为退回现状（不报错，无副作用）。
- 回滚：删除传入选项即可（单提交 `git revert`），无数据/资金副作用。
