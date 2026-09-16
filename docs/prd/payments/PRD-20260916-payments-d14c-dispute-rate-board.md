# PRD-20260916-payments-d14c-dispute-rate-board

| 元数据 | 值 |
|---|---|
| 状态 | done（2026-09-16 实施完成） |
| 创建日期 | 2026-09-16 |
| 来源 | 需求：D14 切片3 拒付率看板与卡组织阈值预警（业务方案 §78-D14 / §71.3 / §72.5） |
| 分类 | payments |
| 关联 Skill | `pallastrade-payments`、`pallastrade-admin`、`pallastrade-data-model`、`pallastrade-events-webhooks`、`pallastrade-testing` |
| 关联 PRD | `PRD-20260916-payments-d14-refund-approval`（切片1：退款审批）、`PRD-20260916-payments-d14b-dispute-deadlines`（切片2：期限分档与超期处置）、`PRD-20260916-payments-d15-risk-lists`（名单能力来源：一键加黑复用） |
| 需求类型 | 新功能（在既有只读争议报表 `Disputes::OpsReport` 之上扩展「比率 + 阈值 + 下钻 + 预警台账」，不改其口径） |

## 1. 背景与目标

业务方案 §71.3 要求「拒付率看板」：**按卡组织阈值预警**（Visa VAMP / Mastercard ECP 类监管项目均为「金额比例 + 笔数比例」**双阈值**），并支持下钻到高风险维度、与 §72 风控名单联动（一键加黑）；§72.5 给出触发线：**拒付率接近卡组织阈值 80% 时预警**。

**今天缺什么**（已核对代码，见 §6）：

1. `Disputes::OpsReport` 只回答「争议侧的运营质量」（胜诉率 / 时限达成 / 处理时长 / 按原因分布 / 金额），**没有分母**——算不出「拒付率」，也没有卡组织维度；
2. 没有任何**阈值配置**与**逼近预警**；卡组织阈值是运营口径，代码里既无注册表也无预警台账；
3. 没有**下钻**（卡 / 国家 / 入口 / 客群）与名单联动入口，运营定位到「某个卡指纹在刷拒付」后只能手工去 `/admin/risk_lists` 加黑。

**目标**

- G1 **可查**：按店铺 + 时间窗给出「按卡组织」的拒付率（笔数比 + 金额比），分母口径唯一、可解释、可下钻。
- G2 **可预警**：双阈值可配；达到阈值 80% 即预警、达到 100% 即超标；**预警不遗漏、不重复**（台账唯一键），恢复一致不产生噪声。
- G3 **可定位**：下钻到卡指纹 / 国家 / 入口 / 客群四个维度，给出「桶内争议数与占比贡献」，并对卡指纹提供**一键加入风控黑名单**（复用 D15 名单能力 + 审计）。
- G4 **零风险**：只读统计（仅写预警台账与审计），零资金副作用、零 provider 调用、不改争议状态。

**非目标**（本切片不做，避免越界）

- 不做 provider（Stripe/Adyen）报文拉取或「卡组织公示阈值自动同步」；
- 不做 **BIN 级**下钻：本仓 `pallastrade_credit_cards` **没有 BIN 列**（只有 `fingerprint` / `cc_type` / `last_digits`），按「不猜」原则以**卡指纹**替代 BIN 维度，并在页面上明示该差异；
- 不做自动处置（不自动加黑、不自动拒付、不自动改争议状态）；
- 不硬编码任何卡组织公示数字（见 FR-003）。

## 2. 用户故事 / 场景

- **US-1（运营早会看板）**：作为支付运营，我要在后台一页看到「最近 30 天各卡组织的拒付率与阈值位置」，以便判断本周是否需要调整风控策略。
- **US-2（逼近阈值预警）**：作为支付运营，我希望拒付率达到阈值 80% 时系统就提醒我（而不是等卡组织罚款函），并留下台账以便回溯「什么时候开始变坏的」。
- **US-3（下钻定位 + 一键加黑）**：作为风控专员，我要看到「哪个卡指纹 / 国家 / 入口 / 客群」贡献了大部分争议，并直接把这些卡指纹加进黑名单，而不必手工复制粘贴。

## 3. 功能需求（FR）

### FR-001 阈值策略（店铺级，唯一口径）

- 存储于 `Store#private_metadata['dispute_rate_policy']`（**无新表**），字段：
  - `enabled`（默认 `true`）：关闭后看板仍展示比率，但**不写台账、不发事件**；
  - `window_days`（默认 **30**，允许 1–365）：比率窗口；非法 → 回默认 30（绝不因配置错误而「无窗口」）；
  - `warning_ratio`（默认 **0.8**，允许 0.5–1.0，对应 §72.5「接近阈值 80%」）：进入 `approaching` 的阈值比例；非法 → 0.8；
  - `networks`：`{ '<卡组织键>' => { 'count_bps' => Integer, 'amount_bps' => Integer } }`（bps = 万分之一，例：`65` = 0.65%）。
    卡组织键与 `CreditCard#cc_type` 归一值**同一套词汇**（`visa` / `master` / `american_express` / `discover` …），不另立第二套命名。
- **未配置**的组织 → 状态 `unconfigured`：**照常展示比率，但不判定、不预警**（不猜阈值）。

### FR-002 比率口径（唯一权威，页面与 CSV 同源）

- **窗口**：`to = 评估时刻`，`from = to - window_days.days`。
- **分子**：`Dispute.for_store(store).where(created_at: 窗口)`（开案时间口径与 `Disputes::OpsReport` 一致），**按卡组织归因**：
  `dispute → payment → source`：当 `source_type == 'PallasTrade::CreditCard'` 且 `cc_type` 非空 → 该品牌；否则归 `unknown`（**不猜**，单独成行展示，且**不参与**任何组织的阈值判定）。
- **分母**：该组织**已完成的卡支付**笔数/金额 —— `Payment.completed`，且 `order_id ∈ store.orders`，且窗口按 `payment.created_at`，且该支付的卡品牌 == 该组织。
  - `order_id` 为空的组合支付（P4）无法归店 → 计入 `unattributed_payments` 计数并明示（**不静默丢**）。
- **金额口径（跨币种不混算）**：金额比只统计**店铺默认币种**；其他币种的支付/争议计入 `excluded_other_currency_*` 计数并在页面/导出明示。
- **比率**：`count_ratio = disputes_count / transactions_count`（分母 0 → `nil`，**不用 0 伪装**）；`amount_ratio = disputes_amount / transactions_amount`（同上）。

### FR-003 状态判定与「不硬编码阈值」

- 判定（仅对**已配置阈值**的组织）：`breached`（任一比率 ≥ 阈值）> `approaching`（任一比率 ≥ `阈值 × warning_ratio`）> `ok`；整体状态取**更严重**者，并给出 `triggered_metrics`（`['count']` / `['amount']` / 两者）。
- 未配置 → `unconfigured`；分母为 0 → 仍按配置判定（比率 `nil` 不触发），并在卡片上标注「窗口内无卡交易」。
- **建议模板**：代码内提供 `SUGGESTED`（含 `source_note` 注明「卡组织公示阈值会调整，落地前需按最新公告复核」），但**默认不生效**；页面「应用建议值」= 显式写入策略（写审计）。

### FR-004 下钻四维度（口径自洽）

- 维度：`card_fingerprint`（卡指纹，脱敏展示）/ `country`（订单账单国家）/ `entry`（支付入口 = `PaymentMethod#effective_payment_option` 的 kind，复用 D16 口径）/ `segment`（客群：窗口开始前该邮箱在本店已有成功支付 → `returning`，否则 `new`）。
- 每个桶给出：交易数、争议数、两比率、**占比贡献**（桶争议数 / 总争议数，桶争议金额 / 总争议金额）。
- **自洽不变量**：桶合计 == 汇总（同一 scope 派生，测试断言）。
- 维度值不可得（空指纹 / 无地址国家 / 入口未知）→ 归入 `unknown` 桶，不丢弃。

### FR-005 预警台账（不遗漏、不重复）

- 表 `pallastrade_dispute_rate_alerts`，唯一键 `dedupe_key = "rate:<store_id>:<network>:<evaluated_on>"`：
  - 只落 `approaching` / `breached`（`ok` / `unconfigured` 不落行，避免噪声）；
  - 同一店铺/组织/评估日**重复评估不新增行**（更新观测值）；
  - **档位升级**（`approaching → breached`）→ 更新同一行 + 记 `escalated_at`（首次进入更高档时间）+ 发事件；**未升级不发事件**。
- 字段：`store_id`、`network`、`tier`(=status)、`window_days`、`evaluated_on`、`count_ratio_bps`、`amount_ratio_bps`、`count_threshold_bps`、`amount_threshold_bps`、`disputes_count`、`transactions_count`、`disputes_amount`、`transactions_amount`、`currency`、`triggered_metrics`(jsonb)、`detected_at`、`escalated_at`、`metadata`。

### FR-006 事件与巡检

- 事件 `dispute.rate_threshold`（仅在**新档位或档位升级**时发布）：载荷 `{ store_id, network, tier, count_ratio_bps, amount_ratio_bps, count_threshold_bps, amount_threshold_bps, triggered_metrics, detected_at }`；事件系统未启用时静默跳过（不阻断巡检）。
- 巡检作业 `Disputes::RateAlertSweeperJob`（`config/sidekiq_schedule.rb` 注册，每小时 `45 * * * *`）：逐店铺评估 → 写台账 → 发事件；**单店失败隔离**（其余店铺继续）+ JSON 指标日志 `{"event":"dispute.rate_alert_sweeper", stores:, evaluated:, recorded:, escalated:, skipped:, failed:}`。

### FR-007 后台看板 `/admin/dispute_rates`

- **阈值设置**：窗口天数、预警比例、各组织双阈值（bps）表单 → 保存写策略 + 审计 `dispute_rate_policy_updated`；非法输入不写库并回显错误；「应用建议值」显式生效（审计同）。
- **组织卡片**：笔数率 / 金额率（`bps` 与百分比双显示）、对应阈值、进度条与状态徽章（`ok` / `approaching` / `breached` / `unconfigured`）、`triggered_metrics` 标注、`data-rate-network` / `data-rate-status` 钩子。
- **下钻表**：维度切换 + 分桶行 + 贡献占比 + 「加入黑名单」按钮（仅卡指纹维度）。
- **预警台账**：最近预警（组织 / 档位 / 时间 / 观测值），支持按组织与档位筛选。
- **重新评估**：`POST reevaluate` 同步跑一次评估并回显结果（审计 `dispute_rates_reevaluated`）。
- **CSV 导出**：汇总 + 下钻 + 台账；**卡指纹脱敏**（`abcd***3456` 形制），**不含任何凭证/PII**（导出写审计 `dispute_rates_exported`）。
- **口径说明区**：显式写出「分子/分母/币种/未知桶/BIN 不可得 → 以卡指纹替代」，杜绝第二种解释。

### FR-008 一键加黑（与 §72 名单联动）

- 卡指纹桶 → `Risk::Lists::Upsert`（`list_type: 'denylist'`、`subject_type: 'card_fingerprint'`、`store:` 当前店铺、`reason` 必填文案、`actor` 当前管理员），复用 D15 能力（**不直接写名单表**）。
- 权限：`can?(:manage, PallasTrade::Dispute)`；失败（如已在名单）→ 友好提示不 500；成功/失败均写审计。

### FR-009 降级与不 500

- `store` 缺失 / 内部异常 → 返回**字段齐全的降级信封**（`degraded: [reason]`，全部数值 `nil`/`0`/空），页面显示「数据不可用」而不是 500（沿用 `Disputes::OpsReport` 范式）。

### FR-010 权限与导航

- 读取：`can?(:read, PallasTrade::Dispute) || can?(:manage, PallasTrade::Order)`（与既有争议页一致）；写动作：`can?(:manage, PallasTrade::Dispute)`。
- 导航：Orders 子项 `dispute_rates`（position **64**，紧随 `fx_snapshots` 63），label `admin.dispute_rates.title`，双语（gem `en.yml` + host `zh-CN`），并同步 `navigation_consistency_spec` 的子项数组。

### FR-011 只读性与零副作用

- 全链路（报表 / 下钻 / 导出 / 巡检 / 重新评估）**不**改支付、订单、退款、账本、库存、争议状态；不调 provider；仅写台账、策略（用户显式保存）与审计。

### FR-012 性能

- 报表查询数**不随行数增长**：批量预加载（disputes 的 payment/source、payments 的 order 维度字段），禁止逐行查询；窗口上限 365 天；下钻桶数上限（如 200）并标注截断。

## 4. 非功能需求（NFR）

| 项 | 要求 |
|---|---|
| 只读与安全 | 零资金副作用、零 provider 调用；页面/CSV 不出现凭证与个人数据；卡指纹一律掩码 |
| 可观测 | 审计动作：`dispute_rate_policy_updated`、`dispute_rate_alert_recorded`、`dispute_rates_reevaluated`、`dispute_rates_exported`、名单联动沿用 D15 审计；巡检 JSON 指标日志 |
| 降级 | 任何异常不得 500（FR-009）；事件发布失败不影响台账写入 |
| 性能 | 报表 p95 < 1s（万级支付量级）；查询数恒定（AC-014 断言） |
| 国际化 | 新增文案双语（gem `en.yml` + host `zh-CN`），键集一致 |
| 兼容 | 不改 `Disputes::OpsReport` 既有输出与语义；不新增 provider 依赖 |

## 5. 验收标准（AC，与测试一一映射）

| AC | 内容 | 测试载体（计划） |
|---|---|---|
| AC-001 | 策略归一化矩阵：窗口/预警比/双阈值非法值保守回默；未配置 → `unconfigured`；`networks` 非 Hash → 空 | `spec/services/pallastrade/disputes/d14c_rate_policy_spec.rb` |
| AC-002 | 比率口径：分子=窗口内争议、分母=窗口内该组织**已完成卡支付**；分母 0 → `nil` | `spec/services/pallastrade/disputes/d14c_rate_report_spec.rb` |
| AC-003 | 卡组织归因：`mastercard`/`maestro` → `master`、`amex` → `american_express`；不可判定 → `unknown` 且不参与判定 | 同上 |
| AC-004 | 跨币种不混算：非默认币种进入 `excluded_other_currency_*` 计数并明示；金额比仅默认币种 | 同上 |
| AC-005 | 状态判定：`ok` / `approaching`（≥80%）/ `breached`（≥100%）/ `unconfigured`；`triggered_metrics` 分别标注 | 同上 |
| AC-006 | 台账幂等：同店/组织/评估日唯一，重复评估不新增行 | `spec/models/pallastrade/d14c_dispute_rate_alert_spec.rb` + 服务 spec |
| AC-007 | 档位升级：`approaching → breached` 更新同行 + `escalated_at`；未升级不发事件 | `spec/services/pallastrade/disputes/d14c_rate_alert_spec.rb` |
| AC-008 | 事件载荷正确（`dispute.rate_threshold`）；事件系统未启用时不报错 | 同上 |
| AC-009 | 巡检作业：多店遍历 + 失败隔离 + 指标计数 | `spec/jobs/pallastrade/disputes/d14c_rate_alert_sweeper_spec.rb` |
| AC-010 | 下钻四维度口径 + 桶合计 == 汇总 + `unknown` 桶保留 | `spec/services/pallastrade/disputes/d14c_rate_report_spec.rb` |
| AC-011 | 卡指纹脱敏（页面/CSV）+ CSV 无凭证/PII | `spec/requests/pallastrade/admin/d14c_dispute_rates_spec.rb` |
| AC-012 | 后台页：计数与列表同源（`data-count-scope`）、组织/状态/窗口筛选、无权限拒绝 | 同上 |
| AC-013 | 阈值保存：非法不写库 + 报错；合法写策略 + 审计；「应用建议值」显式生效 | 同上 |
| AC-014 | **零资金副作用与只读性**：评估前后 payments/orders/refunds/ledger/inventory/争议状态与计数全等；报表查询数不随行数增长 | 服务 spec + 请求 spec |
| AC-015 | 一键加黑：写 D15 名单（denylist/card_fingerprint）+ 审计 + 权限；重复加黑友好不 500 | 请求 spec |

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 搜索（关键词：dispute / 拒付率 / rate / threshold / 看板） | 结论 |
|---|---|---|
| **App** `backend/app/` | `grep -rn "Dispute" backend/app/` | **无命中**：Host App 无争议实现（宿主仅装饰器/订阅者目录，本域零代码） |
| **Core** `pallastrade_gems/pallastrade_core/app/` | `services/pallastrade/disputes/*`、`models/pallastrade/dispute.rb`、`services/pallastrade/risk/*`、`payments/health/metrics.rb` | 已有：`Disputes::OpsReport`（只读运营报表：胜诉率/时限/时长/按原因，**无分母、无阈值**）、`Disputes::DeadlinePolicy`（策略值对象范式）、`Disputes::ScanDeadlines` + `AlertDeadlines`（台账幂等范式）、`Risk::Lists::Upsert`（名单写入，一键加黑复用）、`Payments::Health::Metrics`（窗口聚合范式）；`Dispute` 模型缺 `opened_at`（开案时间取 `created_at`）、**无 BIN 列** |
| **API** `pallastrade_gems/pallastrade_api/app/` | `find ... -ipath '*dispute*'` | **无命中**：v3 Admin/Store 均无 dispute 端点 → 本切片**零契约变更**（`generated:check` 应无漂移） |
| **Admin** `pallastrade_gems/pallastrade_admin/app/` | `disputes_ops_controller.rb`、`views/.../disputes_ops/*` | 已有争议运营页 + D14b 期限看板（`deadline_board_for` 计数与 `deadline_scope_for` 同源范式可复用）；**无拒付率看板** → 新建 `/admin/dispute_rates`，导航 Orders position 64 |
| **Storefront** `storefront/src/` | `grep -rln "dispute" storefront/src` | **无命中**：前台不涉争议运营 |
| **Platform** `platform/packages/` | `grep -rln "dispute" --include=*.ts` | **无命中**：SDK/CLI/Dashboard 无争议面 |

> 关键跨层事实（避免重复造轮子）：① 报表分母必须来自 `Payment.completed`（与 D13c 成本报表同口径：`order_id ∈ store.orders`）；② 卡品牌取自 `CreditCard#cc_type`（归一：`mastercard|maestro → master`、`amex → american_express`）；③ 名单写入必须走 `Risk::Lists::Upsert`（D15 唯一入口）；④ 策略值对象与台账幂等范式直接沿用 `DeadlinePolicy` / `DisputeDeadlineAlert`。

## 7. 技术影响

| 项 | 内容 |
|---|---|
| 迁移 | `20260916260000_create_pallastrade_dispute_rate_alerts.rb`（1 表 + 唯一键 + 2 索引） |
| 新模型 | `PallasTrade::DisputeRateAlert`（TIERS / 展示 helper / `filter_by` / `recent_first` / `for_network`） |
| 新服务 | `Disputes::RatePolicy`（值对象）、`Disputes::RateReport`（只读：汇总 + 下钻 + 降级信封）、`Disputes::RateAlert`（写台账 + 事件） |
| 新作业 | `Disputes::RateAlertSweeperJob` + `config/sidekiq_schedule.rb` 注册（`45 * * * *`） |
| 后台 | `Admin::DisputeRatesController`（index / update_policy / reevaluate / export / add_to_denylist）+ 视图 + 导航（position 64）+ 权限（`can?(:manage, PallasTrade::DisputeRateAlert)`，读写同一权限；一键加黑**另需** `can?(:manage, PallasTrade::PaymentRiskList)`）+ 双语 i18n |
| 契约 | **无**（无 API/v3 端点、无 OpenAPI/SDK 变更）→ 仍需 `harness generated:check` 证明零漂移 |
| 测试 | 6 个新 spec 文件 + 回归（`navigation_consistency_spec` 加子项、`d14b` 争议期限 spec 不受影响）；注册 verifier `d14c-dispute-rates-rspec` |
| 知识同步 | `pallastrade-payments`（看板与阈值章节）、`pallastrade-data-model`（新表）、`pallastrade-admin`（新页面 + 权限 + 导航）、`pallastrade-events-webhooks`（新事件 + 巡检）、`AGENTS.md` §6 行、`harness/scenarios/scenarios.json` **GS-163**（GS-159 已被并行会话占用） |
| 业务方案 | §71.3 与 §78-D14 行补「已实施 D14 切片3」说明 |

## 8. 测试计划

| 文件 | 覆盖 |
|---|---|
| `spec/services/pallastrade/disputes/d14c_rate_policy_spec.rb` | AC-001 |
| `spec/services/pallastrade/disputes/d14c_rate_report_spec.rb` | AC-002/003/004/005/010/014（查询数） |
| `spec/models/pallastrade/d14c_dispute_rate_alert_spec.rb` | AC-006（唯一键/归一化/展示 helper） |
| `spec/services/pallastrade/disputes/d14c_rate_alert_spec.rb` | AC-006/007/008 |
| `spec/jobs/pallastrade/disputes/d14c_rate_alert_sweeper_spec.rb` | AC-009 |
| `spec/requests/pallastrade/admin/d14c_dispute_rates_spec.rb` | AC-011/012/013/015 |
| `spec/requests/pallastrade/admin/navigation_consistency_spec.rb`（改） | 导航子项一致性 |
| verifier | `d14c-dispute-rates-rspec`（上述 6 个文件 + 导航回归） |

## 9. 收口清单

- [x] 迁移与 schema 同步（`db:migrate`）
- [x] 服务/模型/作业实现 + 6 个 spec 全绿
- [x] 后台页（看板/下钻/台账/阈值设置/CSV/一键加黑）+ 导航 + 权限 + 双语 i18n 键集一致
- [x] `harness generated:check` 零漂移
- [x] `navigation_consistency_spec` 子项数组同步
- [x] verifier `d14c-dispute-rates-rspec` 注册（`harness.config.mjs`）+ AGENTS §6 行
- [x] GS-163 入库 + `harness eval-ai --scenarios` 全绿（164/164）
- [x] 4 个 Skill 更新 + 业务方案 §71.3/§78-D14 回写
- [x] PRD 状态 `done` + README 索引 + `prd-status-sync --check`
- [x] `harness sync-check --ack` + `knowledge verify`
- [x] dev 冒烟（比率/状态/台账幂等/升级事件/下钻自洽/脱敏/零副作用/HTTP）
- [x] CI 四项绿 + dev 部署与迁移

## 9.1 实施记录（2026-09-16）

**交付物**（新增/修改，均为本切片）：

| 层 | 文件 |
|---|---|
| 迁移 | `backend/db/migrate/20260916260000_create_pallastrade_dispute_rate_alerts.rb`（`schema.rb` 同步） |
| 模型 | `pallastrade_core/app/models/pallastrade/dispute_rate_alert.rb` + 工厂 `testing_support/factories/dispute_rate_alert_factory.rb` |
| 服务 | `disputes/rate_policy.rb`、`disputes/rate_report.rb`、`disputes/rate_alert.rb` |
| 作业 | `disputes/rate_alert_sweeper_job.rb` + `config/sidekiq_schedule.rb`（`dispute_rate_alert_sweep`） |
| 后台 | `admin/dispute_rates_controller.rb` + `admin/dispute_rates_helper.rb` + `views/.../dispute_rates/index.html.erb` + `config/routes.rb` + `configuration_management.rb` + 导航 `orders_nav` 子项 |
| i18n | gem `en.yml` `dispute_rates:` 块（90 键）+ host `admin_dispute_rates.zh-CN.yml`（90 键，键集一致） |
| 测试 | `d14c_rate_policy_spec` / `d14c_rate_report_spec` / `d14c_dispute_rate_alert_spec` / `d14c_rate_alert_spec` / `d14c_rate_alert_sweeper_spec` / `admin/d14c_dispute_rates_spec` + `navigation_consistency_spec`（改） |

**测试结果**：verifier `d14c-dispute-rates-rspec` 合并运行 **79 examples, 0 failures**（含导航一致性回归 27 例）。

**实施中的关键发现（可复用）**：

1. **`pallastrade_payments` 没有 `currency` 列** —— 币种只能从订单取（`orders.currency`）；因此报表先 `pluck` 支付行，再用订单 map 补币种，**不要**在支付 `.pluck` 里写 `:currency`（会报未知列）。
2. **支付无 store 列** —— 店铺口径只能经由 `order_id ∈ store.orders`（与 D13c 成本报表同口径，直接复用）。
3. **测试造数陷阱**：`create(:order)` 的 email 会被工厂覆盖 → 需 `update_columns(email:)` 后再用；`Payment` 金额被订单总额封顶 → 用 `create(:order_with_line_items, line_items_count: 1, line_items_price: amount, shipment_cost: 0)` 且 `payment_total: 0`。
4. **判定口径只能有一处** —— `RatePolicy.classify` 同时返回 `status` / `triggered_metrics` / bps，报表与台账都调它，避免「页面与台账对不上」。
5. **台账不养噪声**：`ok` / `unconfigured` **不建行**，只刷新已存在的行（`allow_create: false` 分支返回 nil）——否则看板自己会把每个组织每天都写一行。
6. **同日不降档**：当天已是 `breached` 时晚些时候回落只更新观测值 + `relaxed_at`，**不降档、不发事件**（避免运营被反复通知）。
7. **一键加黑不能把原始卡指纹渲染进 HTML** —— 改成「页面只提交掩码 + 服务端在当前窗口下钻结果里唯一反解」，不唯一就拒绝（AC-011 与可用性同时满足）。
8. **脱敏口径只允许一个** —— 复用 D15 `PaymentRiskList#masked_value`（`abcd***3456`）；helper 写成模块函数供控制器调用，视图侧用实例方法 `mask_fingerprint` 包装。
9. **新增控制器必须自带 `audit_actor`**（`BaseController` 不提供；`PaymentRiskList` 是「常量名 + `masked_value`」的既有约定）。
10. **导航一致性 spec 是跨会话冲突高发区**：并行会话会提前把 `:dispute_rates` 写进子项数组，**改前先查、改后验重**。

**已知限制 / 遗留**：提醒**外发渠道**（邮件/IM）未做（本切片只落台账 + 发事件，供后续接入）；**BIN 级**下钻不可得（`pallastrade_credit_cards` 无 BIN 列）→ 以卡指纹替代并在页面明示；`expired` 语义细化为切片2 遗留、不在本切片范围。

**知识同步评估（`harness sync-check`，11 项全部评估，已 `--ack`）**：

| 资产 | 结论 | 说明 |
|---|---|---|
| 领域 Skill | 更新 | `pallastrade-payments` / `pallastrade-admin` / `pallastrade-events-webhooks` 三个领域 Skill 新增章节 |
| pallastrade-data-model Skill | 更新 | 新增 `pallastrade_dispute_rate_alerts` 表章节 |
| scenarios.json / 场景库 | 更新 | 新增 GS-163，`eval-ai --scenarios` 164/164 |
| AGENTS.md | 更新 | §6 新增本切片验证行 |
| SDK 类型(generated:check) | 已评估，无需更新 | 无契约变更，`generated:check` no drift |
| backend/public/api-docs/{store,admin}.yaml | 不适用 | 零 v3 端点变更（PRD §6 跨层搜索结论） |
| pallastrade-api-v3 Skill | 不适用 | 同上 |
| copilot-instructions.md | 已评估，无需更新 | 无新增强制命令/规则 |
| pallastrade-prd Skill | 已评估，无需更新 | PRD 机制未变 |
| 测试 | 已评估，无需更新 | 沿用既有测试范式（唯一键幂等 / 计数与列表同源 / 零副作用断言 / 查询数恒定） |

## 10. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-09-16 | 初稿（D14 切片3，业务方案 §71.3 + §72.5；跨层搜索已完成，见 §6） |
| 2026-09-16 | 实施完成：79 例 spec 全绿 + verifier 注册；GS-163 入库；4 个 Skill + `AGENTS.md` §6 + 业务方案 §71.3/§78-D14 回写；状态 → `done`（见 §9.1） |
