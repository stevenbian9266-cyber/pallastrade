# REQ-20260920-payment-core-unification（P0-A 厂商层地基）

> 任务：`TASK-20260920101239-8200a7d5` ｜ Gate：`GATE-2026-09-20T10-12-40` ｜ 风险：critical（requiredEvidence：test / review / approval / knowledge + recovery）
> 关联 PRD：`docs/prd/checkout/PRD-20260920-checkout-支付核心统一-厂商层-支付方式层-方式级路由-组合支付-订单失效期.md`（用户已确认「实施吧」）
>
> **切片说明**：P0 拆为 P0-A（本 REQ：厂商层地基 = 能力声明 / 账户配置 / 收窄校验 / 三态统一 / 后台诊断卡）与 P0-B（后台配置写路径 + 组合策略 + 付款期限）。本 REQ 只覆盖 P0-A。

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

关键词：`payment_method` / `payment_option` / `payment_option_catalog` / `provider` / `account` / `capabilit` / `breaker` / `active` / `seed`

| 层 | 搜索路径 | 找到的文件 | 是否满足需求？ |
|---|---|---|---|
| App — 宿主应用 | `backend/app/` | 无支付相关命中（无 controller/model/decorator/subscriber 涉及 provider 配置） | ❌ 无能力 |
| Core Gem | `backend/pallastrade_gems/pallastrade_core/app/` | `models/pallastrade/payment_method.rb`（`payment_options` / `optionized?` / `payment_option_catalog` / `breaker_state` / `environment` / `payment_option_rule_set` / `payment_option_entries`）；`services/pallastrade/payments/**`（27 个服务：`availability/{rule_set,evaluator,context,resolver}`、`circuit_breaker`、`three_d_secure`、`fees`、`costs`、`payment_combinations/**`、`health/metrics` 等）；`PaymentCombination` / `PaymentSplit` 模型（P1 数据层已存在） | ⚠️ **部分满足**：能力目录（`payment_option_catalog`，provider 可覆盖，Stripe 已声明 card/apple_pay/google_pay + `three_d_secure` 能力）与三态近似物（`active` boolean + breaker `manual/until`）已存在；**缺**账户级配置、能力∩账户∩市场收窄校验、统一三态 API、错配可解释诊断 |
| API Gem | `backend/pallastrade_gems/pallastrade_api/app/` | `serializers/pallastrade/api/v3/store/payment_method_serializer.rb`、`.../checkout/checkout_serializer.rb`、`controllers/.../orders/payment_preflight_controller.rb` | ⚠️ 只读投影（本切片不改契约） |
| Admin Gem | `backend/pallastrade_gems/pallastrade_admin/app/` | `controllers/pallastrade/admin/payment_methods_controller.rb`（`merge_payment_options_into` / `merged_payment_option_rule_set` / `normalize_payment_option` —— **非法 kind、越界 scope 值一律静默丢弃**）；`views/.../payment_methods/{_form,_options,_breaker,_credentials}.html.erb`；`helpers/pallastrade/admin/payments_helper.rb#payment_option_rows` | ⚠️ **写路径静默丢弃 = 错配无法暴露**（本次新增只读诊断卡补齐可解释性；写路径行为**不动**） |
| Storefront | `storefront/src/` | `components/checkout/{UnifiedCheckout,PaymentSection,WalletPaymentButtons,ExpressCheckoutButton,CardPaymentForm}.tsx`、`lib/checkout/wallet-availability.ts` | ⚠️ 只读消费（本切片不改） |
| Platform | `platform/packages/` | `sdk/src/store-client.ts`、`sdk/src/types/generated/**` | ❌ 本切片无契约变化 |

### 搜索结论

1. **「支付商（provider）层」在本仓不是缺席，而是"隐式"**：一个 provider 就是一条 `PallasTrade::PaymentMethod` 记录（STI `type` = 网关类），其入口集合 = `metadata['options']`，能力来源 = 类方法 `payment_option_catalog`。→ **不新建"厂商表"**（避免与既有 STI 模型重复），而是在既有模型上补**账户配置 + 收窄校验 + 统一三态**。
2. **本切片必须新增的能力（六层皆无）**：① 账户级配置（商家账户已开通的方式/币种/国家，支持手工录入与同步留痕）；② 静态能力声明（国家/币种/金额区间/幂等/结算，provider 类可覆盖）；③ **收窄校验**（启用项必须同时 ∈ 能力 ∩ 账户 ∩ 市场）；④ 三态统一读取（`enabled` / `disabled` / `suspended` + 手动停用粘连）；⑤ 后台**只读**诊断卡（把错配变成可解释清单）。
3. **防重复判定通过**：`Availability::RuleSet`（D8）管"入口适用哪些市场/国家/币种"，`CircuitBreaker`（D11）管"失败率熔断"，二者**语义不同**，本次只做**汇总读取 + 交叉校验**，不复制其判定逻辑（复用同一归一化口径）。
4. **零资金副作用**：本切片不碰 `Payment` / `PaymentSession` / `Transaction` / 账本；只读 `metadata` + 写入 `metadata['account']`（经 `update_columns`，与 D9/D11 同范式）。

## Step 1：Skill 文件咨询（feature 类型强制）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 定制优先级「Settings → Configuration → Events → Dependencies → Admin/Ransack APIs → Generators → **Decorators** → Extensions」。本切片 = 对既有 `PallasTrade::PaymentMethod` 的**结构性扩展**（新增服务 + 模型方法）→ 走**直接改 gem + `# PALLAS-CUSTOM:` 标记**（AGENTS.md §1：本仓 gem 是自研团队产品，不复制到 Host App，禁用 AP-008）。**不新建表**：配置沿用 `metadata`（与 D8/D11/D16 同范式，零迁移） |
| `ai/skills/pallastrade-payments/SKILL.md` | ✅ 已读 | 分层 `PaymentMethod → Payment → source`；「A PaymentMethod is configured in the admin (Settings → Payments)」；`type` 为稳定简写（`stripe`/`adyen`/`paypal_checkout`）；`PaymentSession` 五事件；**`PaymentCombination` / `PaymentSplit` 数据层（P1）+ 服务层（P4）已存在**（组合支付不需新建模型，只需配置面与编排）→ 本切片与资金链路零交集 |
| `ai/skills/harness-prd/SKILL.md` | ✅ 已读 | 一句话需求 → PRD（已建档 `PRD-20260920-checkout-…`）→ 用户确认（「实施吧」）→ gate → 实施 → AC↔测试映射 → 知识同步 → 收尾；本改动 > 5 文件且含逻辑变更 → REQ 走完整版（本文件） |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读（历次会话结论沿用） | 后台 = Rails engine（ERB + Stimulus + Turbo + Tailwind）；视图必须 `content_for(:page_title)`、`data-testid` 作测试锚点；**改 `app/javascript/**` 必须重启容器**（本次不加 JS）；样式走语义 token（禁硬编码色，AP-006） |
| `ai/skills/pallastrade-i18n/SKILL.md` | ✅ 已读（口径沿用） | 新增 key 必须 en ↔ zh-CN **双向键集相等**；gem `config/locales/en.yml` + `backend/config/locales/admin_payment_methods.zh-CN.yml`；改 locale 后**必须重启容器**才生效 |

**按需 Skill：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `ai/skills/pallastrade-testing/SKILL.md` | ✅ 涉及 | ⏭️ 未读（口径沿用既有 spec 范式） | RSpec + FactoryBot（禁 `Model.create`）+ Capybara；后台请求规格用 `sign_in` + Nokogiri scoped selectors（本仓无 `spec/system`） |
| `ai/skills/pallastrade-security/SKILL.md` | ✅ 涉及（凭证/权限） | ⏭️ 未读（不必要） | 本切片**不新增参数、不改权限模型、不读明文凭据**（诊断卡只读 `payment_option_catalog` 与方法返回的布尔/枚举） |
| `ai/skills/pallastrade-data-model/SKILL.md` | ❌ 不涉及 | — | 无迁移、无新表、无列变更（配置存 `metadata`，`update_columns` 写入） |
| `ai/skills/pallastrade-api-v3/SKILL.md` | ❌ 不涉及 | — | 零契约变化（不新增端点/字段）→ `generated:check` 无需重跑 |

## 需求标题

支付核心统一 · **P0-A 厂商层地基**：厂商能力声明 + 账户配置 + 「能力 ∩ 账户 ∩ 市场」收窄校验 + 三态统一 + 后台只读配置诊断卡。

## 任务类型

新功能（core 服务层 + 模型读取方法 + admin 只读视图）；无 DB 迁移、无 API 契约变更、无依赖变更。

## 需求描述

PRD（v10 方案）P0 切片的第一部分。用户诉求原文（要点）：*「可以接入支付厂商…开关启动支付厂商激活情况；选中支付厂商，可以看到在支付厂商启用的各种支付方式…可以开关启用；支付厂商和关联的支付方式可以配置生效的 market、国家」*；并明确 *「我就预接 stripe、adyen、PayPal 三家作为厂商，交付后客户自行再接是客户的事」*。

现状（Step 0）：厂商 = `PaymentMethod` 记录（STI），入口 = `metadata['options']`，能力 = `payment_option_catalog`。**缺口**：

1. 后台表单**静默丢弃**非法 kind 与越界 scope 值 → 运营以为已生效，实际未落库（**错配不可见**）；
2. 没有"**账户**"这一层：PSP 侧"这个账户开通了哪些方式/币种/国家"无处记录，与"能力支持"混淆；
3. 没有静态能力声明（国家 / 币种 / 金额区间 / 结算 / 幂等），无法做"能力 ∩ 账户 ∩ 市场"三方收窄；
4. 三态散落：`active`（人工）+ `breaker`（半自动）无统一读取口径，页面上看不出"这家厂商现在到底能不能用、为什么"。

本切片交付（零资金副作用、零迁移、零契约变更）：

1. **`Providers::Config`**（读模型）：归一 provider 的 **能力声明**（类方法 `provider_capabilities` 优先，缺省从 `payment_option_catalog` + `session_required?` 推导）+ **账户配置**（`metadata['account']`，含 `source` = `manual`/`synced` 与 `synced_at`）+ 二者与**市场**的交集，全部只读、非法结构忽略不 raise。
2. **`Providers::State`**（三态）：`enabled` / `disabled` / `suspended` 统一读取 + `disable!` / `enable!` / `suspend!` / `resume!` 写入原语（**手动停用粘连、不被自动恢复**；全部经 `update_columns` 只写 `metadata`）。
3. **`Providers::Validate`**（收窄校验）：返回结构化诊断（`severity` + `code` + `message` + 受影响 kind），覆盖：能力未声明的 kind、账户未开通的 kind、市场外配置、币种未开通、金额区间越界、能力声明与账户冲突、三态不一致等；**只读、不写库、不阻断**（写路径行为保持现状，避免破坏 D1/D8/D9/D11 既有 spec）。
4. **模型读取方法**（`PallasTrade::PaymentMethod`，`# PALLAS-CUSTOM:` 标记）：`provider_capabilities`（默认推导）、`provider_account_config`、`provider_state`。
5. **后台只读诊断卡**：`payment_methods` 编辑页新增「厂商配置诊断」卡（`data-testid="provider-diagnostics"`），逐行展示三态、能力/账户来源、收窄结论与诊断项；无诊断项时显示"配置一致"。
6. **i18n**：en ↔ zh-CN 双向键集相等（gem `en.yml` + `backend/config/locales/admin_payment_methods.zh-CN.yml`）。

**明确不做（P0-B / 后续切片）**：写路径强制拒绝（改 `merge_payment_options_into` 的静默丢弃语义）、账户配置的编辑表单与 PSP 同步作业、组合策略配置、付款期限配置、路由（P3）、前台渲染（P1）。

## Step 2：用户确认

用户于 2026-09-20 回复 **「实施吧」**（对 PRD-20260920-checkout 支付核心统一完整方案的显式肯定）→ `user-confirmed` 依据成立。

## 验收标准（AC）

| AC | 判定条件 | 验证方式 |
|---|---|---|
| AC-1 | `Providers::Config.capability` 对声明了 `provider_capabilities` 的 provider 取其值；未声明者从 `payment_option_catalog` + `session_required?` 推导（kind 集合与 catalog 一致） | 服务 spec |
| AC-2 | `Providers::Config.account_config` 读 `metadata['account']`；缺失/非法 → `source == 'manual'` 且空集合（**不猜**，不回落成"全部已开通"） | 服务 spec |
| AC-3 | `Providers::Validate` 对「能力未声明的 kind」「账户未开通的 kind」「市场外 kind」「币种未开通」分别产出对应 `code` 的诊断项，且**不发任何写请求**（metadata 与 updated_at 不变） | 服务 spec |
| AC-4 | 诊断项集合与 provider 实际配置一致：无错配时 `ok?` 为 true 且 `issues` 为空 | 服务 spec |
| AC-5 | `Providers::State` 三态：`active=false` → `disabled`；breaker 生效（含 `manual: true` 粘连）→ `suspended`；否则 `enabled`；`disable!` 后 `resume!` **不得**恢复为 enabled（粘连） | 服务 spec |
| AC-6 | 三态与诊断写入**零资金副作用**：不新增/修改 `Payment` / `PaymentSession` / 账本记录（前后计数相等） | 服务 spec |
| AC-7 | 编辑页渲染 `[data-testid="provider-diagnostics"]` 卡：含三态徽标 + 收窄结论行 + 诊断项（i18n 文案，非硬编码英文） | 请求 spec |
| AC-8 | en ↔ zh-CN 双向键集相等（新增 key 两侧齐备） | `harness verify admin-i18n-rspec` |
| AC-9 | 零契约变化：无新增路由/序列化字段（`generated:check` 无需变化） | 人工 + `harness generated:check` 不涉及 |

## 技术影响

- **新增**：`pallastrade_core/app/services/pallastrade/payments/providers/{config,state,validate}.rb`；`pallastrade_admin/app/views/pallastrade/admin/payment_methods/_provider_diagnostics.html.erb`；helper 方法 `provider_diagnostic_rows`；spec 两枚（服务 + 请求）。
- **修改**：`pallastrade_core/app/models/pallastrade/payment_method.rb`（3 个读取方法，`# PALLAS-CUSTOM:`）；`pallastrade_admin/.../payment_methods/_form.html.erb`（渲染 1 行）；`helpers/.../payments_helper.rb`（1 个方法）；locale 2 文件；`harness.config.mjs`（新增 `payment-providers-rspec` verifier）；`AGENTS.md §6`；`ai/skills/pallastrade-payments/SKILL.md`；`harness/scenarios/scenarios.json`。
- **不动**：写路径（controller 归一）、`Availability::*`、`CircuitBreaker`、`ThreeDSecure`、账本/对账、API 契约、前台。

## 测试计划

| 层 | 命令 | 覆盖 |
|---|---|---|
| 服务 | `spec/services/pallastrade/payments/providers/config_spec.rb` | AC-1/AC-2 |
| 服务 | `spec/services/pallastrade/payments/providers/validate_spec.rb` | AC-3/AC-4/AC-6 |
| 服务 | `spec/services/pallastrade/payments/providers/state_spec.rb` | AC-5 |
| 请求 | `spec/requests/pallastrade/admin/payment_provider_diagnostics_spec.rb` | AC-7 |
| verifier | `harness verify payment-providers-rspec`（新注册，含上述 4 枚） | AC-1..AC-7 |
| i18n | `harness verify admin-i18n-rspec` | AC-8 |

## 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-20 | 1.0 | 初稿：P0-A 厂商层地基（能力声明 / 账户配置 / 收窄校验 / 三态 / 诊断卡），AC-1..AC-9 | AI |
