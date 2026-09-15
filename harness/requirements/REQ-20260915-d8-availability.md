# REQ-20260915-d8-availability

> 关联 PRD：`docs/prd/payments/PRD-20260915-payments-d8-支付适用范围引擎-支付商-支付方式-市场-国家-zone-币种-前台入口过滤.md`（用户 2026-09-15 回复「实施」→ approved）
> 业务依据：`豆包梳理业务需求/商城前台 Checkout + Transaction + Promotion + 履约完整方案.md` §65.1（四层模型）、§66（适用范围引擎：14 维度 / 规则语义 / 解析链路 / 同源硬约束）、§74（过渡期不建表）、§75.2（页面 5）、§76.1/§76.4（前台契约与错误码）
> 本次实施范围：**切片 1（core：规则模型 + Resolver + 投影/Start 接入）** 与 **切片 2（admin：范围编辑器 + admin 投影）**；其余 10 维度、路由/熔断、模拟器、落表不在本期。

## Step 0：跨层搜索（6 层）

| 层 | 搜索路径 | 关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | payment_method / available_for | 无业务实现（仅生成类型 `app/javascript/types/serializers/*`） | ❌ 无（本 PRD 不改 App 层） |
| Core | `pallastrade_gems/pallastrade_core/app/` | `available_for_order?` / `frontend_visible?` / `collect_frontend_payment_methods` / market / zone / currency | `models/pallastrade/order.rb`（`:913` `payment_methods`、`:1233` `collect_backend_payment_methods`、`:1237` `collect_frontend_payment_methods`）、`models/pallastrade/payment_method.rb`（D1 入口 API：`payment_options` / `effective_payment_options` / `frontend_visible?`）、`models/pallastrade/market.rb`（store 作用域 + `countries` + `currency` + `tax_zone` + `Market.for_country`）、`models/pallastrade/zone.rb`（`self.match` / `include?` / `zone_members`）、`models/pallastrade/promotion/rules/{market,country,currency}.rb`（规则类 + prefixed ID 归一 + store 作用域先例）、`services/pallastrade/payment_sessions/start.rb`（建会话同源点） | ⚠️ 上下文来源与规则先例齐备；**缺** Option 级规则模型与求值器 |
| API | `pallastrade_gems/pallastrade_api/app/` | market / currency / payment_methods / checkout | `controllers/concerns/.../locale_and_currency.rb`（`x-pallastrade-country` → `PallasTrade::Current.market`；locale/currency 头）、`serializers/.../store/checkout/checkout_serializer.rb#payment_method_payload`（D1 切片2）、`serializers/.../admin/payment_method_serializer.rb`（D1：`optionized` / `options`） | ⚠️ 上下文已备；需补 admin `options[].rule_set` 投影与 `payment_option_not_available` 错误码 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | payment_methods / markets | `controllers/.../payment_methods_controller.rb`（D1 切片3 写入口 + `test_connection`）、`views/.../payment_methods/_options.html.erb`（页签）、`controllers/.../markets_controller.rb`（多选 UI 先例） | ⚠️ 页签载体与写入口模式已备；**缺**范围编辑器与摘要 |
| Storefront | `storefront/src/` | market / country / payment list | `lib/pallastrade/locale.ts`（`pallastrade_country` cookie）、`lib/pallastrade/middleware.ts`、`app/[country]/[locale]/…`（路由已含国家）、`lib/data/checkout.ts#updateCartMarket`、`components/checkout/UnifiedCheckout.tsx` | ⚠️ 上下文与路由已备；本期**不改渲染**，仅消费新错误码 |
| Platform | `platform/packages/` | PaymentMethod / Market types | SDK 生成类型 `PaymentMethod`（`kind` / `frontend_kind`）、admin SDK `AdminPaymentMethod`（`optionized` / `options`） | ⚠️ 需 additive 扩 `options[].rule_set`（仅 admin），store 侧不变 |

### 搜索结论

入口模型（D1）与全部上下文来源（Market / Zone / currency 头 / country cookie / 路由）已具备；
本 PRD **只新增**：Option 级 `rule_set` 规则模型 + core Resolver（单一求值点）+ Order 三处投影接入 + `PaymentSessions::Start` 同源复算 + 后台范围编辑器。不建表、不改 provider 结构、不改前台渲染编排（§76.2 后续）。

---

## Step 1：Skill 文件咨询

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树：本改动属「改既有框架模型 + 新增 core 服务」→ 按仓库约定直接改 gem 源码并加 `# PALLAS-CUSTOM:` 注释（优先级 8，与 D1 一致）；additive 优先 |
| `ai/skills/pallastrade-payments/SKILL.md` | ✅ 已读 | `display_on` 是现行可见性开关；`PaymentSession` 恒建（§0.1-6）；建会话与前台列表必须同源（防「选得上、付不了」）→ 本切片在 `PaymentSessions::Start` 复算，错误码进 `§61.4` 体系 |
| `ai/skills/pallastrade-data-model/SKILL.md` | ✅ 已读 | `metadata` = `private_metadata` 别名（write-only，Stripe 式）；过渡期不建表，入口与规则均落 `metadata['options']`（业务方案 §74）；只读归一必须忽略非法条目 |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | D1 切片3 的「支付方式」页签写入口模式（`payment_method[payment_options][<kind>][...]` 归一 + 目录白名单 + `optionized` 翻转规则）；Turbo 栈约定（`data-turbo-method`）；表单内勿嵌套 `<form>` |
| `ai/skills/pallastrade-api-v3/SKILL.md` | ✅ 已读 | 序列化 additive 契约 + `scripts/ci/contracts.sh` 再生成（Windows 需 Git bash 手跑）；错误响应形态（`{error: {code, message}}` 由 error handler 统一） |
| `ai/skills/pallastrade-testing/SKILL.md` | ✅ 已读 | RSpec：`@default_store`、FactoryBot、请求规格 sign_in 超管模式；测试库店铺 code 必须随机（避免 `pallastrade_N` 残留冲突） |
| `ai/skills/pallastrade-prd/SKILL.md` | ✅ 已读 | §5：每个 AC 必须有测试（同 PRD-ID + AC 号同行标记）；收口走 `prd verify` + `prd-status-sync` |

---

## 需求标题

需求：D8 支付适用范围引擎（支付商/支付方式 × 市场/国家/Zone/币种 → 前台入口过滤）

## 任务类型

新功能（框架扩展，additive；零回归硬约束）

## 设计要点（实施基线）

1. **规则存储**：`metadata['options'][i]['rule_set'] = { 'match' => 'all'|'any', 'include' => [cond], 'exclude' => [cond] }`，
   `cond = { 'dimension' => 'market'|'country'|'zone'|'currency', 'operator' => 'in'|'not_in'|'eq', 'values' => [...] }`。
   **写入时归一到 raw**：market/zone 存 raw id（字符串），country 存 ISO2（大写），currency 存 ISO 大写（与促销规则先例一致，求值零解码）。
2. **求值语义**：`exclude` 命中即排除（否定优先）；`include` 空 = 不限；`match: all`（默认）要求全部命中 / `any` 至少一条；
   **无规则 = 全局可用**；未知维度/算子/空 values 的条目一律忽略（不 raise）。
3. **未知上下文语义**：`include` 条件遇到未知上下文（如地址未填 → country 未知）→ 视为**未命中**（fail closed）；
   `exclude` 条件遇到未知上下文 → 视为**未命中**（fail open，排除必须有正证据）。
4. **单一求值点**：`PallasTrade::Payments::Availability::{Context, Evaluator, Resolver}`（core services）。
   `Order#payment_methods` / `collect_frontend_payment_methods` / `collect_backend_payment_methods` 经 `Resolver.available_providers(order:, scope:)` 过滤（保持返回类型与既有排序）。
5. **同源硬约束**：`PaymentSessions::Start#payment_method_available?` 复算（provider 级 + `option_kind` 级），
   被排除 → `failure(order, { code: 'payment_option_not_available', message: ... })`（不建 PaymentSession）。
6. **后台（切片2）**：`_options.html.erb` 每行加范围编辑（market/country/zone/currency 多选，默认「不限」）+ 摘要；
   控制器归一 `payment_method[payment_options][<kind>][rule_set][dimension][values][]` →
   prefixed ID（`mkt_`/`zone_`）解码 + 当前 store 作用域校验 → raw；国家/币种做白名单存在性校验。
7. **admin 投影（切片2）**：`Admin::PaymentMethodSerializer#options[]` 增 `rule_set`（typelize → 契约再生成）。

## 实现载体（新文件 justification）

| 文件 | 类型 | 说明 |
|---|---|---|
| `pallastrade_core/app/services/pallastrade/payments/availability/context.rb` | 新增 | 求值上下文（market/country/zone/currency/order）；无既有对应物 |
| `pallastrade_core/app/services/pallastrade/payments/availability/evaluator.rb` | 新增 | 纯函数求值器（rule_set × context → 命中/原因） |
| `pallastrade_core/app/services/pallastrade/payments/availability/resolver.rb` | 新增 | 单一求值点（provider/option 级可用性 + 排除原因） |
| `backend/spec/services/pallastrade/payments/availability/resolver_spec.rb` | 新增 | AC-001/002/003/008 覆盖 |
| 其余改动均为**既有文件扩展**（`payment_method.rb` / `order.rb` / `start.rb` / admin 控制器与视图 / serializer / start_spec / payment_method_options_spec / admin request spec） | 改 | — |

## 用户确认

用户于 2026-09-15 会话内回复「**实施**」→ PRD 置 approved，授权按本 REQ 实施切片 1/2（R3/R7）。

---

# 切片 1：core 规则模型 + Resolver + 投影/Start 接入

## 交付物

1. `PaymentMethod` 增规则读取 API：`payment_option_rule_set(kind)`（归一，非法忽略）、`payment_option_scope_summary(kind)`（后台摘要，如 `"EU · EUR"` / `"全部"`）。
2. `Payments::Availability::{Context,Evaluator,Resolver}` 三个服务（见设计要点 2/3/4）。
3. `Order` 三处投影接入 Resolver（`payment_methods` / `collect_backend_payment_methods` / `collect_frontend_payment_methods`）。
4. `PaymentSessions::Start` 复算 + `payment_option_not_available` 错误码。
5. RSpec：`resolver_spec.rb`（4 维度 × include/exclude × 无规则 × 能力收窄）、`payment_method_options_spec.rb` 扩展（规则归一）、`start_spec.rb` 扩展（拒绝 + 未建会话）。

## 本切片不做

- admin 范围编辑器（切片 2）、storefront 文案、其余 10 维度、路由/熔断、模拟器、落表。

---

# 切片 2：admin 范围编辑器 + admin 投影 + 契约再生成

## 交付物

1. `_options.html.erb` 每行加「适用范围」：4 组多选（市场 / 国家 / Zone / 币种）+ 摘要列；「不限」为默认（空规则）。
2. `payment_methods_controller` 归一 `rule_set` 参数（prefixed ID 解码 + store 作用域 + 国家/币种白名单 + 维度/算子白名单）。
3. `Admin::PaymentMethodSerializer#options[]` 增 `rule_set`；`scripts/ci/contracts.sh` 再生成 OpenAPI + SDK 类型。
4. RSpec：admin request spec 扩展（保存/摘要/未知维度忽略/跨店 id 拒绝）。
5. i18n：gem `en.yml` + 宿主 `zh-CN`。

## 收口（两切片共用）

- 注册验证器 `d8-availability-rspec`（`harness.config.mjs`）+ `AGENTS.md` §6 行；
- 知识同步：`pallastrade-payments` / `pallastrade-admin` / `pallastrade-api-v3` / `pallastrade-data-model` Skill、业务方案 §66 状态回写、`harness/scenarios/scenarios.json` 新场景、PRD changelog/§9、README 索引；
- `prd verify`（AC↔测试标记同行）、`doc-impact`、`sync-check --ack`。

---

# 实施记录（2026-09-15，切片 1+2 完成）

## 关键决策（含实施中的偏差）

1. **摘要 i18n**：维度名与「全部 / 排除」文案走 `I18n.t('pallastrade.payment_option_dimensions.*')` / `payment_option_scope_all|exclude`（gem `en.yml` + 宿主 `zh-CN` 均登记）——核心层不硬编码中文。
2. **摘要默认 labels**：`payment_option_scope_summary(kind)` 默认把 market/zone 原始 ID 解析成记录名（`default_option_scope_labels`），显式传 `labels:` 可覆盖；后台列与 admin API 共用同一份。
3. **「范围区已提交」标记**：表单加隐藏位 `[rule_set][present]=1`——否则「全空选择 = 清空规则」与「未提交该区（列表页行内编辑）」无法区分，后者必须保留既有规则。
4. **`exclude` 只读保留**：v1 后台只编辑 include；提交时既有 `exclude` 条件原样保留（摘要列可见）。
5. **币种白名单语义**：`store.supported_currencies_list` 在店铺**有 market 时按市场币种推导**（实施中实测：建 market 后 EUR 可能不在白名单）→ 规格断言取店铺实际支持币种，不写死货币码；国家维度用 `Country.exists?(iso:)`，规格自建国家避免依赖测试库种子。
6. **入口 kind 校验复用 D1 目录**：不在 capability 目录内的 kind 依旧忽略（防注入）。

## 验证（本地）

- `d8-availability-rspec`（4 文件）：**73 例 0 失败**（resolver 4 维度 / exclude 优先 / 能力收窄 + order 投影 + start 门禁 + admin 范围编辑 / 投影 / 摘要）。
- `harness eval-ai --scenarios`：131/131 valid（GS-130）。
- `node scripts/ci/prd-status-sync.mjs --check`：143 份文件 / 143 行索引一致。
- 契约再生成：`scripts/ci/contracts.sh`（admin SDK `PaymentMethod.options[]` 增 `rule_set`/`scope_summary`；两份 OpenAPI 可解析）。

## 变更文件（提交范围）

| 类别 | 文件 |
|---|---|
| Core | `payments/availability/{rule_set,context,evaluator,resolver}.rb`（新增）、`payment_method.rb`、`order.rb`、`payment_sessions/start.rb` |
| Admin | `payment_methods_controller.rb`、`payments_helper.rb`、`_options.html.erb`、宿主 `admin_payment_methods.zh-CN.yml`、gem `en.yml` |
| API | `admin/payment_method_serializer.rb`、`public/api-docs/store.yaml`（+ platform 副本）、admin SDK 生成类型 |
| Spec | `payments/availability/resolver_spec.rb`（新增）、`payment_method_options_spec.rb`、`payment_sessions/start_spec.rb`、`admin/payment_methods_spec.rb` |
| 治理 | `harness.config.mjs`（verifier `d8-availability-rspec`）、`AGENTS.md` §6、`harness/scenarios/scenarios.json`（GS-130）、5 个 Skill、业务方案 §61.4/§63.5/§66、PRD + 本 REQ |
