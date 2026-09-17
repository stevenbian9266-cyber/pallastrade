# PRD-20260917-payments-d15b-risk-rules

| 元数据 | 值 |
|---|---|
| 状态 | done（2026-09-17 实施完成） |
| 创建日期 | 2026-09-17 |
| 来源 | 需求：D15 切片2 支付风控规则引擎版本化/灰度/回滚（业务方案 §72.2 + §78-D15） |
| 分类 | payments（`prd new` 命中 payments；查重命中 D15 切片1 PRD 42%，经评审确认为**新切片**：新表/新服务/新语义，故 `--force` 新建） |
| 关联 Skill | `pallastrade-security`、`pallastrade-data-model`、`pallastrade-admin`、`pallastrade-events-webhooks`、`pallastrade-checkout`、`pallastrade-testing` |
| 关联 PRD | `PRD-20260916-payments-d15-risk-lists`（切片1：名单 + 评估留痕，本切片扩展同一入口 `Risk::Assess`）、`PRD-20260828-checkout-p8`（P8 下单前置校验，flag 门控的 `Checkout::Preflight`） |
| 需求类型 | 新功能（**扩展**既有 `PallasTrade::Risk` 规则引擎：加版本化 + 灰度 + 回滚；**不另建引擎**） |

## 1. 背景与目标

业务方案 §72.2 要求规则引擎具备：条件（金额/国家/BIN/卡类型/邮箱/设备/IP/历史行为/velocity）、动作（放行/人工复核/阻断/强制 3DS）、**版本化（每次变更生成版本，可回滚）+ 灰度（按流量百分比）**；§78-D15 的验收锚点为「高风险订单只给 redirect+3DS；**规则可回滚**；名单可批量导入」——其中「规则可回滚」由本切片交付（3DS 下发属切片3）。

**今天缺什么**（已核对代码，见 §6）：

1. `PallasTrade::Risk`（`lib/pallastrade/risk.rb`，P8 2026-08-28）只有**代码注册式**规则（`Risk.rules << RuleClass`，进程内数组），规则内容与阈值分散在 `preferences` / `Config` 中——**改规则 = 改代码/改配置 + 重启**，既无版本、也无法回滚；
2. D15 切片1 的 `Risk::Assess` 只消费**名单**（denylist/allowlist），没有「条件 → 动作」的规则层；
3. 没有任何**灰度**能力：仓库里的「灰度」全部是 feature flag 注释语义（`flag 灰度`），与「按流量百分比」无关；
4. 运营无法预览「这条规则会不会命中这个订单」，也无法回答「昨天的决策用的是哪一版规则」。

**目标**

- G1 **可配置**：规则（条件 + 动作 + 优先级）落库，运营可在后台维护，**无需发版**。
- G2 **可回滚**：每次变更生成**不可变版本**；回滚 = 以历史版本内容生成**新版本**并生效，全程可审计（验收锚点「规则可回滚」）。
- G3 **可灰度**：金丝雀版本按**订单维度稳定分桶**的流量百分比生效；桶值可复算、可审计（同一订单永远落同一桶）。
- G4 **可解释**：评估留痕记录**用了哪个规则集的哪一版、是否金丝雀、命中哪条规则、命中哪些条件**；缺失主体**不猜**。
- G5 **零风险**：零 provider、零资金副作用；本切片**不改变下单是否被阻断**的既有行为（决策只产出与留痕）。

**非目标**（本切片不做，避免越界）

- **`force_3ds` 动作与 provider 下发**：属切片3（3DS/SCA 策略）；本切片动作词汇 = `allow` / `review` / `block`，扩展点（动作常量 + 严重度表 + 留痕字段）预留。
- **不改 `Checkout::Preflight` 的启用条件与阻断行为**：既有 flag 门控逻辑不动（阻断生效 = 后续切片按运营开关决策；本切片只保证决策**可被消费**）。
- **不做 BIN / 设备指纹条件**：`pallastrade_credit_cards` 无 BIN 列、平台无设备指纹采集 → 不提供这两个条件键（**不猜**），在页面与 Skill 明示。
- **不做 IP 地理/网段判定**（无离线库）；只提供 `ip_present`。
- **不做可视化规则构建器**：规则以结构化 JSON 编辑 + 服务端严格校验 + 预览（可视化构建器 = 后续迭代，PRD §10 记录）。
- **不做规则执行性能工程**（如缓存/索引优化）：评估为 O(规则数)，规则数有界（发布校验限制 ≤ 50 条/版本）。

## 2. 用户故事 / 场景

- **US-1（运营改规则）**：作为风控运营，我要在后台新增一条「金额 ≥ 500 且国家 = KP → 人工复核」的规则并**先预览**它对某订单的判定，再发布生效，而不需要研发发版。
- **US-2（灰度上线）**：作为风控运营，我要把新版本先对 **10% 的订单**灰度，观察留痕中的命中率后再逐步放量；同一订单重复评估必须命中同一版本（否则无法复盘）。
- **US-3（回滚）**：作为风控负责人，当发现新规则误伤时，我要一键**回滚到上一版**，且系统必须留下「谁、何时、从哪版回滚到哪版、原因是什么」的审计与一份**新的不可变版本**（历史版本不可被改写）。
- **US-4（复盘某笔订单）**：作为支付运营，我要打开订单的风控卡，看到「命中规则 X（规则集 default 第 4 版，非金丝雀，桶 37），动作 review」。

## 3. 功能需求（FR）

### FR-001 规则集与版本模型（两表）

- `pallastrade_risk_rule_sets`：`store_id`（NULL = 全局，非空 = 店铺，与名单同口径）、`code`（稳定标识）、`name`、`description`、`status`（`active`/`inactive`）、`active_version_id`、`canary_version_id`、`canary_percent`（0–100）、`metadata`。
- `pallastrade_risk_rule_versions`：`rule_set_id`、`version`（每集从 1 单调递增，**唯一**）、`state`（`draft`/`published`/`archived`）、`rules`（jsonb 数组）、`reason`、`source_version`（回滚来源）、`rolled_back`（bool）、`created_by_type/id`、`published_at`、`metadata`。
- 唯一性：`(rule_set_id, version)`；规则集 `code` 在「全局」与「每店铺」两个作用域内各自唯一（**partial unique index**，避免 NULL 不去重）。
- **版本不可变**：`published` 版本的 `rules` 不允许修改（模型层拒绝；如需改 = 新建版本）。

### FR-002 规则与条件词汇（唯一权威，发布时强校验）

- 规则 = `{code, priority, conditions, action, note}`；`priority` 升序评估，同优先级按数组顺序。
- `conditions` 为**白名单键的 AND 组合**；键集合（全部取订单本地事实，零 provider）：
  - `amount_gte` / `amount_lte`（订单 `total`；`currency_in` 未同时给定时按店铺默认币种比较，币种不符 → **不命中**并记 `currency_mismatch`）
  - `currency_in`（数组，大写 ISO）
  - `country_in`（账单地址国家 ISO2；缺失 → 不命中）
  - `email_domain_in`（域名小写比较）、`email_present`（bool）
  - `ip_present`（bool）
  - `card_brand_in`（卡品牌归一后比较，与 D14c 同词汇 `visa`/`master`/`american_express`/…）
  - `customer_orders_gte`（同客户**已完成**订单数；匿名单不适用 → 不命中）
  - `velocity_count_gte` + `velocity_window_minutes`（同邮箱或同 IP 在窗口内的订单数；两者都缺 → 不命中）
- **未知键 / 类型错误 / 非法动作 / 空条件 / `priority` 非整数 / 规则数 > 50** → **发布失败**并返回人可读错误（不落库、不改现状）。
- 不可判定（主体缺失、币种不符）→ **不命中**（**不猜**），并在评估结果 `skipped` 中记录原因。

### FR-003 生效版本与灰度（确定性分桶）

- 规则集 `status != 'active'` 或 `active_version_id` 为空 → 引擎不参与（返回 nil，不猜）。
- 灰度：`canary_version_id` 存在且 `canary_percent > 0` 时，桶 = `SHA256("<rule_set_id>:<order.prefixed_id>").hex % 100`；
  - 桶 `< canary_percent` → 金丝雀版本，否则稳定版；`canary_percent >= 100` → 恒金丝雀；`0` → 恒稳定版。
  - **稳定性**：同一（规则集, 订单）恒定，跨请求/跨天/重新评估不漂移；桶值进入留痕（可复算证伪）。
- 作用域：全局规则集 + 本店铺规则集都参与；**同 `code` 优先本店铺**（全局为兜底），与名单的「全局 + 本店」口径一致但**优先级相反**（更具体者优先）。

### FR-004 评估与决策合并

- 新服务 `Risk::Rules::Evaluate.call(order:, now:)` → `{rule_set_id:, rule_set_code:, version:, canary:, bucket:, rule_code:, action:, matched_conditions:, skipped:[]}` 或 `nil`（无命中/无生效版本）。
- `Risk::Assess` 在名单判定后合并：**白名单命中 → `allow` 短路（保持切片1 行为不变）**；否则最终决策 = 严重度最大者，严重度 `allow(0) < review(1) < block(2)`，参与者 = 名单动作（`Config[:risk_denylist_action]`，默认 `review`）与规则动作。
- 留痕：`signals['rule_engine']`（含规则集/版本/金丝雀/桶/规则码/动作/命中条件）与 `metadata['rule_engine']`；命中 `review`/`block` 时沿用既有 `risk_order_flagged` 审计与（既有订阅者路径的）人工复核标记。
- **零 provider / 零资金副作用 / 不改订单状态**。

### FR-005 版本发布 / 灰度 / 回滚（服务层）

- `Risk::Rules::Versioning`：
  - `create_draft(rule_set:, rules:, reason:, actor:)` → 校验通过才落 `draft` 版本（版本号 = 当前最大 + 1）。
  - `publish(rule_set:, version:, reason:, actor:)` → 该版本 `published` + 置为 `active_version_id`（旧生效版转 `archived`，并将指向已归档版的**金丝雀清空**）。
  - `set_canary(rule_set:, version:, percent:, actor:)` → 校验 percent 0–100；**金丝雀与稳定版并存**：草稿版本可以金丝雀身份发布（`published`，**不动** `active_version_id`、**不归档他人**）；已归档版本拒绍（要走回滚/新建）；`percent = 0` 关闭。
  - `rollback(rule_set:, to_version:, reason:, actor:)` → 以 `to_version` 的 `rules` **生成新版本**（`rolled_back: true`、`source_version: to_version`、`reason` 必填）并置为 active；**旧版本保持不可变**。
  - `deactivate(rule_set:, actor:)` / `activate`。
- 每次动作写审计：`risk_rule_version_created` / `risk_rule_version_published` / `risk_rule_canary_updated` / `risk_rule_version_rolled_back` / `risk_rule_set_deactivated`；并发布事件 `risk.rule_version_published` / `risk.rule_version_rolled_back`（事件系统未启用只记日志，不阻断）。

### FR-006 后台规则工作台 `/admin/risk_rules`

- `index`：规则集列表（作用域 全局/店铺、状态、生效版本、金丝雀版本+百分比、规则数、最近发布时间）+ 每态计数与列表**同源**。
- `show`：版本历史（版本号/状态/来源版本/是否回滚/发布人/发布时间/原因）+ 生效版本规则表（优先级/规则码/条件摘要/动作）+ 金丝雀状态。
- 动作（均需权限 + confirm + 审计）：新增草稿版本（结构化 JSON 编辑 + 服务端校验 + 错误回显）、发布版本、设置金丝雀、**回滚**（选版本 + 必填原因）、停用/启用。
- `preview`：输入订单 prefixed_id → 展示「生效规则集/版本/是否金丝雀/桶/命中规则/动作/被跳过的原因」，**零写入、零审计**。
- 导航：Orders → `risk_rules`（position 59.5，紧跟「风控名单」59）；权限 `can :manage, PallasTrade::RiskRuleSet`（+ 版本）注册到 `configuration_management`。
- 双语 i18n：gem `en.yml` + 宿主 `zh-CN` 键集一致。

## 4. 非功能需求（NFR）

| 维度 | 要求 |
|---|---|
| 只读性 | 评估路径零写库（**除** `Risk::Assess` 既有留痕）、零 provider、零资金副作用；不改订单/支付状态 |
| 确定性 | 分桶由 `(规则集, 订单)` 唯一决定；同输入同输出（可复算） |
| 安全 | 规则编辑走强参数白名单；规则集/版本跨店隔离（只读本店 + 全局）；无 PII 落在日志与审计（只记规则码/版本/计数） |
| 有界 | 规则数 ≤ 50/版本；评估 O(规则数) 且每条条件的查询有界（velocity/历史各自 ≤ 1 次 COUNT） |
| 兼容 | P8 `Risk.rules` 代码规则与 `Checkout::Preflight` **行为不变**（本切片不改其调用与启用条件）；D15 切片1 名单语义不变 |
| 国际化 | 新增文案双语，键集一致 |

## 5. 验收标准（AC，与测试一一映射）

| AC | 内容 | 测试载体（计划） |
|---|---|---|
| AC-001 | 模型：`(rule_set_id, version)` 唯一；`code` 在全局/每店铺两作用域各自唯一（partial unique）；`published` 版本不可改写 rules | `spec/models/pallastrade/d15b_risk_rule_set_spec.rb` |
| AC-002 | 条件白名单：每个受支持键的正/反例（含边界 = 命中）；缺失主体 → 不命中且记 skip 原因 | `spec/services/pallastrade/risk/d15b_rules_condition_spec.rb` |
| AC-003 | 发布校验：未知键 / 类型错 / 非法动作 / 空条件 / 超 50 条 / priority 非整数 → 拒绝且**不落库** | 同上 + `d15b_versioning_spec.rb` |
| AC-004 | 规则求值：priority 升序首个命中；同优先级按数组序；无命中 → nil | `spec/services/pallastrade/risk/d15b_rules_evaluate_spec.rb` |
| AC-005 | 生效版本选择：inactive/无生效版 → 不参与；店铺版优先于全局版同 code | 同上 |
| AC-006 | 灰度分桶：稳定（重复调用同桶）；percent=0 恒稳定版、100 恒金丝雀；边界（桶 == percent 归稳定版）；桶可复算 | 同上 |
| AC-007 | 决策合并：allowlist 短路优先；名单 review + 规则 block → block；规则 allow + 名单 review → review（最严者胜） | `spec/services/pallastrade/risk/d15b_assess_integration_spec.rb` |
| AC-008 | 留痕：`signals['rule_engine']` 含规则集/版本/金丝雀/桶/规则码/动作/命中条件；命中 review/block 触发既有 `risk_order_flagged` 审计 | 同上 |
| AC-009 | 版本流转：create_draft → publish → set_canary → deactivate；版本号单调；旧生效版转 archived | `spec/services/pallastrade/risk/d15b_versioning_spec.rb` |
| AC-010 | **回滚**（锚点）：以历史版内容生成**新版本**（`rolled_back`/`source_version`/`reason` 留痕）并生效；**源版本内容不被改写**；审计与事件各 1 次 | 同上 |
| AC-011 | 事件：`risk.rule_version_published` / `risk.rule_version_rolled_back` payload 正确；事件系统未启用不报错 | 同上 |
| AC-012 | 后台页：计数与列表同源（`data-count-scope`）；列表/详情渲染版本历史与规则表；无权限拒绝 | `spec/requests/pallastrade/admin/d15b_risk_rules_spec.rb` |
| AC-013 | 后台动作：新增草稿（校验失败回显且不落库）、发布、金丝雀、回滚（原因必填）、停用；各写审计 | 同上 |
| AC-014 | 预览：给定订单显示版本/金丝雀/桶/命中规则/动作/skip 原因，且**零写入**（前后各表计数与行内容全等） | 同上 |
| AC-015 | **零副作用与兼容**：评估前后 orders/payments/disputes/ledger/inventory 与订单状态全等；`Risk.evaluate`/`Checkout::Preflight` 既有 spec 全绿；D15 切片1 名单 spec 全绿 | 集成 spec + 回归 |
| AC-016 | 分桶确定性可复算：跨进程/跨天（不同 `now`）同订单同桶 | 评估 spec（多 now） |

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 搜索（关键词：risk / rule / version / rollout / canary / 灰度） | 结论 |
|---|---|---|
| **App** `backend/app/` | `grep -rn "risk\|blacklist" backend/app` | **零命中**：宿主无风控代码 → 本切片全部落在 gem（Core/Admin） |
| **Core** `pallastrade_gems/pallastrade_core/` | `lib/pallastrade/risk.rb`、`lib/pallastrade/risk/{blacklist_rule,order_frequency_rule}.rb`、`app/services/pallastrade/risk/**`、`app/services/pallastrade/checkout/preflight.rb`、`app/subscribers/pallastrade/risk/order_submitted_subscriber.rb` | **已有**：`PallasTrade::Risk`（代码注册式规则引擎，`Risk.rules` 数组 + `Risk.evaluate` 首个命中 → `{code,message}`）、`BlacklistRule`（`users.blacklisted_at`）、`OrderFrequencyRule`（`preferred_order_frequency_limit` + `Config[:order_frequency_window_minutes]`）、`Checkout::Preflight`（**唯一** `Risk.evaluate` 调用点，flag `preferred_checkout_preflight_enabled` → `Config[:checkout_preflight_enabled]`，默认关闭）、`Risk::Assess`（D15 切片1 唯一入口：名单 → 决策 → 留痕 `Risk::OrderSubmittedSubscriber` 订阅 `order.submitted`）、`Risk::Lists::{Upsert,Export}`；`PaymentRiskAssessment` 有 `signals`/`metadata` **jsonb**（可扩展留痕，**无需迁移**）；**无任何版本/灰度/回滚实现**（`grep rollout\|canary` 命中的全是「flag 灰度」注释语义） |
| **API** `pallastrade_api/app/` | `grep -rn "risk\|preflight"` | 只命中 `order_serializer.rb` 的 `considered_risky` 字段与 CORS 注释 → **无风控端点，本切片零契约变更** |
| **Admin** `pallastrade_admin/app/` | `*-risk*`、`risk_lists_controller.rb`、`orders/_risk_analysis.html.erb`、导航 `initializers/pallastrade_admin_navigation.rb:146` | 已有「风控名单」工作台（D15 切片1，Orders position 59）+ 订单页风控卡；**无规则/版本页面** → 新建 `/admin/risk_rules`（position 59.5），权限与名单同域（`configuration_management`） |
| **Storefront** `storefront/src/` | `grep -rn "risk\|blacklist\|preflight"` | **零命中**：前台不涉风控配置；下单错误码契约本切片不改 |
| **Platform** `platform/packages/` | `grep -rn "risk\|blacklist\|preflight"` | **零命中**：SDK/CLI/Dashboard 无风控面 |

> 关键跨层事实（避免重复造轮子）：
> ① **规则引擎已存在**（P8 `PallasTrade::Risk`）→ 本切片**扩展**它（新增数据驱动规则层 + 版本化/灰度/回滚），**不新建第二套引擎**；
> ② **评估入口已存在**（D15 切片1 `Risk::Assess`）→ 规则结果并入同一决策与留痕，**不新建入口**；
> ③ 留痕表 `PaymentRiskAssessment.metadata/signals` 是 jsonb → 版本/灰度信息**零迁移**写入；
> ④ 下单阻断已由 flag 门控的 `Checkout::Preflight` 负责 → 本切片**不动**其启用条件（不改变下单行为）；
> ⑤ BIN（无列）与设备指纹（无采集）不可得 → 不提供对应条件键。

## 7. 技术影响

| 项 | 内容 |
|---|---|
| 迁移 | `20260917010000_create_pallastrade_risk_rule_sets_and_versions.rb`（2 表 + 唯一索引 3 个（含 2 partial）+ 普通索引） |
| 新模型 | `PallasTrade::RiskRuleSet`、`PallasTrade::RiskRuleVersion`（含版本不可变守卫） |
| 新服务 | `Risk::Rules::Condition`（条件匹配）、`Risk::Rules::Schema`（发布校验/归一）、`Risk::Rules::Evaluate`（生效版本 + 灰度 + 求值）、`Risk::Rules::Versioning`（草稿/发布/金丝雀/回滚/停用 + 审计 + 事件） |
| 修改 | `Risk::Assess`（合并规则决策 + 留痛 signals/metadata）、`configuration_management.rb`（权限）、导航、`routes.rb`、gem `en.yml` |
| 后台 | `Admin::RiskRulesController`（index / show / create_version / publish / canary / rollback / toggle / preview）+ 视图 + helper |
| 契约 | **无**（无 API/v3 端点）→ 仍需 `harness generated:check` 证明零漂移 |
| 事件 | `risk.rule_version_published`、`risk.rule_version_rolled_back` |
| 测试 | 6 个新 spec 文件 + 导航一致性回归 + 既有 `preflight_spec` / D15 名单 spec 回归；注册 verifier `d15b-risk-rules-rspec` |
| 知识同步 | `pallastrade-security`（规则引擎版本/灰度/回滚 + 条件词汇表）、`pallastrade-data-model`（两新表）、`pallastrade-admin`（新页面/权限/导航）、`pallastrade-events-webhooks`（两事件）、`pallastrade-checkout`（Preflight 与引擎的关系：本切片不改其行为）、`AGENTS.md` §6 行、`harness/scenarios/scenarios.json` **GS-166** |
| 业务方案 | §72.2 补「已实施 D15 切片2」+ §78-D15 行回写 |

## 8. 测试计划

| 文件 | 覆盖 |
|---|---|
| `spec/models/pallastrade/d15b_risk_rule_set_spec.rb` | AC-001 |
| `spec/services/pallastrade/risk/d15b_rules_condition_spec.rb` | AC-002（含边界与 skip 原因） |
| `spec/services/pallastrade/risk/d15b_rules_evaluate_spec.rb` | AC-004/005/006/016 |
| `spec/services/pallastrade/risk/d15b_versioning_spec.rb` | AC-003/009/010/011 |
| `spec/services/pallastrade/risk/d15b_assess_integration_spec.rb` | AC-007/008/015 |
| `spec/requests/pallastrade/admin/d15b_risk_rules_spec.rb` | AC-012/013/014 |
| `spec/requests/pallastrade/admin/navigation_consistency_spec.rb`（改） | 导航子项一致性 |
| 回归 | `spec/services/pallastrade/checkout/preflight_spec.rb`、`spec/services/pallastrade/risk/d15_assess_spec.rb`、`spec/requests/pallastrade/admin/d15_risk_lists_spec.rb` |
| verifier | `d15b-risk-rules-rspec`（上述 6 个文件 + 3 个回归 + 导航） |

## 9. 文档同步清单（知识同步门）

- [x] `ai/skills/pallastrade-security/SKILL.md`：「下单风控规则」章节扩为「规则引擎（数据驱动 + 版本化/灰度/回滚）」+ 条件词汇表 + 不可得主体明示
- [x] `ai/skills/pallastrade-data-model/SKILL.md`：两新表
- [x] `ai/skills/pallastrade-admin/SKILL.md`：`/admin/risk_rules` 页面/权限/导航/动作与审计
- [x] `ai/skills/pallastrade-events-webhooks/SKILL.md`：两个新事件
- [x] `ai/skills/pallastrade-checkout/SKILL.md`：Preflight 与规则引擎的关系（本切片不改阻断行为）
- [x] `AGENTS.md` §6：新 verifier 行
- [x] `harness/scenarios/scenarios.json`：GS-166（版本/灰度/回滚的可辩护性），`eval-ai --scenarios` 167/167
- [x] 业务方案 §72.2 / §78-D15 回写
- [x] 接口文档：**不适用**（零契约变更，`generated:check` 自证）

## 9.1 实施记录（2026-09-17）

**交付物**（新增/修改）：

| 层 | 文件 |
|---|---|
| 迁移 | `backend/db/migrate/20260917010000_create_pallastrade_risk_rule_sets_and_versions.rb`（2 表 + 3 唯一索引（含 2 partial）+ 4 普通索引；`schema.rb` 同步） |
| 模型 | `pallastrade_core/app/models/pallastrade/{risk_rule_set,risk_rule_version}.rb` + 工厂 `testing_support/factories/risk_rule_factory.rb` |
| 服务 | `risk/rules/{condition,schema,evaluate,versioning}.rb` |
| 修改 | `risk/assess.rb`（决策合并 + 规则留痕）、`permission_sets/configuration_management.rb`、`backend/config/initializers/pallastrade_permission_registry.rb`（登记 `:risk_rules`） |
| 后台 | `admin/risk_rules_controller.rb` + `views/.../risk_rules/{index,show,preview}.html.erb` + `routes.rb` + 导航（Orders position 59.5） |
| i18n | gem `en.yml` `risk_rules:` 块（109 键）+ 宿主 `admin_risk_rules.zh-CN.yml`（109 键，键集一致） |
| 测试 | `d15b_risk_rule_set_spec` / `d15b_rules_condition_spec` / `d15b_rules_evaluate_spec` / `d15b_versioning_spec` / `d15b_assess_integration_spec` / `admin/d15b_risk_rules_spec` + `navigation_consistency_spec`（改） |

**测试结果**：verifier `d15b-risk-rules-rspec` 合并运行（6 个新 spec + 导航 + `preflight` / `d15_assess` / `d15_risk_lists` 回归）**108 examples, 0 failures**；新增 6 个 spec 共 60 例。

**实施中的关键发现（可复用）**：

1. **多态 `created_by` 不能赋字符串**：`versions.create!(created_by: 'admin')` 会把字符串当类型 → 撞 `PrefixedId#assign_attributes` 报 `undefined method 'has_query_constraints?' for String`。定式：actor 归一在服务层（只有 `ActiveRecord::Base` 才落多态列，`'admin'` / `{type:,id:,label:}` 交给审计）。
2. **工厂的裸关联会找错名字**：`factory :risk_rule_version do rule_set end` 会去找名为 `:rule_set` 的工厂（不存在）→ `KeyError: key not found: "rule_set"`；改为 `rule_set { association(:risk_rule_set) }`。
3. **`let` 惰性求值会坑计数快照**：零副作用用例先取快照时订单还没建（`let` 未求值）→ 基线恒为 0；定式：取快照前先 `order.reload` 强制建单。
4. **条件比较要容错大小写**：`Schema` 已归一（`country_in` 大写 / `email_domain_in` 小写），但 `Condition` 的列表命中仍做了**大小写不敏感**比较，避免运营手写小写时「看着生效、永不命中」。
5. **桶边界语义**：`approaching/breached` 的对照经验（D14 切片3）提醒 —— 灰度边界必须写死「**桶 == percent → 稳定版**」并用可复算断言（本次 spec 用同一哈希公式推出期望桶，不硬编码数字）。
6. **回滚的断言要抓「源版本一字不改」**：先取 `v2.reload.rules` 快照，回滚后比较快照（而不是比较归一化后的期望值 —— `Schema` 会补 `note` 键，直接比值会假阳性）。

**已知限制 / 遗留**：`force_3ds` 动作与 provider 下发（切片3）；可视化规则构建器（本切片为 JSON + 服务端强校验 + 预览）；BIN/设备指纹条件不可得（不提供键）；IP 地理/网段判定不做；规则数上限 50/版本（未做性能工程）。

## 9.2 后续修复记录（2026-09-17，bugfix）

**缺陷**（dev 冒烟发现；纯推理没能暴露的盲区）：FR-005 原文要求「金丝雀目标版本必须已 `published`」，但 `publish` 会把**其它已发布版归档** → 系统里**不存在**「已发布但不生效」的候选版 → `set_canary` 永远被拒，**灰度实际不可达**（功能写了但用不了）。

**修复**（最小面、不改数据模型、零迁移）：
- `Versioning#set_canary`：**金丝雀与稳定版并存** —— 草稿版本以金丝雀身份发布（`published`），**不动 `active_version_id`**、**不归档他人**；已归档版拒绝（提示新建/回滚）；`percent = 0` 关闭。
- `Versioning#publish`：新增 `clear_stale_canary` —— 金丝雀指向**已归档 / 丢失 / 刚成为生效版**的版本时清空（避免灰度与稳定版重复或指向历史版本）。
- `Evaluate#effective_version`：只认**已发布**的金丝雀版；草稿/归档 → **回落稳定版**（不猜）。

**回归**：`d15b_versioning_spec` 15 例 + `d15b_rules_evaluate_spec` 12 例 → verifier **112 examples, 0 failures**；dev 冒烟 **21 OK / 0 FAIL**（含「金丝雀与稳定版并存」「发布后清理过期金丝雀」「归档版不可作金丝雀」「回滚生成新版本且源版本一字不改」）。

**知识同步门结论**（`harness sync-check --id PRD-20260917-payments-d15b-risk-rules`）：

| 资产 | 结论 |
|---|---|
| `ai/skills/pallastrade-security/SKILL.md` | 已更新（金丝雀并存 / 发布清理 / 只认已发布） |
| `ai/skills/pallastrade-data-model/SKILL.md` | 已更新（「已发布 ≠ 生效」；active 与 canary 可并存） |
| `harness/scenarios/scenarios.json` | 已更新（GS-166 增补「金丝雀可达性」mustDo / mustNotDo） |
| `ai/skills/pallastrade-prd/SKILL.md`、`AGENTS.md`、`.github/copilot-instructions.md` | 已评估，无需更新（命令与流程未变） |
| `AGENTS.md` §8 危险操作 | 不适用（本修复未引入新的危险操作） |

## 10. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-09-17 | 初稿（D15 切片2，业务方案 §72.2；`prd new` 查重命中 D15 切片1 PRD 42% → 评审确认为新切片后 `--force` 新建；跨层搜索已完成，见 §6） |
| 2026-09-17 | 实施完成：6 个新 spec（60 例）+ verifier 合并 108 例全绿；迁移 `20260917010000`；GS-166 入库（167/167）；5 个 Skill + `AGENTS.md` §6 + 业务方案 §72.2/§78-D15 回写；状态 → `done`（见 §9.1） |
| 2026-09-17 | 后续修复（单独 bugfix）：**金丝雀在「发布即归档」语义下不可达** —— `set_canary` 改为「金丝雀与稳定版并存」（草稿版可以金丝雀身份发布且不改生效版；归档版拒绍），`publish` 新增「清理指向已归档版的金丝雀」，`Evaluate` 只认已发布的金丝雀版（否则回落稳定版）；FR-005 与对应 Skill 已同步；新增 5 例回归（见 §10 行） |
