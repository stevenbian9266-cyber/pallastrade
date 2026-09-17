# REQ-20260917-d3-risk-dashboard

| 项 | 值 |
|---|---|
| 关联 PRD | `docs/prd/payments/PRD-20260917-payments-d3-risk-dashboard-threshold-alerts.md` |
| 任务 | `TASK-20260917160640-0c308f56`（需求：D3 风控看板与阈值告警） |
| 风险档 | quick（`risk check` 判定） |
| 类型 | feature |

## 1. 一句话需求

把「risky 数 / 3DS 挑战率 / 拒付率 / 退款率 / 审核队列时长」五个风控水位指标拉到一页（`/admin/payment_risk`），阈值可配、触发告警有留痕且幂等；**零迁移、零契约、零资金副作用**。

## 2. 跨层搜索记录（6 层，命令与结论）

| 层 | 搜索 | 命中 | 结论 |
|---|---|---|---|
| App（宿主） | `backend/app/**` 搜 `dashboard\|rate_report\|RatePolicy\|RateAlert\|challenge_rate\|refund_rate\|threshold\|Metrics\|risk_assessment` | 0 | 宿主零实现，不重复 |
| Core | `pallastrade_core/app/services/pallastrade/{disputes,payments/health,risk}/**` | `rate_policy.rb` / `rate_report.rb` / `rate_alert.rb` / `ops_report.rb` / `deadline_policy.rb` / `payments/health/metrics.rb` / `risk/assess.rb` / `risk/rules/**` / `transactions/review.rb` | 事实层齐备，**缺统一读模型 + 策略 + 判定 + 告警** |
| API | `pallastrade_api/app/**` 搜 `dashboard\|rate\|alert` | 0 | 零 v3 端点变更 |
| Admin | `pallastrade_admin/app/controllers/pallastrade/admin/*` | `dashboard_controller.rb`（首页 analytics，非风控）/ `dispute_rates_controller.rb` / `risk_lists_controller.rb` / `risk_rules_controller.rb`；导航 `orders.add :transactions/:risk_rules/:dispute_rates` | 缺风控聚合页；导航/权限域可沿用 |
| Storefront | `storefront/src/**` 搜 `dashboard\|challenge_rate` | 0 | 后台面，零影响 |
| Platform | `platform/packages/**` 搜 `dashboard\|risk_metric` | 0 | 零契约变更 |

**复用清单（不重造）**
- 拒付率：`PallasTrade::Disputes::RateReport.call(store:, window_days:, from:, to:)`（**只调用**，不复制其 Policy/Alert）
- 风险留痕：`PallasTrade::PaymentRiskAssessment`（`DECISIONS = allow/review/force_3ds/block`、`FLAGGED_DECISIONS`、`evaluated_at`、`filter_by(store:)`）
- 3DS 痕迹：`PaymentSessions` 的 `metadata['three_d_secure_hint'] ∈ {three_d_secure, none}`（D15c 下发时写入）
- 复核队列：`CommerceTransaction`（`state='manual_review'`、`manual_review_at`）+ D2 审计 `transaction_review_{captured,released,failed}`
- 退款/支付金额：`PallasTrade::Refund`（`amount` / `payment` / `commerce_transaction`）、`PallasTrade::Payment`（`completed` + `amount`）
- 策略先例：`Disputes::RatePolicy`（`raw:` 构造 + `MIN/MAX` + `normalize_*` + `for(store)`）、`Payments::ThreeDSecure::Policy`（读 fail-safe / 写拒绝式 + 审计）
- 调度先例：`Disputes::RateAlertSweeperJob`（cron 注册方式）
- 后台先例：`dispute_rates_controller.rb` + 导航 `orders.add` + 策略区块（locale 同域同文件）

## 3. 文件计划（新 / 改）

**新增（Core）**
- `backend/pallastrade_gems/pallastrade_core/app/services/pallastrade/risk/dashboard_policy.rb`
- `backend/pallastrade_gems/pallastrade_core/app/services/pallastrade/risk/dashboard_report.rb`
- `backend/pallastrade_gems/pallastrade_core/app/services/pallastrade/risk/dashboard_threshold.rb`
- `backend/pallastrade_gems/pallastrade_core/app/services/pallastrade/risk/dashboard_alert.rb`
- `backend/pallastrade_gems/pallastrade_core/app/jobs/pallastrade/risk/dashboard_alert_sweeper_job.rb`

**新增（Admin）**
- `backend/pallastrade_gems/pallastrade_admin/app/controllers/pallastrade/admin/payment_risk_controller.rb`
- `backend/pallastrade_gems/pallastrade_admin/app/views/pallastrade/admin/payment_risk/index.html.erb`
- `backend/config/locales/admin_payment_risk.zh-CN.yml`

**修改**
- `backend/pallastrade_gems/pallastrade_admin/config/routes.rb`（显式 `get 'payment_risk'` / `patch 'payment_risk/policy'` / `post 'payment_risk/reevaluate'` —— **不用** `resources`，否则 helper 会复数化成 `admin_payment_risk_index_path`）
- `backend/pallastrade_gems/pallastrade_admin/config/initializers/pallastrade_admin_navigation.rb`（orders 子项 `payment_risk`）
- `backend/pallastrade_gems/pallastrade_admin/config/locales/en.yml`（`admin.payment_risk.*`）
- `backend/config/sidekiq_schedule.rb`（`risk_dashboard_alert_sweep`，每小时 `5 * * * *`）
- `backend/spec/requests/pallastrade/admin/navigation_consistency_spec.rb`（orders 子项数组同步）
- `harness.config.mjs`（verifier `d3-risk-dashboard-rspec`）、`AGENTS.md` §6、`harness/scenarios/scenarios.json`（GS-177）、3 个 Skill、`docs/prd/README.md`

**规格（新增）**
- `backend/spec/services/pallastrade/risk/d3_dashboard_policy_spec.rb`
- `backend/spec/services/pallastrade/risk/d3_dashboard_report_spec.rb`
- `backend/spec/services/pallastrade/risk/d3_dashboard_threshold_spec.rb`
- `backend/spec/services/pallastrade/risk/d3_dashboard_alert_spec.rb`
- `backend/spec/jobs/pallastrade/risk/d3_dashboard_alert_sweeper_job_spec.rb`
- `backend/spec/requests/pallastrade/admin/d3_payment_risk_spec.rb`

## 4. Skill 咨询表（gate `read-skill-*` 强制，须真实结论）

| Skill | 读到的关键约束 | 本切片的遵循方式 |
|---|---|---|
| `pallastrade-customization` | 决策树优先级：能扩既有服务就不新建域；后台扩展优先注入而非覆盖 gem | 复用既有 `Disputes::RateReport` / 策略先例 / 导航扩展点；**不新建事实表、不覆盖 gem 视图** |
| `pallastrade-payments` | §D14c 先例：比率必须「有分母才成立」；不可判定不猜（返回 nil + reason）；阈值事件幂等且同日不降档 | 5 指标全部返回 `available/reason`；告警同日同档位一次、同日不降档 |
| `pallastrade-security` | 风控面只读、零 provider、零资金副作用；跨店隔离必须显式收窄；载荷无 PII | `DashboardReport` 全程 `store` 收窄；事件载荷只含 store/metric/status/value/threshold；无订单号/邮箱/卡信息 |
| `pallastrade-admin` | 新页面三要素（标题/面包屑/图标）+ 导航子项必须同步 `navigation_consistency_spec` + 权限域登记 | 新增 orders 子项 + 控制器 `BaseController` + `model_class` + 权限沿用风控域；同步导航 spec |
| `pallastrade-events-webhooks` | 事件名 `domain.action`、载荷最小化、发事件不得阻断主流程 | 事件名 `payments.risk_dashboard_threshold`；只在档位升级时发；作业内 rescue 不阻断 |
| `pallastrade-testing` | 规格必须环境无关（CI 有种子数据：市场/国家/默认店铺）；金额/汇率/币种类夹具要显式声明 | 指标规格不依赖默认店铺币种/市场；比率夹具用同店同币；时间用 `update_columns` 直写 |

## 5. 验收与证据计划

- **verifier**：`d3-risk-dashboard-rspec`（5 服务/作业 + 1 请求 + 导航一致性 + D14c/D15/D2 回归）→ `evidence run/verify --type test`
- **AC ↔ 测试映射**：PRD §5 的 AC-001..AC-014 逐条在规格中以 `# PRD-20260917-payments-d3-risk-dashboard-threshold-alerts AC-0xx` 同行标注（`harness prd verify --id`）
- **dev 冒烟**：`tmp-toy/d3_dev_smoke.rb`（事务包裹 + 回滚）→ 5 指标复算一致 + 告警一次 + 重复不重复 + 双店隔离 + 零副作用；HTTP `/admin/payment_risk` 302
- **知识同步**：`sync-check --id PRD-…` → 逐项 `knowledge assess` → `--ack`（payments / security / admin Skill + AGENTS §6 + scenarios GS-177）
- **恢复计划**：`recovery create`（若 risk 为 critical）—— 本切片改动路径含 `backend/**`+`harness/**`，按 quick 处理，必要时补

## 6. 风险与回滚

| 风险 | 等级 | 缓解 |
|---|---|---|
| 指标口径与 D14c 不一致（同一"拒付率"两个数） | 中 | **直接调用** `Disputes::RateReport`，不重算；页面注明数据来源 |
| 3DS 挑战率分子依赖会话 metadata（历史数据可能缺失） | 中 | 口径写死为「已下发 hint 的会话」；无数据 → `nil`（不猜），页面显示「不可判定」 |
| 聚合查询在大数据量下变慢 | 中 | 只用 `count/sum` + 时间范围；规格断言「查询数不随行数增长」；不新增索引（依赖既有 `created_at`/`evaluated_at`） |
| 告警刷屏 | 低 | 同店同指标同档位同日一次 + 同日不降档 |
| 后台新增页面打破他人整页文本断言 | 低 | 规格用 `data-testid` / 组件作用域断言（不整页 `include`） |
| 与并行会话共享文件冲突 | 中 | `harness.config.mjs` / `scenarios.json` / `AGENTS.md` / Skill：提交前核对差异仅含本切片内容；冲突时按既有惯例（pathspec + 记录） |

**回滚**：`git revert <本批提交>`；零迁移 → 无数据回滚；策略键残留无副作用（未配置即默认）。
