# PRD-20260915-payments-d8-支付适用范围引擎

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-15 |
| 来源 | 需求：D8 支付适用范围引擎（支付商/支付方式 × 市场/国家/Zone/币种 → 前台入口过滤） |
| 分类 | payments（自动判定，关键词命中 1） |
| 关联 Skill | `pallastrade-payments`、`pallastrade-admin`、`pallastrade-api-v3`、`pallastrade-data-model`、`pallastrade-testing` |
| 关联 REQ | `harness/requirements/REQ-20260915-d8-availability.md` |
| 关联 PRD | `PRD-20260915-admin-管理后台支付配置选项化-支付商-支付方式-前台入口`（D1：提供「入口（Option）」模型与门控；本 PRD 在其上加「适用范围」层）；设计依据：业务方案 §65（四层模型）/ §66（适用范围引擎） |
| 需求类型 | 新功能 |
| 业务依据 | `豆包梳理业务需求/商城前台 Checkout + Transaction + Promotion + 履约完整方案.md` §65.1（四层：Provider → Method → Option → AvailabilityRule）、§66（14 维度 / 规则语义 / 解析链路 / 同源硬约束）、§74（过渡期不建表）、§75.2（页面 5：Option 编辑·范围）、§76.1/§76.4（前台契约与错误码） |

## 1. 背景与目标

- **一句话需求原文**：D8 支付适用范围引擎（支付商/支付方式 × 市场/国家/Zone/币种 → 前台入口过滤）。
- **背景（代码事实）**：
  - D1 已把「支付商 × 支付方式 → 前台入口」落地为 `PaymentMethod` 上的选项化入口（`metadata['options']` + `optionized` 门控，切片1–3 已上线 `b884b0a0` → `1535d3f2`），后台可按 method 启停/命名/排序，核心门控 `frontend_visible?` 与 `PaymentSessions::Start` 同源校验已就位。
  - 但入口**没有「适用范围」**：`Order#collect_frontend_payment_methods` 的过滤条件只有 `store + active + display_on + available_for_order? + frontend_visible?`（`order.rb:1237`），与市场/国家/Zone/币种无关 —— 今天无法表达「Klarna 只在 EU 市场 + EUR」「iDEAL 不对 US 开放」。
  - 业务方案 §65.1 明确：「能收哪些国家/市场/Zone」是 **Option 的属性**，不是 provider 的；§66 给出 14 个维度与 `rule_set` 语义，§66.5 要求前台列表与建会话**同一份求值**。
  - 现有可复用件：`PallasTrade::Market`（store 作用域 + `countries` + `currency` + `tax_zone`，`Market.for_country`）、`PallasTrade::Zone.match/include?`（国家/州成员）、API v3 `x-pallastrade-country` → `PallasTrade::Current.market`（`locale_and_currency.rb`）、以及促销/价格规则中的「规则类 + prefixed ID 归一 + 作用域存在性校验」先例（`Promotion::Rules::{Market,Country,Currency}`、`PriceRules::*`）。
- **目标**：给每个入口（Option）加一层**服务端权威**的适用范围规则（首版 4 维度：market / country / zone / currency），商家在后台配置即生效；前台列表与建会话使用同一求值结果；无规则 = 全局可用（零回归）。
- **成功指标**：
  1. 配置「Klarna 仅 EU 市场 + EUR」后，US 用户/IP 或 USD 报价下**看不到**该入口，EU+EUR 下可见（无需发版/重启）；
  2. 前端绕过列表直接建会话 → `422 payment_option_not_available`，**不产生** PaymentSession；
  3. 未配置规则的 provider（含未选项化）行为与今天**逐字节一致**（回归 spec 断言）。

## 2. 用户故事 / 场景

- 作为**运营**，我希望把某个支付方式限定在特定市场/币种，以便合规且不给用户展示用不了的支付方式。
- 作为**运营**，我希望把某入口从"某国家"排除（如美国不显示 iDEAL），以便减少失败支付与客服。
- 作为**客服/开发**，我希望知道"为什么这个入口没出现"（被哪条规则排除），以便快速定位配置问题。
- 场景：
  - 正常：EU 市场 + EUR → 显示 Klarna；切到 US 市场 → 列表即时变化。
  - 边界：无规则 → 全局可用；`include` 命中但 `exclude` 也命中 → **不可用**（否定优先）。
  - 异常：配置漂移（列表已刷新但客户端仍提交旧入口）→ `payment_option_not_available` + 刷新提示。

## 3. 功能需求（FR）

- **FR-001　规则模型（Option 级 `rule_set`）**：每个入口可带 `rule_set` JSON：
  `{ "match": "all"|"any", "include": [条件], "exclude": [条件] }`，条件 = `{ "dimension": <d>, "operator": <op>, "values": [...] }`；
  首版维度 `d ∈ { market, country, zone, currency }`，算子 `op ∈ { in, not_in, eq }`（`eq` 仅 currency）。
- **FR-002　过渡期存储与归一**：`rule_set` 存 `metadata['options'][i]['rule_set']`（沿用 D1 过渡期形态，**不建表**，业务方案 §74）；读取归一：非法条目（未知维度/算子/空 values）一律忽略；`include`/`exclude` 均为空 → 视同**无规则**。
- **FR-003　求值语义**：`exclude` 命中即不可用（否定优先）；`include` 为空视作不限；`match: all`（默认）要求全部 include 条件命中，`any` 要求至少一个；**无规则 = 全局可用**（向后兼容）。
- **FR-004　服务端单一求值点（Resolver）**：新增 core 服务 `PallasTrade::Payments::Availability::Resolver`，输入上下文（market / country / zone / currency / order），输出可用入口 + 被排除入口及原因（`reasons`）；`Order#collect_frontend_payment_methods` / `collect_backend_payment_methods` / `Order#payment_methods` 改为经 Resolver 过滤（保持既有返回类型与排序：provider position → option position）。
- **FR-005　同源硬约束（建会话复算）**：`PaymentSessions::Start` 用**同一 Resolver** 复算；入口不在可用集合 → 拒绝并返回新错误码 `payment_option_not_available`（业务方案 §66.5 / §76.4），**不创建** PaymentSession。前端传入的 option 永不信任。
- **FR-006　后台「适用范围」编辑**：D1 的「支付方式」页签每行增加范围编辑（市场 / 国家 / Zone / 币种 多选，默认「不限」），保存归一写入 `rule_set`（沿用 D1 写入口模式：仅接受已知维度/算子、接受 prefixed ID（`mkt_…`/`ctry_…`/`zone_…`）并解码为 raw id、作用域校验限定当前 store）；行内展示范围摘要（如「EU · EUR」「全部」）。
- **FR-007　零回归**：无 `rule_set` 的入口、未选项化的 provider、`display_on=back_end` 的场景行为不变（含后台录单：后台入口同样受规则约束，但**默认规则为空 = 不限制**）。
- **FR-008　可解释性（首版轻量）**：Resolver 返回被排除项的原因（dimension/条件/命中值）；后台页面展示最近一次保存的范围摘要（完整模拟器/影响预览列后续，见 §9）。
- **FR-009　API 投影（additive）**：admin `PaymentMethodSerializer#options[]` 增加 `rule_set`（管理端可见）；store 侧**不新增字段**（列表已由服务端过滤，客户端无需感知规则）。
- **FR-010　能力目录收窄（可选机制）**：若 provider 能力目录声明 `currencies` / `countries`（`payment_option_catalog` 可选键），则实际可用性 = **Capability ∩ Policy**（商家只能收窄，不得扩宽）；未声明 = 不限制。

## 4. 非功能需求（NFR）

- **性能**：Resolver 不引入 N+1（入口来自 `metadata`，市场/Zone 预载；单订单求值 O(入口数 × 条件数)）；列表接口不得因规则求值增加可见延迟（目标 ≤ 5ms/订单）。
- **安全**：规则只做**收窄**；不得成为越权入口（Start 复算）；prefixed ID 与 store 作用域校验（跨店 market/zone id 拒绝）。
- **兼容**：全套 additive（`rule_set` 缺省 = 无规则）；老客户端字段不变；后台旧保存路径不受影响。
- **可维护性**：维度/算子以常量表声明（新增维度不改求值核心）；非法配置**忽略**而非 500。
- **i18n**：后台新增文案 en + zh-CN（沿用 D1 的 gem en.yml + 宿主 `*.zh-CN.yml` 模式）。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001 ← FR-001/002**：`rule_set` 读写归一 —— 非法维度/算子/空 values 被忽略；空 include+exclude 视同无规则（RSpec: model 单测）。
- **AC-002 ← FR-003**：`exclude` 命中即排除（即使 include 命中）；`match: any` 至少一条命中即通过；无规则 = 可用（RSpec: Resolver 单测）。
- **AC-003 ← FR-004**：4 维度分别在 `collect_frontend_payment_methods` 生效（market / country / zone / currency 各一例 + 组合例）（RSpec: order 投影）。
- **AC-004 ← FR-005**：被排除入口在 `PaymentSessions::Start` 被拒（`payment_option_not_available`）且**未创建** PaymentSession；可用入口照常通过（RSpec: start_spec）。
- **AC-005 ← FR-006**：后台页签保存范围 → `metadata['options'][i]['rule_set']` 持久化；未知维度被忽略；页面显示范围摘要（RSpec: admin request spec）。
- **AC-006 ← FR-007**：无规则 provider / 未选项化 provider / 无 market 上下文（后台录单）行为不变（RSpec: 回归断言）。
- **AC-007 ← FR-008/009**：Resolver 返回排除原因；admin serializer `options[]` 输出 `rule_set`（RSpec: serializer + service）。
- **AC-008 ← FR-010**：目录声明 `currencies` 时，非匹配币种被收窄（Capability ∩ Policy），未声明不受限（RSpec: Resolver）。
- **AC-009 ← 收口**：注册验证器 `d8-availability-rspec` 全绿（`harness.config.mjs`）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | payment_method / available_for | 无业务实现（仅生成类型） | ❌ 无（保持） |
| Core | `pallastrade_gems/pallastrade_core/app/` | `available_for_order?` / `frontend_visible?` / `collect_frontend_payment_methods` / market（market）/ zone / currency | `payment_method.rb`（D1 入口 API + 门控）、`order.rb:913/1233/1237`（前台/后台投影）、`market.rb`（store 作用域 + countries/currency/tax_zone + `Market.for_country`）、`zone.rb`（`match` / `include?` / zone_members）、`promotion/rules/{market,country,currency}.rb` 与 `price_rules/*`（规则类 + prefixed ID 归一先例）、`payment_sessions/start.rb`（建会话同源点） | ⚠️ 有全部**上下文来源**与规则先例；**缺** Option 级规则模型与求值器 |
| API | `pallastrade_gems/pallastrade_api/app/` | market / currency / payment_methods / checkout | `concerns/.../locale_and_currency.rb`（`x-pallastrade-country` → `Current.market`；locale/currency 头）、`store/checkout/checkout_serializer.rb#payment_method_payload`（D1/切片2 投影）、`admin/payment_method_serializer.rb`（D1 切片2/3：`optionized` / `options`） | ⚠️ 上下文已备；需补 admin `rule_set` 投影与 `payment_option_not_available` 错误码贯通 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | payment_methods / markets | `payment_methods_controller.rb`（D1 切片3 写入口 + `test_connection`）、`views/.../payment_methods/_options.html.erb`（页签）、`markets_controller.rb`（市场 CRUD，多选 UI 先例） | ⚠️ 有页签载体与写入口模式；**缺**范围编辑与摘要 |
| Storefront | `storefront/src/` | market / country / payment list | `lib/pallastrade/{locale,middleware}.ts`（country cookie `pallastrade_country`）、`app/[country]/[locale]/…`（路由已含国家）、`lib/data/checkout.ts#updateCartMarket`、`components/checkout/UnifiedCheckout.tsx`（支付列表渲染） | ⚠️ 上下文与路由已备；本期**不改**渲染（服务端已过滤），仅消费 `payment_option_not_available` 错误码（刷新列表） |
| Platform | `platform/packages/` | PaymentMethod / Market types | SDK 生成类型 `PaymentMethod`（D1 切片2/3：`kind` / `frontend_kind`）、admin SDK `AdminPaymentMethod`（`optionized` / `options`） | ⚠️ 类型需 additive 扩展（admin `options[].rule_set`），store 侧不变 |

**结论**：入口模型（D1）与全部上下文来源（Market/Zone/currency 头/cookie/路由）**已具备**；本 PRD 只新增 **Option 级规则模型 + 服务端 Resolver + 建会话复算 + 后台范围编辑**，不建表、不改 provider 结构、不改前台渲染编排（§76.2 属后续）。

## 7. 技术影响

- **Core**：`PaymentMethod` 增 `payment_option_rules_for(kind)` / `payment_option_scope_summary`（读归一）；新增 `app/services/pallastrade/payments/availability/{resolver.rb,context.rb,evaluator.rb}`；`Order` 三处投影接入；`PaymentSessions::Start` 复算 + 错误码。
- **API**：admin `PaymentMethodSerializer#options[]` 增 `rule_set`（typelize → OpenAPI 契约再生成）；错误码 `payment_option_not_available` 进入 §61.4 错误码表（store 侧 `payment_sessions#create` 响应）。
- **Admin**：`_options.html.erb` 每行增加范围编辑器（4 组多选）+ 摘要列；控制器归一 `payment_method[payment_options][<kind>][rule_set][...]`；i18n en/zh。
- **Storefront**：本期**不改渲染/文案**——被排除入口已由服务端过滤，不会出现在列表；`payment_option_not_available` 仅出现在「列表已过期」的竞态（如商家刚改范围），前端沿用既有错误通道展示服务端 message。专用文案 + 自动刷新列表属 §76.2 渲染编排（需 5 语言 i18n + 选项刷新编排），另立任务；`store.yaml` 已记录该码。
- **数据**：无迁移（`metadata` 内的 additive JSON）；无新表（§74 的 `pallastrade_payment_options` 属 D1 后半/D2）。
- **影响面**：`harness affected --base origin/dev`（实施时执行）。

## 8. 测试计划

| 测试文件 | 类型 | 覆盖 AC |
|---|---|---|
| `backend/spec/services/pallastrade/payments/availability/resolver_spec.rb`（新增） | RSpec | AC-001、AC-002、AC-008 |
| `backend/spec/models/pallastrade/payment_method_options_spec.rb`（扩展） | RSpec | AC-001、AC-003、AC-006 |
| `backend/spec/services/pallastrade/payment_sessions/start_spec.rb`（扩展） | RSpec | AC-004 |
| `backend/spec/requests/pallastrade/admin/payment_methods_spec.rb`（扩展） | RSpec | AC-005、AC-006 |
| serializer spec（admin `options[].rule_set`） | RSpec | AC-007 |
| `harness.config.mjs` + `harness verify d8-availability-rspec` | 验证器注册 | AC-009 |

## 9. 文档同步清单（知识同步门）

- [x] API 文档：`admin.yaml` schema 由 `scripts/ci/contracts.sh` 再生成（admin SDK `PaymentMethod.options[]` 增 `rule_set`/`scope_summary`，platform 副本同步）；store 侧两处 payment_sessions 创建端点补 `payment_option_not_available` 422 示例
- [x] Skill：`pallastrade-payments`（规则语义/同源硬约束/失败语义 + Changelog）、`pallastrade-admin`（范围编辑器 + 归一 + 回填）、`pallastrade-api-v3`（admin 投影 + store 失败码）、`pallastrade-data-model`（`rule_set` metadata 形态与值域）、`pallastrade-typescript-sdk`（生成类型变更）
- [x] 业务方案：§66 首版实施标注（4/14 维度 + 同源复算 + 后台编辑）、§63.5 页签行更新、§61.4 新增错误码行（`payment_option_not_available`）
- [x] `harness/scenarios/scenarios.json`：新增 GS-130（同一 Resolver 求值 + 规则归一 + Start 同源门禁）→ `harness eval-ai --scenarios` 131/131 valid
- [x] 本 PRD 状态更新（→ done）+ `docs/prd/README.md` 索引（`prd-status-sync --fix` 同步）
- [x] 评估（不强求更新）：**storefront** —— 被排除入口不在列表（服务端过滤）；`payment_option_not_available` 专用文案 + 自动刷新列表随 §76.2 任务（本期仅错误码契约进 `store.yaml`），故本期零 storefront 改动

**不在本期（记录以免误判为遗漏）**：其余 10 个维度（segment / amount / items / shipping / channel / device / risk / time / fulfillment / locale）；路由与熔断（§67）；规则模拟器与影响预览（§66.4）；`pallastrade_payment_options` 落表（§74）；前台按 `frontend_kind` 的渲染编排（§76.2）。

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-15 | 0.1 | 初稿（据业务方案 §65/§66/§74/§75/§76 + 6 层搜索；`prd new` 查重命中 D1 PRD 35% → `--force` 确属新需求：D1 = 入口配置，D8 = 入口适用范围） | AI |
| 2026-09-15 | 0.2 | 用户回复「**实施**」→ 状态 approved；建立 REQ（`REQ-20260915-d8-availability.md`）；实施切 2 片：① core 规则模型 + Resolver + 投影/Start 接入 ② admin 范围编辑器 + admin 投影 + 契约再生成 | AI |
| 2026-09-15 | 1.0 | **实施完成（切片1+2）→ done**：`Payments::Availability::{RuleSet,Context,Evaluator,Resolver}` + `Order#payment_methods` 三处投影接入 + `PaymentSessions::Start` 入口级同源门禁（422 `payment_option_not_available`，不建会话）+ 后台「适用范围」编辑（4 组多选/prefix 回填/摘要）+ admin API `options[].rule_set`/`scope_summary` + 契约再生成 + 新验证器 `d8-availability-rspec`（73 例全绿）。零 migration。 | AI |
| 2026-09-15 | 1.1 | 范围裁定（§7 收窄）：前台**不改渲染/文案**——专用文案 + 自动刷新列表归 §76.2 渲染编排（本期仅错误码契约进 `store.yaml`）；同期内另两点实施决策：摘要默认把 market/zone 解析为记录名（`default_option_scope_labels`）、表单加 `[rule_set][present]` 标记以区分「全空选择（清空）」与「未提交该区」。 | AI |
