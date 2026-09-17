# PRD-20260917-checkout-d15-切片3-3ds-sca-支付认证策略与-provider-下发-高风险订单只给-redirect-3ds

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-17 |
| 来源 | 需求：D15 切片3 3DS/SCA 支付认证策略与 provider 下发（高风险订单只给 redirect+3DS） |
| 分类 | checkout（自动判定） |
| 关联 Skill | `pallastrade-payments` / `pallastrade-security` / `pallastrade-checkout` / `pallastrade-admin` / `pallastrade-api-v3` |
| 关联 REQ | REQ-20260917-d15c-three-d-secure.md（实施时回填） |
| 关联 PRD | N/A（`prd new` 查重命中 D15 切片1 PRD 31%，评审确认为**新切片**后 `--force` 新建） |
| 需求类型 | 新功能 |

> 🔁 **查重回写记录**：`harness prd new` 报「D15 切片1 风控名单 PRD 相似度 31%」。
> 评审结论：`PRD-20260916-payments-d15-risk-lists` §「范围纪律」明确写「3DS/SCA 策略与 provider 下发 → 切片3」，
> `PRD-20260917-payments-d15b-risk-rules` 亦写明「`force_3ds` 与 provider 下发属切片3」——
> 故属**全新切片**，不回写原 PRD。

---

## 1. 背景与目标

- **一句话需求原文**：`需求：D15 切片3 3DS/SCA 支付认证策略与 provider 下发（高风险订单只给 redirect+3DS）`
- **业务方案依据**：§72.1「3DS / SCA 策略」（模式 `always` / `risk_based` / `off` + 豁免 + provider 映射）、§72.2「动作：放行 / 人工复核 / 阻断 / **强制 3DS**」、§78-D15 验收锚点**「高风险订单只给 redirect+3DS」**、§2865「风险档 Risk band → 服务端」。
- **现状（跨层搜索结论见 §6）**：
  - D15 切片1 交付了**名单 + 决策留痕**（`PaymentRiskAssessment`），切片2 交付了**规则引擎版本化/灰度/回滚**（动作词汇 `allow` / `review` / `block`），并明确把 `force_3ds` 与 provider 下发**留给切片3**；
  - 支付入口侧已有**唯一求值点** `Payments::Availability::Resolver`（D8：范围规则 + 能力目录 + D11 熔断；前台列表与 `PaymentSessions::Start` **同源硬约束** §66.5），入口目录 `payment_option_catalog` 已带 `kind` / `frontend_kind`（Stripe：`card`=inline、`apple_pay`/`google_pay`=express）；
  - Stripe 会话目前是 **Checkout Session `ui_mode: elements`**（`CheckoutSessionPresenter`，`payment_intent_data` 可下发支付意图级参数），卡挑战由 provider 端处理。
  - **缺**：① 商家可配置的 3DS/SCA **策略与豁免**（今天完全由 provider 默认值决定）；② 规则动作 `force_3ds`；③ 「高风险 → 只给能完成认证的入口」的**入口闸门**（今天钱包/一键入口与内嵌卡表单在高风险下照样可选）；④ 向 provider **下发**「强制挑战」指令的链路；⑤ 决策与出口的**可解释留痕**（为什么只显示了这个入口）。
- **目标**：把「要不要挑战」从「provider 默认」变成**商家可配置策略 + 订单级风险决策 → 单一判定 → 入口闸门 → provider 下发**的闭环，交付 §78-D15 验收锚点：**高风险订单只给 redirect+3DS**。
- **成功指标**：
  1. 策略 `risk_based`（默认）下，**无风险信号订单的可用入口集合与今天逐项相同**（零感，回归 spec 兜底）；
  2. 命中 `force_3ds`（或策略 `always`）的订单：**可用入口集合 ∩ 无法保证认证的入口 = ∅**，且 `PaymentSessions::Start` 对不合规入口**建会话前拒绝**（结构化错误，不产生任何 session 行）；
  3. 出口可解释：能回答「**为什么只显示这些支付方式**」（策略模式 + 风险动作 + 命中豁免 + 被排除入口与原因）；
  4. 判定与闸门**零资金副作用**（不改 Payment/Order/Journal 金额与状态、不阻断结账、不改 Preflight 阻断行为）。

**铁律（本切片不破）**：判定与闸门**零 provider I/O**（provider 只在既有建会话路径被调用，且只多传一个已声明的参数）；不改「支付成功 → 订单完成」既有链路；不引入任何自动扣款/自动退款/自动取消。

**范围纪律（本切片不做）**：Adyen 等其它 provider 的 3DS 参数落地（只留能力声明位与「不支持就不下发」的诚实路径）；MIT（商户发起交易）豁免的真实实现（无可信 MIT 标志，**不猜**，登记为"未实现"）；挑战率看板（§72.5 观测层另立切片）；保存卡后续扣款的 SCA 例外；3DS 失败后的重试编排（属既有 `authentication_failed` 语义，本切片不改）。

---

## 2. 用户故事 / 场景

- 作为**商家/风控运营**，我希望在后台配置「什么时候必须挑战」的策略与豁免，以便不依赖 provider 默认值、且对 PSD2 地区给出可辩护的口径。
- 作为**风控运营**，我希望规则命中时能选「强制 3DS」动作，以便不走「阻断」也能把高风险订单逼到认证环节。
- 作为**顾客（高风险订单）**，我希望在结账页只看到能完成认证的支付方式，以便不会选了钱包/一键支付后又被拒绝。
- 作为**客服/工程**，我希望看到「为什么这些入口被隐藏」，以便解释与排障。

场景（正常 / 边界 / 异常）：

1. **正常（默认 `risk_based` + 低风险）**：策略默认、订单无风险信号 → 认证需求 = 否 → 入口集合 = 策略前的集合（与今天一致）。
2. **正常（规则 `force_3ds`）**：规则集命中 `force_3ds` → 认证需求 = 是 → express 钱包入口消失、可认证入口保留，且建会话时下发「强制挑战」。
3. **边界（豁免优先）**：策略 `always`，但订单金额 < `low_amount_threshold`（TRA）或国家在 `allowlisted_countries` → 认证需求 = 否，且留痕 `exemptions` 如实列出（可解释）。
4. **边界（策略 `off`）**：显式关闭 → 无风险时恒为否；**但**若风险决策为 `force_3ds` → 风险严格性优先（`off` 不覆盖显式 `force_3ds`），留痕记 `policy_off_overridden_by: 'risk_rule'`。
5. **边界（provider 不支持下达）**：入口目录未声明强认证能力 → 该入口在「认证需求 = 是」时**不出现**（而不是出现后再失败）；留痕记 `provider_hint: 'none'`。
6. **异常（客户端绕过）**：前端直接对不合规入口调 `POST /api/v3/store/orders/:id/payment_sessions` → `PaymentSessions::Start` 在建会话**之前**返回 **422 `payment_option_not_available`（`reason='authentication_required'`）**，**零 session 行写入**；前台按 D8 既有约定刷新列表并提示重选。
7. **异常（无可用入口）**：认证需求 = 是且店铺**没有任何**具备强认证能力的入口 → 前台展示「需可认证的支付方式」提示（不静默空白），后台计数可见，**不**自动降级为弱认证入口（不猜）。
8. **异常（策略配置非法）**：后台提交未知模式 / 负阈值 / 非法国家码 → 归一化拒绝并提示，不落库。

---

## 3. 功能需求（FR）

### FR-001 3DS/SCA 策略（store 级，零新表）
- 存储：`store.private_metadata['three_d_secure_policy']`（与 `dispute_rate_policy` 同先例，**零迁移**）。
- 字段：`mode`（`always` / `risk_based`（默认）/ `off`）、`low_amount_threshold`（可选；**仅订单币种与店铺默认币种一致时参与比较**，否则视为未配置，**不跨币种猜**）、`allowlisted_countries`（ISO-2 数组）、`allowlisted_option_kinds`（入口白名单）。
- 唯一入口：`Payments::ThreeDSecure::Policy.normalize(raw)` / `.for(store)`；非法值 → 回落默认并返回 reasons；`mode` 未知 → 后台表单层拒绝（不落库）。
- 审计：保存策略写审计 `store_three_d_secure_policy_updated`。

### FR-002 订单级认证需求判定（唯一入口、只读、零 provider）
- 新服务 `Payments::ThreeDSecure::Required.call(order:, store:, now:)`（`ServiceModule::Result`）：
  - 输入：门店策略 + 该订单**最近一次**风险决策（`PaymentRiskAssessment`：`force_3ds` 或其它）+ 订单事实（金额 / 币种 / 国家）。
  - 输出：`{ required:, mode:, source: 'policy'|'risk_rule'|'policy+risk', reason:, exemptions: [...], risk_action:, threshold_used:, threshold_skipped: }`。
  - 语义顺序（写死、可断言）：策略 `off` → 否（**除非**风险 `force_3ds`）；`always` → 是（豁免可放宽到否）；`risk_based` → 仅当风险决策 = `force_3ds` 时为是（豁免同样生效）。
  - **豁免只放宽「是否挑战」，不放宽「是否可付」**：`block` 决策不被豁免改写（仍走既有阻断语义，本切片不改）。
- **零 provider**、**不写库**（纯判定；留痕由 FR-006 承担）。

### FR-003 规则动作 `force_3ds`
- `Risk::Rules::Schema::ACTIONS` 增加 `force_3ds`（发布校验通过）；非法动作仍拒绝。
- 严重度（唯一口径）：`allow(0) < review(1) < force_3ds(2) < block(3)`；`Risk::Assess::DECISION_SEVERITY` 同步；`PaymentRiskAssessment::DECISIONS` 增加 `force_3ds` 并并入 `FLAGGED_DECISIONS`。
- 合并规则不变：白名单 `allow` **短路**；否则「名单动作 vs 规则动作」取**最严者**（`force_3ds` 可覆盖 `review`，**不得**放宽 `block`）。
- 留痕：`signals['rule_engine']['action']` 呈现；`decision_source` 语义不变。
- 后台规则工作台：动作词汇与预览新增 `force_3ds`（i18n en + zh-CN 键集相等）。

### FR-004 入口闸门（扩展 D8 同源求值，唯一口径）
- `Payments::Availability::Resolver.evaluate` 逐入口结果新增原因 `{ 'dimension' => 'three_d_secure', 'reason' => 'authentication_required' }`；
  `available_options` / `providers` / `option_available?` 与 `PaymentSessions::Start` **自动同源生效**（不新增第二套筛选）。
- 判定：认证需求 = 是时，仅**入口目录声明可强制认证**的入口可用；express 钱包（Stripe `apple_pay` / `google_pay`）与未声明能力者一律不可用。
- 能力声明（provider 侧 `payment_option_catalog`）：新增 `'three_d_secure' => 'supported' | 'unsupported'`；Stripe `card` = `supported`，钱包 = `unsupported`（**无声明按 unsupported 处理，不猜**）。
- `PaymentSessions::Start`：不合规入口 → 沿用 D8 既有失败语义 **422 `payment_option_not_available`**，并在 payload 里新增 `reason: 'authentication_required'`（**不新建错误码家族**，客户端「刷新列表 + 重选」的既有处理无需改动），**建会话前**返回（零 session 行）。
- 「无可用入口」时：checkout 投影给出显式信号（FR-005），前台据此提示，不静默空白。

### FR-005 前台契约（同源投影，非新筛选）
- checkout 投影的支付方式项新增 `requires_authentication`（布尔）；选项级暴露被排除原因（供解释/排障）。
- 投影**仍只列出可用入口**（隐藏 = 不出现），与 `Start` 判定同源。
- 契约同步：`backend/public/api-docs/store.yaml` + `platform/docs/api-reference/` + SDK 生成类型（`harness generated:check` 零漂移）。
- 前台（Next.js）：无可用入口时展示提示文案（i18n 两语言）；**不做客户端筛选**。

### FR-006 留痕、事件与可解释性
- `PaymentRiskAssessment.signals['three_d_secure']`：`{ required:, mode:, source:, reason:, exemptions:, policy_off_overridden_by:, risk_action:, threshold_used:, threshold_skipped: }`（jsonb，零迁移）。
- 事件 `payment.three_d_secure_required`：仅 `required=true` 时发布，payload 无 PII（`order_id` / `mode` / `source` / `exemptions` / `risk_action`）；事件系统未启用或发布失败**不阻断**支付路径。
- 后台：订单页风控卡显示认证需求与来源；支付方式页入口表新增「可强制认证」列（只读，来自 catalog）。

### FR-007 provider 下发（已声明能力才下发，不支持就诚实不下发）
- 建会话时透传认证指令：`Payments::ThreeDSecure::ProviderHint.call(payment_method:, option_kind:, required:)` →
  - Stripe `card`：`payment_intent_data.payment_method_options.card.request_three_d_secure = 'any'`（`CheckoutSessionPresenter` 透传）；
  - 其它 provider / 未声明能力：返回 `{ applied: false, hint: 'none' }`，**不发送未知参数**。
- 留痕：会话 `metadata` 记 `three_d_secure_hint`（`applied` / `none`），不记任何凭据。
- 无法强制认证时**不静默跳过**——由 FR-004 闸门保证该入口本就不可选。

### FR-008 后台：策略编辑与动作文案
- 门店编辑页新增「3DS / SCA 策略」区块：模式 + 低金额阈值 + 国家白名单 + 入口白名单；归一化 + 审计；i18n en + zh-CN 键集相等。
- 规则工作台 `force_3ds` 文案与展示（FR-003）；权限沿用既有 `can :manage, PallasTrade::Store` / `RiskRuleSet`（**不新增权限资源**）。

---

## 4. 非功能需求（NFR）

- **性能**：判定为常数次本地查询（策略取自 store 属性、决策取最近一行、订单事实在内存）→ **查询数不随入口数增长**（闸门落在既有 `Resolver.evaluate` 内，无新增 N 次查询）。
- **安全**：不落卡数据/PII；事件 payload 无 PII；策略编辑走既有权限与审计；`request_three_d_secure` 为公开参数，无凭据外泄面。
- **兼容（零感）**：默认 `risk_based` + 无风险信号 = 与今天逐项一致；未选项化 provider 的默认入口路径不变；`DECISIONS` 扩展不改变既有行语义；未配置门店与 `off` 行为一致。
- **可维护性**：策略归一化 / 认证判定 / 闸门原因 / provider 指令各自单一入口；`Resolver` 不新增第二套筛选（D8 §66.5 同源硬约束）。
- **可观测性**：留痕（signals）+ 事件 + 后台可见；**不新增表、不新增后台导航项**。
- **不改动**：`Checkout::Preflight` 的启用条件与阻断行为；`PaymentSessions::Start` 的既有复用/幂等/quote 门逻辑（只在可用性校验处消费认证闸门）。

---

## 5. 验收标准（AC，与测试一一映射）

| AC | ← FR | 判定条件（可验证） |
|---|---|---|
| AC-001 | FR-001 | 策略归一化：默认 `risk_based`；三值合法；未知模式/负阈值/非法国家码 → 拒绝（后台层）；低金额阈值仅同币种参与比较 |
| AC-002 | FR-001 | 保存策略写审计；未配置门店读取返回默认值（不落库、不报错） |
| AC-003 | FR-002 | `off` 无风险 → `required=false`；`always` → `true`；`risk_based` → 仅 `force_3ds` 时 `true`；判定 **零写库、零 provider** |
| AC-004 | FR-002 | 豁免优先：低金额（同币种）/ 国家白名单命中 → `false` 且 `exemptions` 如实列出；跨币种阈值不生效（记 `threshold_skipped='currency_mismatch'`） |
| AC-005 | FR-002 | 风险严格性优先：策略 `off` + 风险 `force_3ds` → `true` + `policy_off_overridden_by='risk_rule'`；`block` 不被豁免放宽 |
| AC-006 | FR-003 | 发布门接受 `force_3ds`（非法动作仍拒）；严重度序 `allow<review<force_3ds<block`；`force_3ds` 覆盖 `review`、不覆盖 `block`；白名单 `allow` 仍短路 |
| AC-007 | FR-003 | `PaymentRiskAssessment` 接受 `force_3ds` 且 `flagged?` = true；留痕 `signals['rule_engine']['action']='force_3ds'` |
| AC-008 | FR-004 | 认证需求 = 是时 `available_option_kinds` 不含未声明强认证能力的入口；`evaluate` 含 `dimension=three_d_secure` 原因；前台列表与 `Start` 判定同源 |
| AC-009 | FR-004 | `Start` 对不合规入口返回 422 `payment_option_not_available` + `reason='authentication_required'`，且 **DB session 计数前后相等**；合规入口正常建会话 |
| AC-010 | FR-004 | 认证需求 = 否时可用入口集合与变更前**逐项相同**（含 optionized 与未选项化两条路径） |
| AC-011 | FR-005 | checkout 投影含 `requires_authentication`；隐藏 = 不出现；契约文档与 SDK 类型同步（`generated:check` 零漂移） |
| AC-012 | FR-006 | `signals['three_d_secure']` 字段齐全；`required=true` 恰好发布一次事件（无 PII），发事件失败不阻断建会话；`required=false` 不发 |
| AC-013 | FR-007 | Stripe `card` + required → 会话载荷含 `request_three_d_secure='any'`（stub 断言，零真实 provider）；未声明能力入口 → hint `none` 且无未知参数 |
| AC-014 | FR-008 | 门店策略区块保存/校验/审计 + i18n en↔zh-CN 键集相等；后台入口表显示认证能力列（只读） |
| AC-015 | NFR | 判定与闸门查询数不随入口数增长（`ActiveRecord::Base.count_queries` 断言）；dev 冒烟：策略切换后入口集合按预期变化且零资金副作用 |

---

## 6. 跨层搜索记录（6 层，gate 强制）

关键词：`3ds` / `three_d_secure` / `sca` / `payment_option` / `frontend_kind` / `availability` / `Risk::Assess` / `force_3ds`

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | `3ds` / `risk` / `payment_option` | 仅序列化类型（`considered_risky`）与 CSS 徽章 | ❌ 零命中 |
| Core | `pallastrade_gems/pallastrade_core/app/` | `payment_option` / `availability` / `force_3ds` | `payments/availability/{resolver,rule_set,evaluator}.rb`（**唯一求值点**）、`payment_sessions/start.rb`（建会话前可用性校验）、`risk/assess.rb`（`DECISION_SEVERITY`）、`payment_risk_assessment.rb`（`DECISIONS`/`FLAGGED_DECISIONS`/`signals`）、`payment_method.rb`（`payment_option_catalog`/`effective_payment_options`）、`payments/error_codes.rb`（`authentication_failed`） | ⚠️ 部分（求值与决策底座齐、**缺策略/判定/闸门/下发**） |
| API | `pallastrade_gems/pallastrade_api/app/` | `payment_sessions` / `payment_option` | `store/orders/payment_sessions_controller.rb`、`store/checkout/checkout_serializer.rb`（`available_payment_methods` + `method_key`）、`payment_method_serializer.rb` | ⚠️ 部分（契约可增量扩展） |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | `frontend_kind` / `optionized` | `payment_methods_controller.rb`（`merge_payment_options_into`/`normalize_payment_option`）、`views/.../payment_methods/_options.html.erb`（入口表含 `frontend_kind` 列）、stores 编辑页（私域配置先例）、risk_rules 工作台（动作词汇） | ⚠️ 部分（可扩展，缺策略区块与动作文案） |
| Storefront | `storefront/src/` | `express` / `inline` / `redirect` | `components/checkout/OrderPaymentContent.tsx`（单选 + Stripe 内嵌卡表单）、`components/checkout/ExpressCheckoutButton.tsx`（钱包）、`lib/checkout/express-canonical.ts` | ⚠️ 部分（已按服务端列表渲染；缺「无可用入口」提示） |
| Platform | `platform/packages/` | `method_key` / `frontend_kind` | `sdk/src/types/generated/StoreCheckoutCheckout.ts`、`README.md`（入口口径） | ⚠️ 生成物，随 OpenAPI 同步 |

**结论**：**无重复实现风险** —— `Resolver` 是既有唯一求值点（本切片**扩展**它，不新建第二套筛选）；策略 / 判定 / 闸门 / 下发四件套**新建**（core gem 内）；Stripe 下发点唯一（`CheckoutSessionPresenter#payment_intent_data`）；契约字段为**增量**（不动既有字段）。

**防重复判定（AP-SEARCH-1/2/3 兜底）**：钱包入口的隐藏**不**在 storefront 客户端做（前端零筛选逻辑），一律由 `Resolver` 输出决定（D8 §66.5 同源硬约束）。

## 7. 技术影响

| 层 | 文件（新/改） | 说明 |
|---|---|---|
| Core（新） | `payments/three_d_secure/{policy,required,provider_hint}.rb` | 策略归一化 / 订单级判定 / provider 指令 |
| Core（改） | `payments/availability/resolver.rb` | 新增 `three_d_secure` 原因维度（同源） |
| Core（改） | `risk/rules/schema.rb`、`risk/assess.rb`、`models/pallastrade/payment_risk_assessment.rb` | 动作 `force_3ds` + 严重度 + 决策集 |
| Core（改） | `payment_sessions/start.rb` | 不合规入口 → 结构化错误（建会话前） |
| Stripe（改） | `payment_option_catalog`（能力声明）、`checkout_session_presenter.rb`（`request_three_d_secure`） | 能力 + 下发 |
| API（改） | `store/checkout/checkout_serializer.rb`、`store/orders/payment_sessions_controller.rb` | 契约增量 + 错误码透出 |
| 契约（改） | `backend/public/api-docs/store.yaml` + `platform/docs/api-reference/` + SDK 生成类型 | `generated:check` 零漂移 |
| Admin（改） | stores 表单（策略区块）+ `payment_methods/_options.html.erb`（认证能力列）+ risk_rules 文案 | i18n en + zh-CN 键集相等 |
| Storefront（改） | 结账页「无可用入口」提示（i18n） | 零客户端筛选 |
| 数据库 | **零迁移**（store `private_metadata` / assessment `signals` / session `metadata`） | 无 schema 变更 |
| 事件 | 新增 `payment.three_d_secure_required` | payload 无 PII |

**影响面**：`harness affected` 输出见 REQ；重点回归 = D8 可用性、D11 熔断、D16 入口展示、切片1/2 风控决策、Checkout 收尾收敛 B4（express canonical）。

## 8. 测试计划

| 层 | 文件 | 覆盖 |
|---|---|---|
| 服务 | `spec/services/pallastrade/payments/three_d_secure/d15c_policy_spec.rb` | AC-001/002 |
| 服务 | `spec/services/pallastrade/payments/three_d_secure/d15c_required_spec.rb` | AC-003/004/005 |
| 服务 | `spec/services/pallastrade/risk/d15c_force_3ds_action_spec.rb` | AC-006/007 |
| 服务 | `spec/services/pallastrade/payments/availability/d15c_authentication_gate_spec.rb` | AC-008/010/015 |
| 集成 | `spec/services/pallastrade/payment_sessions/d15c_start_gate_spec.rb` | AC-009 |
| 请求 | `spec/requests/api/v3/store/d15c_checkout_authentication_spec.rb` | AC-011 |
| 单元 | `spec/services/pallastrade_stripe/d15c_three_d_secure_hint_spec.rb` | AC-013（stub 断言载荷，零真实 provider） |
| 请求 | `spec/requests/pallastrade/admin/d15c_three_d_secure_policy_spec.rb` | AC-014 |
| 前端 | `storefront/src/components/checkout/__tests__/OrderPaymentContent.test.tsx` | AC-011 前台侧（认证提示 / 无可用入口提示，2 例新增） |
| 回归 | D8 availability / D11 breaker / D16 presentation / 切片1 assess / 切片2 rules / checkout 契约序列化 / preflight / 导航一致性 既有 spec | AC-010 零回归（契约序列化 spec 的键集断言按 additive 新增 `requires_authentication`） |

**验证器**：`d15c-three-d-secure-rspec`（上述集合 + 导航一致性 + 回归）。
**dev 冒烟**：`tmp-toy/d15c_dev_smoke.rb`（事务包裹 + 结束回滚）—— 策略三模式切换 → 入口集合变化 → `Start` 拒绝 → 零资金副作用；HTTP 探活。
**E2E**：`harness e2e storefront`（高风险订单结账页只显示可认证入口）。

## 9. 文档同步清单（知识同步门）

- [x] `ai/skills/pallastrade-payments/SKILL.md`：「3DS / SCA —— 认证策略、订单级判定与 provider 下发」全链路（策略两路径/判定语义/闸门/下发/契约/铁律）
- [x] `ai/skills/pallastrade-security/SKILL.md`：`force_3ds` 入动作词汇与严重度 `allow<review<force_3ds<block` + 「3DS/SCA 认证需求：从风险决策到入口闸门」（风险严格性优先 / 豁免只放宽挑战）
- [x] `ai/skills/pallastrade-checkout/SKILL.md`：「结账页的 3DS/SCA 认证需求」（契字段 / 零筛选 / 无入口是显式状态 / 不改 Preflight）
- [x] `ai/skills/pallastrade-admin/SKILL.md`：门店策略区块 + 入口能力列 + `force_3ds` 动作文案
- [x] `ai/skills/pallastrade-api-v3/SKILL.md`：checkout 契约增量（`requires_authentication` + 空列表语义 + 422 reason）
- [x] `ai/skills/pallastrade-events-webhooks/SKILL.md`：事件 `payment.three_d_secure_required`
- [x] `AGENTS.md` §6：新 verifier 行（`d15c-three-d-secure-rspec`）
- [x] `harness/scenarios/scenarios.json`：GS-171（「高风险单只能看到能认证的入口」）→ `eval-ai --scenarios` **172/172**
- [x] `backend/public/api-docs/store.yaml` + `platform/docs/api-reference/`：**已评估** —— 该投影未在 OpenAPI `components.schemas` 逐字枚举（非 Typelizer 所有权），`rake api:docs:schemas` 后 **零 drift**；消费者契约由 SDK 类型承担：`backend/app/javascript/types/serializers/PallasTradeApiV3StoreCheckoutCheckout.ts` + `backend/packages/sdk/...` + `platform/packages/sdk/src/types/generated/StoreCheckoutCheckout.ts` 三处已随 Typelizer 生成（`scripts/ci/contracts.sh` 同步），`harness generated:check` 零漂移
- [x] 业务方案 §72.1 / §78-D15 回写（本地设计文档，`.gitignore` 内）
- [x] `docs/prd/README.md` 索引（状态 → done + 实施摘要）

## 9.1 实施记录（2026-09-17）

**交付物**（新增/修改）：

| 层 | 文件 |
|---|---|
| Core（新） | `payments/three_d_secure/{policy,required,provider_hint}.rb` |
| Core（改） | `payments/availability/{resolver,context}.rb`（新增 `three_d_secure` 原因维度）、`payment_sessions/start.rb`（建会话前闸门 + `reason='authentication_required'`）、`risk/assess.rb`（严重度 + `force_3ds`）、`models/pallastrade/{payment_risk_assessment,risk_rule_version}.rb`（决策集 + 动作词汇） |
| Stripe（改） | `pallastrade_stripe/gateway.rb`（入口目录声明 `three_d_secure`）、`gateway/{payment_sessions,payment_intents}.rb` + `checkout_session_presenter.rb` + `payment_intent_presenter.rb`（`request_three_d_secure` 透传与会话 metadata 留痕） |
| API（改） | `store/checkout/checkout_serializer.rb`（`requires_authentication`） |
| Admin（改） | `admin/stores_controller.rb`（策略归一化/校验/审计）、`views/.../stores/form/_checkout.html.erb`（策略区块）、`views/.../payment_methods/_options.html.erb` + `helpers/.../payments_helper.rb`（只读能力列）、`admin_risk_rules.zh-CN.yml`（动作文案）；gem `en.yml` 同步 |
| 契约 | `backend/app/javascript/types/serializers/PallasTradeApiV3StoreCheckoutCheckout.ts`、`backend/packages/sdk/src/types/generated/StoreCheckoutCheckout.ts`、`platform/packages/sdk/src/types/generated/StoreCheckoutCheckout.ts`（Typelizer 生成 + 平台副本同步） |
| Storefront（改） | `components/checkout/OrderPaymentContent.tsx`（认证需求提示 + 无可用入口提示，零客户端筛选）、`messages/{en,de,es,fr,pl}.json`（五语言键集一致） |
| 测试 | `d15c_{policy,required,force_3ds_action,authentication_gate,start_gate,three_d_secure_hint,checkout_authentication,three_d_secure_policy}` 8 个 spec（55 例）+ 契约序列化 spec 键集断言（additive）+ 前端 2 例 |

**范围扩展说明**：任务 `--allow` 声明了 `backend/**`、`docs/prd/**`、`harness/**`、`ai/skills/**`；本切片按 PRD FR-005/§7（Storefront 行）**额外修改 `storefront/`**（21 行组件 + 五语言文案 + 2 例组件测试）—— 范围扩展已在此处显式声明，并在提交信息中标注。

**测试结果**：
- verifier `d15c-three-d-secure-rspec`（18 个 spec 文件，含 D8/D11/D16/契约/切片1·2/导航回归）→ **181 examples, 0 failures**；新增 8 个 d15c spec 共 55 例。
- 前端：`vitest run OrderPaymentContent` → **23 例全绿**；`tsc --noEmit` 干净；`biome check` 干净；`check:locale-parity` 五语言一致。
- 契约：`scripts/ci/contracts.sh`（typelizer + api:docs:schemas + 平台副本同步）后 `harness generated:check` **零漂移**。

**实施中的关键发现（可复用）**：

1. **共享上下文的 `store` 实例会让「同值写」变成空写**：`shared_context 'API v3 Store'` 的 `let(:store) { @default_store || ... }` 里 `@default_store` 在 example group 内**跨 example 复用**（事务回滚只回滚 DB，不回滚该 Ruby 对象的内存值）→ `store.update!(private_metadata: <与内存相同>)` 被 AR 判为无变化 → **不发 UPDATE**，DB 保持空，后面的 example 凭空看到「未配置策略」。定式：**写前先 `store.reload`**（或 `update_columns`）。⚠️ 这个坑与 `pallastrade-testing` SKILL「本地绿 CI 红」同族：都是**共享/种子状态**导致的假设错误。
2. **契约 additive 必然撞旧键集断言**：D16/D10 时期的 `checkout_serializer_spec` 用 `contain_exactly` 锁了键集合 —— 新增字段必须同步该断言（这正是「零感」的守卫：它逼你把变更**显式**登记）。
3. **Typelizer 是契约的唯一生成源**：改序列化器后必须 `bash scripts/ci/contracts.sh`（生成 + 把 `backend/packages/sdk` 与 `api-docs` 副本同步到 `platform/`）；只手动改 `platform/` 副本会被下次生成覆盖，也可能漏掉 `backend/app/javascript/types/serializers/`。
4. **前端类型：结账投影 ≠ `PaymentMethod`**（后者是 Typelizer 从 `PaymentMethodSerializer` 生成、不含认证字段）→ 组件用本地 `PaymentMethod & { requires_authentication?: boolean }` 表达「投影有、订单快照回退可能没有」。
5. **五语言 JSON 的手工编辑极易写出「一行两个值」**（`"k": "v1", "v2",`）→ 症状是 `tsc` 报 TS1328/TS1005 且**只在 `tsc` 才暴露**；改完文案**必跑** `pnpm check:locales` + `npx tsc --noEmit`。

**已知限制 / 遗留**：Adyen/PayPal 等 provider 的 3DS 参数落地（只留能力声明位与「不支持就不下发」的诚实路径）；MIT（商户发起交易）豁免真实实现（无可信 MIT 标志 → 不猜）；挑战率看板（§72.5 观测层，另立切片）；3DS 失败后的重试编排（沿用既有 `authentication_failed` 语义，本切片不改）。

## 10. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-09-17 | 初稿（D15 切片3；业务方案 §72.1/§72.2/§78-D15；`prd new` 查重命中切片1 PRD 31% → 评审确认为新切片后 `--force`；跨层搜索见 §6） |
| 2026-09-17 | 实施完成：3 新服务 + 9 改文件 + 8 个 d15c spec（55 例）→ verifier `d15c-three-d-secure-rspec` **181 examples / 0 failures**；契约 additive（`requires_authentication`）+ SDK 类型三处同步；前端提示 2 例组件测试（前端 23 例全绿、locale parity 五语言一致）；GS-171 入库（172/172）；6 Skill + `AGENTS.md` §6 + 业务方案回写；状态 → `done`（见 §9.1） |
