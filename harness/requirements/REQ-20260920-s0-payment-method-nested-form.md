# REQ-20260920-s0 — 后台支付方式页嵌套表单（账户配置保存落到主表单）

- **类型**：bugfix（S0，支付核心统一 PRD-20260920-checkout 的前置修复切片）
- **Task**：`TASK-20260920140411-b33e72d1`
- **Gate**：`GATE-2026-09-20T14-04-21`
- **风险**：critical（改动落 `backend/pallastrade_gems/pallastrade_admin/**` 框架视图）
- **影响面**：`backend/pallastrade_gems/pallastrade_admin/app/views/pallastrade/admin/payment_methods/{edit,_form,_breaker}.html.erb` + `backend/spec/requests/pallastrade/admin/payment_provider_account_spec.rb`
- **不触碰**：写路径（controller action / 表单参数形状 / `Providers::Account`）、core 服务、SDK、storefront、`platform/payments/**`

## 1. 缺陷描述（现象 → 机制）

**现象**：后台「设置 → 支付方式 → Stripe」编辑页，点诊断卡内「保存账户配置」：
账户配置**没有保存**，而**主表单被保存了一次**（用页面上当时填的内容）。无报错、无提示。

**机制**（HTML5 解析，非猜测）：

| 步骤 | 发生的事 |
|---|---|
| ① | `edit.html.erb` 的 `form_for`（主表单）打开 |
| ② | `_form.html.erb` 内 render `_provider_diagnostics`，其 `form_with`（账户配置）产生**内层 `<form>` 起始标签** |
| ③ | HTML5 解析器发现 form element pointer 非空 → **丢弃**该起始标签（parse error）；内层控件全部落入外层主表单 |
| ④ | 内层 `</form>` 把**外层** form 从开放元素栈移除（外层在 DOM 里仍是祖先，故页面看起来正常、保存按钮照样能用） |
| ⑤ | 后续出现的 `<form>` 起始标签（`_breaker` 的软置灰）因 form pointer 已归零而**能被正常创建** → 该功能侥幸可用 |

**为什么长期没被发现**：`payment_provider_account_spec.rb` 用 `post` **直打端点**（绕开浏览器），
渲染断言只检查 `[data-testid='provider-account-form']` 存在，**从不校验 form 归属**。

**连带风险（本次必须同修的根因）**：只有**第一个**嵌套 form 会失去身份。因此：
- 只修账户表单 → `_breaker` 变成第一个嵌套 form → **软置灰立即退化成"提交落到主表单"**
- 只修 `_breaker` → 账户配置维持现状（坏）
→ **两者必须一起移出主表单**。

## 2. Step 0 六层跨层搜索（R4，每层独立执行）

| 层 | 搜索路径 | 关键词 | 结果 | 是否修改层 |
|---|---|---|---|---|
| **App** | `backend/app/` | `payment_option\|provider_account\|payment_methods` | 仅命中生成的 TS 类型（`PallasTradeApiV3*` / `StoreCheckoutCheckout` 的 `payment_methods` 数组字段），无后台表单/视图/控制器 | ❌ |
| **Core** | `backend/pallastrade_gems/pallastrade_core/app/` | `provider_account\|provider_account_config` | 仅 `PaymentMethod#provider_account_config`（读 `metadata['account']`）等读路径 | ❌ |
| **API** | `backend/pallastrade_gems/pallastrade_api/app/` | `payment_option\|entries` | `admin/payment_method_serializer`（暴露 `payment_options` + `scope_summary`，只读）；store 侧 `payment_option_entries` / `checkout_serializer` —— 均为读模型，不渲染后台表单 | ❌ |
| **Admin** | `backend/pallastrade_gems/pallastrade_admin/app/` | 同上 | **命中**：`payment_methods/edit.html.erb`（主表单）+ `_form.html.erb`（内 render 诊断卡）+ `_provider_diagnostics.html.erb`（嵌套 form #1）+ `_breaker.html.erb`（嵌套 form #2） | ✅ **修改层** |
| **Storefront** | `storefront/src/` | `provider_account\|option_kind\|payment_options` | `UnifiedCheckout` / `ExpressCheckoutButton` / `WalletPaymentButtons` / `lib/checkout/server.ts` 的 `option_kind` 透传（前台消费入口语义），不参与后台表单 | ❌ |
| **Platform** | `platform/packages/` | 同上 | 仅 SDK 类型（`src/types/index.ts` + `dist` 生成物） | ❌（SDK 不动） |

**同层补充**：`_credentials.html.erb`（reveal = `link_to + turbo_method`）、`custom_form_fields/_pallastrade_stripe.html.erb`（纯链接）、
`_options.html.erb`（测试连接 = `link_to + turbo_method`）**均无 `<form>`** → 本页只有上述两处嵌套。

## 3. Skill 咨询表（R2，逐项真实结论）

| Skill | 读取位置 | 结论（对本次的影响） |
|---|---|---|
| `pallastrade-admin` §419「支付方式选项化」 | `ai/skills/pallastrade-admin/SKILL.md` | **直接命中**：明文约定「`_options.html.erb` 挂在主表单内（随保存一起提交，**勿再嵌套 `<form>`**）」与「Test connection 按钮用 `link_to + turbo_method`（Turbo 栈约定，**非嵌套表单**）」→ **P0-B 的诊断卡 `form_with` 违反了既有约定**；修复方向由本约定给出 |
| `pallastrade-admin` §444「支付凭据与环境」（D9） | 同上 | 确认 reveal 已是 Turbo 栈约定（无 form）；本次不触碰 |
| `pallastrade-admin` §452「支付熔断与健康」（D11） | 同上 | 确认 `_breaker.html.erb` 提供软置灰表单；本次只移动其渲染位置，**不动其请求契约**；并记入"路径参数用 `prefixed_id`"的历史坑 |
| `pallastrade-admin` §588「支付适用范围编辑」（D8） | 同上 | 确认 `_options` 的 `rule_set` 随主表单提交 —— 本次不触碰，保持零回归 |
| `pallastrade-payments` §177「厂商层 P0-A/P0-B」/ §P3 | `ai/skills/pallastrade-payments/SKILL.md` | 确认「诊断卡内账户配置表单（P0-B）是唯一的写入口」+「`update_provider_account` 走 `Account.write!`、`authorize! :update`、审计、幂等」→ **本次只改渲染位置，写路径与语义零改动** |
| `pallastrade-testing` | 领域测试约定 | 渲染断言用 `Nokogiri::HTML5`（与浏览器同算法）；request spec 必须签入并有 `update` 权限 |

## 4. 验收标准（AC）与测试映射

| AC | 内容 | 映射测试 |
|---|---|---|
| **AC-1** | 账户配置的提交控件，其"浏览器表单所有者"是该功能自己的 member 路由（`…/update_provider_account`），而非主表单 | `payment_provider_account_spec.rb` → `renders the account form outside the main form and lets its submit own it` |
| **AC-2** | 软置灰的提交控件，其表单所有者是 `…/soft_disable` | 同文件 → `renders the breaker form outside the main form and lets its submit own it` |
| **AC-3** | 主表单子树内**不得存在任何 `<form>` 元素** | 同文件 → `keeps the main edit form free of nested forms` |
| **AC-4** | 写路径零改动：`update_provider_account` / `soft_disable` 的既有请求契约全绿 | `harness verify payment-providers-rspec`、`harness verify d11-circuit-breaker-rspec` |
| **AC-5** | 同页其他卡片零回归（选项化页签 / 适用范围 / 凭据 / 诊断渲染） | `admin-payment-methods-rspec`、`d8-availability-rspec`、`d9-credentials-rspec` |

**证据口径（TDD 红灯 → 绿灯）**：
- 修复前：`payment_provider_account_spec.rb` → **9 examples, 2 failures**，失败信息直击根因
  （`账户配置的提交会落到 "/admin/payment_methods/pm_55dQZnCRf8"`）。
  同批 `_breaker` 断言**通过** —— 与浏览器实测一致，印证"只有第一个嵌套 form 失去身份"。
- 修复后：**9 examples, 0 failures**；5 个验证器全绿。

## 5. 决策记录（为什么这样修）

| 选项 | 取舍 |
|---|---|
| 改用 Turbo 栈约定（`link_to + turbo_method`） | ❌ 账户配置有 3 个多选、软置灰需要 `reason` 文本 —— 无法用链接携带 |
| 把账户配置并入主表单保存 | ❌ 会改动写路径语义（`update_columns` 幂等/不审计 → 变成走 provider 校验，Stripe `validate_secret_key` 每次保存发远端请求），超出 bugfix 边界 |
| **把两张卡的渲染移到主表单之外** | ✅ 最小、零写路径改动、视觉位置基本保持；且与 S1 之后的页面重设计方向一致 |

**已知视觉变化**：熔断卡由「凭据卡之后、保存按钮之前」变为「保存按钮之后」（因其必须脱离主表单）。
诊断卡保持内容列顶部不变。

## 6. 残留与后续

- 本切片**不动** `platform/payments/**`（standalone 副本，运行时以 `backend/pallastrade_gems/**` 为准；镜像同步为仓库治理决策）。
- 已知漂移（另案）：`developerTools` 修复只落在 `platform/payments/pallastrade_stripe`，`backend` 份缺失。
- 后续切片（S1–S3，见 Stripe 详情页方案）：诊断卡收缩、方式列表（全目录 + 四象限）、账户同步、删范围 UI。
