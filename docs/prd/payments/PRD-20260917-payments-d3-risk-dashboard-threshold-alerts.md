# PRD-20260917-payments-d3-risk-dashboard-threshold-alerts

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-17 |
| 来源 | 需求：D3 风控看板与阈值告警（risky 数 / 3DS 挑战率 / 拒付率 / 退款率 / 审核队列时长） |
| 分类 | payments（自动判定） |
| 关联 Skill | `pallastrade-payments` / `pallastrade-security` / `pallastrade-admin` / `pallastrade-events-webhooks` |
| 关联 REQ | REQ-20260917-d3-risk-dashboard.md |
| 关联 PRD | 依赖 D2（`PRD-20260917-payments-d2-…`，已完成）；复用 D14c（`PRD-20260916-payments-d14c-dispute-rate-board`）的 `Disputes::Rate*`；D11 健康页不并入本切片 |
| 需求类型 | 新功能 |

---

## 1. 背景与目标

- **一句话需求原文**：`需求：D3 风控看板与阈值告警（risky 数 / 3DS 挑战率 / 拒付率 / 退款率 / 审核队列时长）`
- **业务方案依据**：§78-D3 行（验收锚点：**指标可查、阈值可配、触发告警**；依赖 D2）；§60.2-P3（风控运营阶段）；§72.5（「接近卡组织阈值 80% 时预警」的既有先例）；§63.2 交易排障台（只读一页看全）。
- **现状（跨层搜索结论见 §6）**：
  - **已有**：D14c 拒付率看板 `Disputes::{RatePolicy,RateReport,RateAlert}` + `pallastrade_dispute_rate_alerts` 台账 + `/admin/dispute_rates`；D15 风险评估留痕 `PaymentRiskAssessment`（`DECISIONS = allow/review/force_3ds/block`，`evaluated_at`）；D15c 认证需求与 provider 下发（会话 metadata 记 `three_d_secure_hint`，取值 `three_d_secure` / `none`）；D2 人工裁决（`Transactions::Review`，`manual_review_at` + 审计 `transaction_review_{captured,released,failed}`）；D13 资金账本/对账、`Refund`（`amount` / `payment` / `commerce_transaction`）。
  - **缺**：把「风控运营关切」的 5 个指标**拉到一页**的只读看板 + **阈值可配** + **触发告警**；拒付率已有专页（本切片**不重算**，只聚合跳转）。
- **目标**：运营在一页内回答「现在的风控水位健康吗、哪一项逼近阈值、该去哪个专页处理」，且阈值告警**有留痕、可追溯、幂等**；全程**只读**（除策略保存与审计）。

---

## 2. 用户故事 / 场景

| # | 角色 | 故事 |
|---|---|---|
| U1 | 风控/运营 | 打开 `/admin/payment_risk` 一页看到 5 个指标（值 + 档位 + 阈值 + 窗口），点击可下钻到专页处理 |
| U2 | 风控负责人 | 为每项指标配置 `warning` / `critical` 阈值与窗口天数；配置非法值被拒绝且说明原因 |
| U3 | 值班同学 | 某项指标突破阈值时收到事件/留痕（谁在何时、哪项指标、值多少、超了哪个阈值），且**同一天同档位不重复刷屏** |
| U4 | 审计 | 指标口径可复算（每个字段能追到源表/源服务），且**不可判定时不猜**（显示「不可判定」而不是 0） |

---

## 3. 功能需求（FR）

### FR-001 策略（`Risk::DashboardPolicy`，唯一读写口径）
- 栖于 `Store#private_metadata['payment_risk_dashboard_policy']`（与 `dispute_rate_policy` / `three_d_secure_policy` 同先例，**零迁移**）。
- 字段：`window_days`（默认 30，范围 1..365）+ 每指标 `{ enabled, warning, critical }`；指标键固定 5 个：`risky_orders` / `three_ds_challenge_rate` / `dispute_rate` / `refund_rate` / `review_queue_duration`。
- **两条路径语义不同**（沿用 D15c 先例）：`normalize`（读）**永不抛错**，非法值回落默认并记 `reasons`；`storable`（写）非法值返回 `errors` **不落库**（未知指标键 / 负值 / warning ≥ critical / 比率 > 10000bps / 时长 ≤ 0）。
- 保存写审计 `store_payment_risk_dashboard_policy_updated`（前后值 + 操作人）。

### FR-002 指标读模型（`Risk::DashboardReport`，只读、零 provider、零写库）
`call(store:, window_days: nil, now: Time.current)` → `success({ scope:, policy:, metrics: [...], evaluated_at: })`，每项 `{ key, value:, unit:, available:, reason:, window:, sources: }`：

| 指标 | 口径（写死，可复算） | 不可判定 |
|---|---|---|
| `risky_orders` | 窗口内 `PaymentRiskAssessment` 中 `decision ∈ FLAGGED_DECISIONS` 的**去重订单数** ÷ 窗口内下单数（`orders.submitted_at`） | 分母 0 → `value: nil, reason: 'no_denominator'` |
| `three_ds_challenge_rate` | 窗口内 `payment_sessions.metadata['three_d_secure_hint'] == 'three_d_secure'` 的会话数 ÷ 窗口内会话数 | 无会话 → `nil` + `no_denominator` |
| `dispute_rate` | **复用** `Disputes::RateReport`（不重算；取其实付口径中的**笔数比**） | RateReport 降级 → 透传 `reason` |
| `refund_rate` | 窗口内 `Refund.amount` 之和 ÷ 窗口内 `completed` 支付金额之和（跨店隔离：经 payment/txn → store） | 分母 0 → `nil` + `no_denominator` |
| `review_queue_duration` | `{ oldest_pending_minutes, p90_handled_minutes, pending_count }`：`state = 'manual_review'` 的 `now - manual_review_at` 最大值；已处理样本取窗口内裁决审计时间 − `manual_review_at` 的 P90 | 无 pending 且无样本 → `nil` + `no_data` |

- 比率一律以 **bps**（万分比）表达（与 D14c 同单位，便于阈值配置与对比），展示层再转百分比。

### FR-003 阈值判定（`Risk::DashboardThreshold#classify`，纯函数、只读）
- 每指标输出 `{ key, status, value, threshold:, direction: }`，`status ∈ ok | approaching | breached | unconfigured`。
- `approaching` 定义 = 达到 `warning`（含）未达 `critical`；`breached` = 达到 `critical`；未启用/未配置 → `unconfigured`（**不判定**，不猜）；`value == nil` → `unavailable`（不判定）。
- 方向：比率与时长均「越高越坏」（`higher_is_worse`），预留 `direction` 字段但本切片只实现该方向。

### FR-004 告警与留痕（`Risk::DashboardAlertSweeperJob`）
- 定时（每小时，`0 * * * *`）对**所有有配置的店铺**评估；逐店隔离失败（单店异常不影响其它店）。
- 档位**升级**（`ok/approaching → breached`，或首次进入 `approaching`）时写审计 `payment_risk_dashboard_threshold`（`before/after` + 指标 + 值 + 阈值 + 窗口），并发事件 `payments.risk_dashboard_threshold`（载荷：`store_id` / `metric` / `status` / `value` / `threshold` / `evaluated_at`，**无 PII、无订单号**）。
- **幂等**：同店 + 同指标 + 同档位 + 同评估日只发一次（以审计行为幂等键；同日不降档）。
- 台账：**本切片不新建表**（理由见 §7）——审计行即留痕，页面「最近评估/最近告警」从审计读取。

### FR-005 后台页面（`/admin/payment_risk`）
- Orders 子项（紧跟 `dispute_rates`），`BaseController` + 既有风控权限域；页面含：5 张指标卡（值/单位/档位徽章/阈值/窗口/最近评估时间 + 下钻链接）、策略区块（窗口 + 5 指标开关与阈值）、最近告警留痕表。
- 下钻链接：`risky_orders` → `/admin/risk_rules`（或订单列表）、`three_ds_challenge_rate` → 门店 3DS 策略区块、`dispute_rate` → `/admin/dispute_rates`、`refund_rate` → `/admin/refunds_ops`、`review_queue_duration` → `/admin/transactions`（`manual_review` 筛选）。
- i18n：新增键写入既有 `pallastrade.admin.payment_risk.*`（gem `en.yml` + 宿主 `config/locales/admin_payment_risk.zh-CN.yml`，en↔zh-CN 键集相等）。

### FR-006 铁律
- 指标/判定/告警链路**零写库**（除策略保存与审计）、**零 provider I/O**、**零资金副作用**；不改任何资金/订单状态。
- **跨店隔离**：所有聚合都以 `store` 收窄；找不到店铺 → 降级 envelope（`store_missing`），不返回他店数据。
- **查询数不随数据量线性增长**：聚合一律用 SQL `count/sum` + 少量分组查询（不做逐行 Ruby 计算）。

---

## 4. 非功能需求（NFR）

| # | 要求 |
|---|---|
| NFR-1 | 看板首屏查询数（含策略/指标/告警）固定 ≤ 12 条，不随订单量增长 |
| NFR-2 | 指标聚合单店单窗口 P95 < 800ms（30 天窗口、百万级支付）/ 无索引缺失（新增查询必须走既有索引或仅用 `created_at`/`evaluated_at` 范围） |
| NFR-3 | 政策读取 fail-safe（坏配置不 500）；策略保存拒绝式（非法值不落库） |
| NFR-4 | 告警作业幂等、可重入、逐店隔离；不因单店异常中断全局 |
| NFR-5 | 零迁移、零 v3 契约变更（admin engine 内部页面） |

---

## 5. 验收标准（AC，与测试一一映射）

| AC | ← FR | 判定条件（可验证） |
|---|---|---|
| AC-001 | FR-001 | 未配置店铺 → 返回默认策略（window 30、5 指标默认阈值、`enabled` 默认策略），零异常 |
| AC-002 | FR-001 | 非法写入被拒且不落库（未知指标键 / 负值 / warning ≥ critical / 比率 > 10000bps / 时长 ≤ 0），返回字段级 errors |
| AC-003 | FR-001 | 合法保存落库 + 审计 `store_payment_risk_dashboard_policy_updated`（含前后值）；键集与读回一致 |
| AC-004 | FR-002 | 5 指标口径逐项可复算（构造夹具 → 断言精确值与单位 bps / minutes / count） |
| AC-005 | FR-002 | 不可判定不猜：分母 0 / 无会话 / 无样本 → `value: nil` + `available: false` + 结构化 `reason`（不是 0） |
| AC-006 | FR-002 | 跨店隔离：他店数据不计入（双店夹具：本店指标不受他店影响） |
| AC-007 | FR-002 | 查询数不随行数增长（N 行与 10N 行查询数相同） |
| AC-008 | FR-003 | 判定矩阵：`ok` / `approaching`（= warning）/ `breached`（= critical）/ `unconfigured`（未配置）/ `unavailable`（值 nil）逐分支断言 |
| AC-009 | FR-004 | 档位升级 → 恰一条审计 + 一次事件（载荷无 PII：不含订单号/邮箱/卡信息） |
| AC-010 | FR-004 | 幂等：同店同指标同档位同日重复评估 → **不**新增审计/事件；同日不降档；跨店隔离（他店配置不影响本店） |
| AC-011 | FR-005 | 页面渲染 5 卡 + 阈值 + 档位徽章 + 下钻链接 + 策略区块 + 最近告警；非 Orders 权限 → 拒绝且零写入 |
| AC-012 | FR-006 | 零副作用：跑一遍指标/判定/作业后，订单/支付/退款/交易状态与金额零变化；零 provider 调用 |
| AC-013 | NFR | dev 冒烟：构造夹具 → 指标数值与手工复算一致 → 触发告警留痕一次 → 重复跑不重复；HTTP 探活 |
| AC-014 | NFR | 回归：D14c 拒付率专页、D15 名单/规则页、D2 排障台与导航一致性 spec 全绿 |

---

## 6. 跨层搜索记录（6 层，gate 强制）

关键词：`dashboard` / `rate_report` / `RatePolicy` / `RateAlert` / `challenge_rate` / `refund_rate` / `threshold` / `risk_assessment` / `manual_review`

| 层 | 路径 | 找到的文件 | 是否满足需求 |
|---|---|---|---|
| App（宿主） | `backend/app/` | 0 命中（`pattern: dashboard|rate|threshold|risk_assessment`） | ❌ 零命中 |
| Core | `pallastrade_gems/pallastrade_core/app/` | `services/pallastrade/disputes/{rate_policy,rate_report,rate_alert,ops_report,deadline_policy}.rb`、`services/pallastrade/payments/health/metrics.rb`、`services/pallastrade/risk/{assess,rules/**}.rb`、`models/pallastrade/{payment_risk_assessment,commerce_transaction,refund,payment_session}.rb`、`services/pallastrade/transactions/review.rb`（D2） | ⚠️ 部分（5 个指标各自的**原始事实**都在，**缺统一看板 + 策略 + 阈值判定 + 告警**） |
| API | `pallastrade_gems/pallastrade_api/app/` | 0 命中（本切片零 v3 端点） | ✅ 无影响 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | `controllers/…/dashboard_controller.rb`（首页 analytics，**非风控**）、`dispute_rates_controller.rb`（D14c 专页）、`risk_lists_controller.rb`、`risk_rules_controller.rb`、`config/initializers/pallastrade_admin_navigation.rb`（orders 子项 `transactions` / `risk_rules` / `dispute_rates`） | ⚠️ 部分（**缺风控聚合页**；导航与权限域可沿用） |
| Storefront | `storefront/src/` | 0 命中 | ✅ 无影响（后台面） |
| Platform | `platform/packages/` | 0 命中 | ✅ 无影响（零契约变更） |

**结论**：**无重复实现风险** —— 5 个指标的事实层（风险评估留痕 / 3DS 下发痕迹 / 拒付率专报 / 退款与支付金额 / 复核队列时间）全部已存在；本切片只新增「**统一读模型 + 策略 + 判定 + 告警 + 一页呈现**」，**不重算拒付率、不新建事实表、零迁移**。

**防重复判定（AP-SEARCH-1/2/3 兜底）**：D14c 的 `Disputes::RatePolicy/RateReport/RateAlert` 是**拒付率专用**（卡组织阈值 + 台账 + 下钻四维）；本切片**只调用其 Report**，不复制其 Policy/Alert（两者关注对象不同：卡组织维度 vs 店铺风控水位）。

---

## 7. 技术影响

| 层 | 文件（新/改） | 说明 |
|---|---|---|
| Core（新） | `services/pallastrade/risk/dashboard_policy.rb` | 策略归一（读 fail-safe / 写拒绝式）+ 审计 |
| Core（新） | `services/pallastrade/risk/dashboard_report.rb` | 5 指标只读读模型（复用 `Disputes::RateReport`） |
| Core（新） | `services/pallastrade/risk/dashboard_threshold.rb` | 纯函数判定（ok/approaching/breached/unconfigured/unavailable） |
| Core（新） | `services/pallastrade/risk/dashboard_alert.rb` + `jobs/pallastrade/risk/dashboard_alert_sweeper_job.rb` | 档位升级 → 审计 + 事件（幂等、逐店隔离） |
| Core（改） | `config/schedule.yml`（或 sidekiq cron 注册处） | 每小时调度（沿用 D14c `RateAlertSweeperJob` 的注册方式） |
| Admin（新/改） | `controllers/…/payment_risk_controller.rb`（index + policy 保存动作）、`views/…/payment_risk/index.html.erb`、导航 orders 子项、gem `en.yml` + 宿主 `config/locales/admin_payment_risk.zh-CN.yml` | 看板 + 策略区块 + 最近告警；权限沿用风控域 + 导航一致性 spec 同步 |
| 契约 | — | **零变更**（admin engine 内部只读页；无 v3 API、无 Typelizer 生成物影响） |
| 数据库 | **零迁移** | 复用 `payment_risk_assessments` / `payment_sessions` / `refunds` / `payments` / `commerce_transactions` / `audit_logs` / `stores.private_metadata` |
| 事件 | 新增 `payments.risk_dashboard_threshold`（只发不收） | 与既有事件命名一致；订阅者可选（本切片不新增订阅者） |

**不建台账表的理由**：D14c 建 `dispute_rate_alerts` 是因为它需要**按卡组织 + 评估日的多行状态机**（approaching/breached + 自动销案 + 下钻）；本切片是**店铺级单值水位**，用「审计行（唯一幂等键 + 前后值）」即可满足「可查、可追溯、幂等」，避免为聚合面再造一张表（KISS + 零迁移）。

**影响面**：`harness affected` 见 REQ；重点回归 = D14c 拒付率专页、D15 名单/规则页、D2 排障台、导航一致性。

---

## 8. 测试计划

| 层 | 文件 | 覆盖 |
|---|---|---|
| 服务 | `spec/services/pallastrade/risk/d3_dashboard_policy_spec.rb` | AC-001/002/003 |
| 服务 | `spec/services/pallastrade/risk/d3_dashboard_report_spec.rb` | AC-004/005/006/007 |
| 服务 | `spec/services/pallastrade/risk/d3_dashboard_threshold_spec.rb` | AC-008 |
| 服务/作业 | `spec/services/pallastrade/risk/d3_dashboard_alert_spec.rb` + `spec/jobs/pallastrade/risk/d3_dashboard_alert_sweeper_job_spec.rb` | AC-009/010/012 |
| 请求 | `spec/requests/pallastrade/admin/d3_payment_risk_spec.rb` | AC-011（含权限拒绝零写入） |
| 回归 | `d14c-dispute-rates-rspec` 既有 spec、`d15-risk-lists-rspec` / `d15b-risk-rules-rspec`、`d2-manual-review-rspec`、`navigation_consistency_spec` | AC-014 |

**验证器**：新增 `d3-risk-dashboard-rspec`（上述集合）。
**实测**：`d3-risk-dashboard-rspec` = **144 例 0 失败**（D3 本体 81 例 + D14c/D8/D2 回归 63 例）；`admin-i18n-rspec` = 212 例 0 失败（新增 `admin_payment_risk.zh-CN.yml` 键集相等）。
**dev 冒烟**：`tmp-toy/d3_dev_smoke.rb`（事务包裹 + 回滚）—— 造夹具 → 断言 5 指标与手工复算一致 → 触发一次告警留痕 → 重复跑不重复 → 双店隔离 → HTTP 探活 `/admin/payment_risk`。

---

## 9. 文档同步清单（知识同步门）

- [x] `ai/skills/pallastrade-payments/SKILL.md`：D3 看板（5 指标口径 + 阈值判定 + 告警幂等）
- [x] `ai/skills/pallastrade-security/SKILL.md`：风控水位与档位语义（「把不知道当一等公民」）
- [x] `ai/skills/pallastrade-admin/SKILL.md`：`/admin/payment_risk` 页面接线（导航/权限/策略区块/路由写法坑）
- [x] `AGENTS.md` §6：`d3-risk-dashboard-rspec` 行
- [x] `harness/scenarios/scenarios.json`：GS-177「A dashboard must be able to say I do not know」→ `eval-ai --scenarios` 178/178 全绿
- [x] `docs/prd/README.md` 索引（`prd-status-sync --fix`）
- [x] 业务方案 §78-D3 / §60.2-P3 / §72.5 回写（本次未改业务方案源文档；口径已写入 3 个 Skill + 本 PRD）
- [x] 接口文档：**不适用**（零 v3 契约；`generated:check` 自证零漂移）

## 10. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-09-17 | 初稿（D3；业务方案 §78-D3 / §60.2-P3 / §72.5；复用 D14c 的 `RateReport`、D15 留痕、D15c 3DS 痕迹、D2 复核审计；零迁移、零契约、不建台账的理由见 §7） |
| 2026-09-17 | 实施完成：`Risk::Dashboard{Policy,Report,Threshold,Alert}` + `DashboardAlertSweeperJob` + 后台 `/admin/payment_risk`（5 卡 + 策略表单 + 告警历史 + 立即评估）+ 双语键 + 规格 81 例 + 回归 63 例（合计 144 例 0 失败）；实现期修正：路由改显式 `get/patch/post`（`resources` 会复数化 helper）、`drill_down_path` 退款链接改 `admin_refunds_path`、委派抽出 `rate_report` 接缝（`ServiceModule::Base` 单例 `call` 不可 stub）；verifier `d3-risk-dashboard-rspec` 注册；状态 → done |
| 2026-09-17 | **CI 修复（Backend CI 3165 例中本切片 1 例红 → 已修）**：`AC-007 查询数不随行数增长` 在 CI 红（本地绿）。根因两条：① `handled_durations` 旧写法「先查审计 → 再按 id 查交易起点」在**空集**时被 Rails 的 `where(id: [])` **短路**掉第二条查询 → 空库 12 条 / 有数据 13 条（CI 有种子数据即红）；② 同处**跨店缺陷**：裁决审计查询未按店收窄（`pallastrade_audit_logs` 无 `store_id`），别店的 `transaction_review_*` 会被算进本店队列 P90。修法＝**改为单条 JOIN SQL**（`JOIN pallastrade_commerce_transactions` 一步完成「按店收窄 + 形状恒定」，时长在 Ruby 侧算，总查询数 14 → 13）；新增两条守护用例（空库 vs 有数据查询数相等 / 别店裁决审计不入本店 `handled_samples` 与 P90）；SPEC 实测 16 例 0 失败（`EMPTY(13) == FULL(13)`） |
