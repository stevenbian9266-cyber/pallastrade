# REQ-20260920-s1 — Stripe 厂商详情页定向优化（连接区上移、删空配置指南与路由预览卡）

- **类型**：feature（优化迭代，S1；PRD `PRD-20260915-admin-管理后台支付配置选项化…` §1.1 / FR-010..014）
- **Task**：`TASK-20260920144658-1779a32f`
- **Gate**：`GATE-2026-09-20T14-47-06`
- **风险**：critical（改动落 `backend/pallastrade_gems/pallastrade_admin/**` 框架视图 + Stripe/Core gem）
- **上游**：S0 `caab77f7`（同页嵌套表单修复）先行交付（bugfix，已含 `# PALLAS-CUSTOM: S0` 标记）
- **不触碰**：路由（无新路由）、OpenAPI/SDK 契约、DB schema、`Payments::Routing::*` 引擎、`PaymentSessions::Start`、`Providers::{Config,State,Validate,Account}`、`platform/payments/**` 副本

## 1. 问题（代码事实）

进入「设置 → 支付方式 → Stripe」编辑页，看到的是：

| 位置 | 内容 | 问题 |
|---|---|---|
| 页首 | 「厂商诊断卡」（P0-A 只读 6 行 + P0-B **账户配置手填表单** + P3-C 路由预览） | 「厂商事实」抢占首屏；账户手填与「本店开关」概念打架（账户事实将由 S3 从 Stripe 同步） |
| 页中 | 凭证（Stripe key）/ 显示设置 | **真正的第一步（配 key）被压到中下部** |
| 页中下 | 「支付方式」卡 | 卡头才挂 `[测试连接]` 按钮、卡尾才显示上次结果 —— **离凭证太远** |
| 底部 | 凭据健康 / Webhook / 熔断 | —— |
| 顶部 | **空的** Stripe 配置指南（partial **0 字节**） | 死重 |
| 诊断卡内 | P3-C 路由预览 | 回答的是「**多厂商之间**谁承接」，不属于「单厂商配置」页；且其结论只在订单上下文才有意义（`order_gates: 'skipped'`） |

## 2. Step 0 六层跨层搜索（R4）

| 层 | 路径 | 关键词 | 结果 | 修改层 |
|---|---|---|---|---|
| **App** | `backend/app/` | `provider_page`/`test_connection`/`payment_methods` | 仅生成的 TS 类型，无业务实现 | ❌ |
| **Core** | `pallastrade_core/app/` | `method_type`/`last_test_connection`/`TestConnection` | `PaymentMethod#method_type`(L272)、`Gateway#method_type`(L74)、`PaymentMethods::TestConnection`（只读、不落库）；**无「厂商页面分派」机制** | ⚠️ 新增 1 个基类方法 |
| **API** | `pallastrade_api/app/` | `payment_option`/`entries` | admin/store 序列化读模型，与后台表单无关 | ❌ |
| **Admin** | `pallastrade_admin/app/` | 同上 | **唯一实现层**：`edit`/`_form`/`_options`/`_provider_diagnostics`/`_breaker`/`_credentials` + `payments_helper` | ✅ |
| **Storefront** | `storefront/src/` | 同上 | 无（后台专属概念） | ❌ |
| **Platform** | `platform/packages/` | 同上 | 无（SDK 不涉后台页面） | ❌ |

**同层事实核验（决定删除面）**：
- 三个 provider 的配置指南实际字节：**Stripe `0`**（死重）、Adyen `556`、PayPal `436` → 删除面**仅限 Stripe**。
- `PaymentsHelper#provider_routing_preview` 消费者**唯一**（`_provider_diagnostics.html.erb:68`）→ 可安全移除。
- `[测试连接]` 按钮与结果目前都在 **共享 partial** `_options.html.erb`（L12 / L103）→ Stripe 定向迁移**必须保留非 Stripe 分支**。
- **既有分派先例**：`payments/new.html.erb:40` 已用 `source_forms/#{method_type}` 按 provider 选 partial。

## 3. Skill 咨询表（R2）

| Skill | 读取位置 | 结论 |
|---|---|---|
| `pallastrade-customization`（gate 强制 always） | `ai/skills/pallastrade-customization/SKILL.md` | 决策树对「给已有后台页加区块」推荐注入 API `PallasTrade.admin.partials.<page> << ...`。**本项目不采用**，理由：① AGENTS.md §3 对 **Admin 视图**明确采用「直接改 gem 源 + `# PALLAS-CUSTOM:`」（本仓既有 D 系列全部如此）；② 注入 API **只能加不能删**，而本切片核心动作是**删除**（空指南 / 路由预览卡）；③ 本切片改的是**版面分派**而非注入区块。→ 记录为「已评估，采用直改范式」 |
| `pallastrade-admin` §419/§588（D1/D8） | `ai/skills/pallastrade-admin/SKILL.md` | 约定：`_options` 挂在主表单内、**勿再嵌套 `<form>`**；动作走 **Turbo 栈约定**（`link_to + data: { turbo_method: :post }`）或 `button_to`（后台无 rails-ujs）；`test_connection` 文案键与 `metadata['last_test_connection']` 形态；D8 范围编辑随主表单提交（本切片不动） |
| `pallastrade-admin` §1061（Design tokens & density，B6-1） | 同上 | **样式规范唯一权威**：token 定义在 gem `base/_theme.css`；**组件层禁止直引 Tailwind 调色板**（主色/语义走 token）；密度 `data-admin-density`；改样式后须重建 CSS 并 `docker restart` 才行；守护 `admin-theme-rspec` |
| `pallastrade-admin` §D12（Webhook console） | 同上 | 「后台**无 rails-ujs**，`link_to method:` 无效」→ 页内动作一律 `button_to` / Turbo 栈 |
| `pallastrade-payments` §177（厂商层 P0-A/P0-B） | `ai/skills/pallastrade-payments/SKILL.md` | 诊断卡只读、账户配置表单是唯一写入口；P3-C 路由预览是**只读展示面**（引擎 `Routing::{Decide,Policy,Summary}` 与本页解耦）→ 移除展示面不动引擎 |
| `pallastrade-i18n` | `ai/skills/pallastrade-i18n/SKILL.md` | en ↔ zh-CN **双向键集相等**（CI 有覆盖率校验）；YAML 1.1 把未加引号的 `off`/`on`/`yes`/`no` 当布尔 → 此类键必须加引号 |
| `harness-prd`（gate 强制） | `ai/skills/harness-prd/SKILL.md` | 一句话需求 → 查重 → **命中即回写**（本次命中 33%，已 `prd update` 回写）→ 用户确认 → gate → REQ → 实施 |

## 4. 验收标准（AC）与测试映射

| AC | ← FR | 内容 | 映射测试 |
|---|---|---|---|
| AC-009 | FR-010 | Stripe 详情页渲染**专用版面**；Adyen/PayPal/Check 仍渲染默认版面（默认特征区块仍在） | `payment_methods_spec.rb`（扩展） |
| AC-010 | FR-011 | Stripe 页**首卡**含 `preferred_publishable_key`/`preferred_secret_key` + `[测试连接]` + 最近结果；非 Stripe 页按钮/结果**仍在 `_options` 卡** | 同上 |
| AC-011 | FR-012 | Stripe 页不渲染配置指南且 `configuration_guides/_pallastrade_stripe.html.erb` **文件不存在**；Adyen/PayPal 指南仍渲染 | 同上 |
| AC-012 | FR-013 | 任何 provider 编辑页均**不再**出现 `[data-testid="provider-routing-preview"]`；`payment-routing-rspec` 全绿 | `payment_provider_diagnostics_spec.rb`（扩展） + 验证器 |
| AC-013 | FR-014 | 熔断卡仍含 `#payment_method_breaker` + 指标 + 软置灰/解除动作（仅外层可折叠） | `d11_payment_method_soft_disable_spec.rb` + 验证器 |
| AC-014 | 全部 | 样式/文案守护全绿 | `admin-theme-rspec`、`admin-i18n-rspec`、`admin-payment-methods-rspec` |

## 5. 决策记录

| 决策 | 取舍 |
|---|---|
| **分派钩子用 provider 声明式方法**（`provider_page_partial_name`，基类 `nil`） | ✅ 与既有 `description_partial_name`/`custom_form_fields_partial_name`/`configuration_guide_partial_name` 同范式；默认 `nil` = 零回归。❌ 不采用「按 `method_type` 猜 partial 名 + `lookup_context.exists?`」——隐式、易在重命名时静默回落 |
| **不改路由**（仍走 `edit`） | ✅ 保住面包屑/权限/跳转链路；「点 Stripe 进详情页」本就走 `edit`。❌ 不新增 `/provider` 路由（会引入重复授权与导航口径） |
| **非 Stripe 版面逐字保留** | ✅ 零回归可验证（同一 partial 集合）。代价：`edit.html.erb` 出现一个分派分支（可接受，属既有范式） |
| **测试落在既有 spec 文件内** | ✅ 不新增验证器 id → **不动 `harness.config.mjs`**（避开与并行会话争抢共享文件） |
| **删 P3-C 展示面但保留引擎** | ✅ 用户明确要求删；引擎已被 P3-A/B 交付且有独立验证器。PRD §7.1 显式记录「移除的是后台展示面」 |

## 6. 残留与后续

- **S2**：方式列表按「Stripe 账户事实 ∩ 本地能力」四象限渲染 + 去范围编辑 UI + 存量 `optionized` 回填。
- **S3**：从 Stripe 同步已启用方式（`metadata['account']` 的 `source`/`synced_at` 已预留）+ `test_connection` 真实远端探测。
- **另案**：`platform/payments/pallastrade_stripe` 的 `developerTools` 漂移（backend 份缺失）。
