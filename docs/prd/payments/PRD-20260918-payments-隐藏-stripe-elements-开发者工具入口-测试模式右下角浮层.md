# PRD-20260918-payments-隐藏-stripe-elements-开发者工具入口

| 元数据 | 值 |
|---|---|
| 状态 | implementing |
| 创建日期 | 2026-09-18 |
| 来源 | 优化：checkout 页面右下角会显示 Stripe 开发者工具入口，隐藏掉 |
| 分类 | payments（自动判定） |
| 关联 Skill | `pallastrade-payments`（主）、`pallastrade-storefront`（消费面） |
| 关联 REQ | REQ-YYYYMMDD-stripe-devtools.md（实施时回填） |
| 关联 PRD | N/A（查重未命中，属全新需求） |
| 需求类型 | 优化迭代 |

---

## 1. 背景与目标

- **一句话需求原文**：优化，checkout 页面右下角会显示 stripe 开发者工具入口，隐藏掉。
- **背景**：
  - dev 环境（`dev.pallastrade.cn`）使用 Stripe **测试密钥**（`pk_test_…`），Stripe.js 在测试模式下会向页面注入一个**悬浮的开发者工具入口**（黑色圆形按钮，点击展开“填测试卡 / 模拟支付失败 / 事件”面板），遮挡结账页右下角，演示与验收时容易被当成产品缺陷。
  - **它确实是 Stripe 官方的调试 UI，不是我们的代码**。证据链：
    1. 面板原文（Stripe 自述）：*"We built this widget to give developers helpful shortcuts, testing tools, and timely guidance when integrating Stripe Elements into your checkout pages. **It only shows in development—your customers should never see it.**"*，并带一个 *"How to disable"* 链接；
    2. Stripe.js 内的 iframe 标题常量：`title.easel = "Stripe developer tools frame"`，按钮 aria-label：`easel.aria.stripe_dev_tools.open = "Open Stripe Developer Tools"`；
    3. 注入条件（主包反编译）：仅当 `window.top === window`（顶层窗口）+ `keyMode() === "test"` + 组件在允许名单内，且 `developerToolsOptions.assistant.enabled` 为真；
    4. **官方关闭开关**：`Stripe(pk, { developerTools: { assistant: { enabled: false } } })` —— `@stripe/stripe-js` 的 `StripeConstructorOptions` 公开声明了该字段；Stripe.js 内部逻辑为 `void 0 !== e.assistant.enabled ? 采用用户值（并上报 easel.user_set_easel_option） : 默认值`，即**显式传 false 会被尊重**。
  - 为什么不能 “等生产就没了”：客户确实看不到，但 dev/staging 是团队演示、录屏、验收的主要环境，且未来预发环境同样使用测试密钥，会持续干扰；同时团队对“页面右下角冒出一个未知控件”存在安全与合规疑虑。
  - 为什么**不**用 CSS 屏蔽：控件属于 Stripe 的 Easel UI 体系（`<hash>__Easel-contentWrapper`），其类名 hash 随 Stripe.js 版本变化，且同一体系还承载支付面 UI（卡片/钱包/弹层）——盲屏蔽会把真实支付 UI 一并弄挂。
- **目标**：在**所有我们实例化 Stripe.js 的地方**，以官方选项关闭该开发者工具入口；不引入 DOM/CSS 修补、不影响支付面。
- **非目标**：
  - 不改变测试/生产密钥策略，不引入新的环境变量或后台开关；
  - 不隐藏 Stripe 的正常支付 UI（卡表单、钱包、Link、弹层）；
  - 不删除开发人员的调试能力（需要时可用浏览器本地覆盖或临时改回默认值）。
- **成功指标**：
  - dev 结账页右下角**不再出现** “Open Stripe Developer Tools” 入口与 `Stripe developer tools frame` iframe；
  - 支付区渲染（卡表单 / Apple Pay / Google Pay 入口）与支付链路**零回归**；
  - 全部受影响入口有自动化断言，防止后续升级 Stripe.js 时回归。

## 2. 用户故事 / 场景

- 作为**店铺运营/演示者**，我希望 dev 结账页跟生产一致（没有调试浮层），以便向客户演示与录屏。
- 作为**前端工程师**，我希望关闭方式走官方选项而不是 CSS 补丁，以便 Stripe.js 升级后不失效。
- 作为**支付维护者**，我希望所有 Stripe.js 实例化点都�一同处理，以便不会“修了一个入口又从另一个入口冒出来”。

场景列表：

| # | 场景 | 期望 |
|---|---|---|
| S1 | 正常流：测试密钥下打开 `/{country}/{locale}/checkout/{cart}` | 无开发者工具入口；卡表单/钱包入口照常渲染 |
| S2 | 边界：`NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY` 回落路径（API 未下发 `client_config`） | 同样无入口（选项与密钥来源无关） |
| S3 | 边界：同一 key 重复调用 `getStripePromise` | 仍只 `loadStripe` 一次（既有缓存语义不变） |
| S4 | 异常：未配置密钥（`isStripeConfigured === false`） | 仍返回 `Promise.resolve(null)`，不报错 |
| S5 | 回归：钱包/卡支付正常发起 | 入口渲染与金额、`paymentMethods=always` 行为不变 |

## 3. 功能需求（FR）

- **FR-001**：`storefront` 的 Stripe.js 单例入口 `getStripePromise()`（`storefront/src/lib/utils/stripe.ts`，当前唯一调用点）在 `loadStripe(publishableKey, options)` 时必须传入 `{ developerTools: { assistant: { enabled: false } } }`，且该选项与密钥来源（API 下发 / 环境变量回落）无关。
- **FR-002**：`platform/payments/pallastrade_stripe` 的 Stimulus 控制器（第二处 Stripe.js 实例化点：`stripe_button_controller.js` 的 `loadStripe(...)` 与全局 `Stripe(...)` 两条分支）同步传入相同选项，避免“修一个入口又从另一个入口冒出来”。
- **FR-003**：注释必须写明**为什么**关闭（Stripe 官方开发者工具、仅测试模式注入、官方选项名与来源），以及**如何临时恢复**（本地改回默认值即可），避免后人误改。
- **FR-004**：不新增环境变量 / 后台开关；不引入任何基于 DOM 选择器的隐藏规则（禁止 `display:none` 补丁）。

## 4. 非功能需求（NFR）

- **兼容**：`developerTools` 已在 `@stripe/stripe-js@8.11.0` 的公开类型 `StripeConstructorOptions` 中声明，无需类型断言；旧版 Stripe.js 对未知选项为忽略，不会报错。
- **性能**：不增加额外网络请求（仅初始化参数变化）；`stripePromises` 的按 key 缓存语义不变。
- **安全**：不触碰密钥、不在前端暴露任何 secret；不改变 CSP/域名注册要求。
- **可维护**：关闭理由与来源（官方选项名 + 反编译依据）写在代码注释与 Skill 文档中，供后续升级核对。
- **可回归**：新增单测锁住“必须传该选项”，使 Stripe.js 升级或重构时能自动发现回归。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001** ← FR-001：调用 `getStripePromise(clientConfig)` 后，`loadStripe` 收到的第二个参数**恰好包含** `developerTools.assistant.enabled === false`。
- **AC-002** ← FR-001/S2：在“API 下发 key”与“环境变量回落 key”两条路径下均满足 AC-001。
- **AC-003** ← FR-001/S3：同一 key 连续调用两次 `getStripePromise`，`loadStripe` 仍只被调用一次，且选项一致。
- **AC-004** ← FR-001/S4：未配置密钥时返回 `null`、抛错为 0（既有行为不变）。
- **AC-005** ← FR-002：`platform` 侧控制器源码在两条实例化分支上都带有 `developerTools` 选项（静态检查，命令见 §8）。
- **AC-006** ← FR-004：仓库内不存在针对 Stripe Easel/开发者工具的 **CSS / 选择器补丁**（`*.css` 无 `Easel`；无 `querySelector*Easel` / `display:none*Easel` / `stripe_dev_tools`；代码注释里的说明文字不算）。
- **AC-007** ← 零回归：dev 结账页仍渲染 `payment-entry-row`（卡 + Apple Pay + Google Pay），支付区行为与金额展示不变；`storefront-test` 全绿。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | `developerTools` / `loadStripe` / `easel` | 无 | ❌ 不涉及（后端不发前端初始化参数） |
| Core | `backend/pallastrade_gems/pallastrade_core/app/` | 同上 | 无（仅 `PaymentMethods::ClientConfig` 下发密钥，不下发 Stripe.js 选项） | ❌ 不动 |
| API | `backend/pallastrade_gems/pallastrade_api/app/` | 同上 | `PaymentMethodSerializer#client_config`（D10 密钥下发） | ❌ 无需改契约（选项在前端初始化时传） |
| Admin | `backend/pallastrade_gems/pallastrade_admin/app/` | 同上 | 无（`PallasTradeDevTools` gem 是 Rails 开发工具，与 Stripe 无关） | ❌ 不涉及 |
| **Storefront** | `storefront/src/` | `loadStripe(` | **`src/lib/utils/stripe.ts`（唯一调用点，`getStripePromise`）** | ✅ **主修点** |
| **Platform** | `platform/packages/` + `platform/payments/` | `loadStripe` / `@stripe/stripe-js` | **`platform/payments/pallastrade_stripe/app/javascript/…/stripe_button_controller.js`**（`loadStripe(...)` + 全局 `Stripe(...)` 两分支） | ✅ **次修点（FR-002）** |

**结论**：
- 前台（Next.js）与平台（Stimulus）存在**两处** Stripe.js 实例化点，必须同修；
- 后端/API/Admin **不需要**任何契约或数据变更（密钥下发已由 D10 统一）；
- 防重复：不要新增“隐藏浮层”的通用工具函数或 CSS 类，直接使用官方选项。
- 环境验证补充：headless / 伪装 `navigator.webdriver` / 真实 Chrome 三种自动化环境均**未**复现该控件（说明其注入还受环境因素影响），因此验收以**选项传递**为硬断言，浏览器侧仅做“不出现”的辅助观察。

## 7. 技术影响

- **改动文件**（预期）：
  - `storefront/src/lib/utils/stripe.ts`（+ 常量与注释）
  - `storefront/src/lib/utils/__tests__/stripe-client-config.test.ts`（+ AC 断言；已有 `loadStripe` mock 可直接复用）
  - `platform/payments/pallastrade_stripe/app/javascript/pallastrade_stripe/controllers/stripe_button_controller.js`
  - 文档：`ai/skills/pallastrade-payments/SKILL.md`、`ai/skills/pallastrade-storefront/SKILL.md`、`docs/prd/README.md`
- **依赖 / 数据库 / 接口**：无新增依赖、无迁移、**无 OpenAPI/SDK 变更**（`generated:check` 预期无差异）。
- **影响面**：仅 Stripe.js 初始化参数；支付业务流程、会话创建、金额口径均不变。
- **回滚**：`git revert` 单个提交即可；无数据/资金副作用。

## 8. 测试计划

| AC | 测试文件 | 变更点 |
|---|---|---|
| AC-001 | `storefront/src/lib/utils/__tests__/stripe-client-config.test.ts` | 新增：断言 `loadStripe` 第二参包含 `developerTools.assistant.enabled === false` |
| AC-002 | 同上 | 参数化：API 下发 key / 环境变量回落 key 两路径 |
| AC-003 | 同上 | 断言同 key 二次调用仍只 `loadStripe` 一次（缓存语义） |
| AC-004 | 同上 | 保留既有“未配置 → null”用例（回归） |
| AC-005 | 静态检查（命令固化） | `git grep -n "DEVELOPER_TOOLS_DISABLED\|loadStripe(this.apiKeyValue\|Stripe(this.apiKeyValue" -- platform/payments/pallastrade_stripe` → 两条分支均带选项 |
| AC-006 | 静态检查（命令固化） | `git grep -n Easel -- "*.css"` 为空；`git grep -nE "querySelector[^;]*Easel\|display: *none[^;]*Easel\|stripe_dev_tools"` 为空 |
| AC-007 | `storefront-test`（全量）+ 浏览器 | 支付区三入口渲染与钱包行为无回归（部署后浏览器复验） |

验证命令：`npx harness verify storefront-test --task <TASK-ID>`（新增后注册对应 verifier）。

## 9. 文档同步清单（知识同步门）

- [x] API 文档：**不涉及**（无接口/契约变更，`generated:check` 无差异）
- [ ] Skill 文档：`ai/skills/pallastrade-payments/SKILL.md` 新增“Stripe 开发者工具入口与其官方关闭开关”小节；`ai/skills/pallastrade-storefront/SKILL.md` 补一句（Stripe.js 初始化选项集中点）
- [ ] README 索引：`docs/prd/README.md` 新增本 PRD 行
- [ ] 反模式库 / 任务规则：**不涉及**（无新增反模式；但可在场景库补一条“不得用 CSS 屏蔽第三方调试 UI”）
- [ ] 本 PRD 状态更新 + `docs/prd/README.md` 索引

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-18 | 0.1 | 初稿：根因（Stripe 测试模式开发者工具 + 官方 `developerTools` 开关）+ FR/AC/跨层搜索/测试计划 | AI |
| 2026-09-18 | 0.2 | 用户确认「按 PRD 实施（前台 + platform 两处）」→ 实施：`stripe.ts` 常量 + 两处实例化点 + 3 例单测（含既有 2 例断言补第二参）；文档同步 payments/storefront Skill | AI |
