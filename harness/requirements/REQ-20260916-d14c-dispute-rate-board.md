# REQ-20260916-d14c-dispute-rate-board

> 任务：`TASK-20260916132157-f20baf78`
> Gate：`GATE-2026-09-16T13-22-11`
> PRD：`docs/prd/payments/PRD-20260916-payments-d14c-dispute-rate-board.md`
> 类型：feature（新功能，D14 切片3）
> 业务方案依据：§71.3（拒付率看板：卡组织阈值预警 + 下钻 + 名单联动）、§72.5（拒付率接近阈值 80% 预警）；§78-D14 验收锚点「拒付率逼近阈值可预警」

## 1. 需求摘要

在既有**只读争议运营报表**（`Disputes::OpsReport`，只看争议侧质量）之上，补齐「**拒付率**」这一运营核心指标：按卡组织的**双阈值**（笔数比 + 金额比）比率 → 阈值可配（默认不硬编码任何卡组织公示数字）→ 达到 80% 预警、100% 超标 → 预警台账**不遗漏不重复**（唯一键 + 档位升级才发事件）→ 后台一页可查可下钻（卡指纹/国家/入口/客群）+ 卡指纹**一键加入风控黑名单**（复用 D15 `Risk::Lists::Upsert`）。全链路**只读统计**：零资金副作用、零 provider 调用、不改争议状态。

## 2. 新建 vs 修改判据

- **新建（6 层搜索确认缺失）**：`DisputeRateAlert` 模型 + 1 表、`Disputes::{RatePolicy,RateReport,RateAlert}` 三服务、`RateAlertSweeperJob`、后台 `/admin/dispute_rates`（含下钻/台账/阈值设置/CSV/一键加黑）。
- **修改已有（复用，不重复造）**：
  - `Disputes::OpsReport` 的**降级信封**范式（异常不 500）；
  - `Disputes::DeadlinePolicy` 的**策略值对象 + 保守归一化**范式；
  - `DisputeDeadlineAlert` 的**台账唯一键幂等**范式；
  - `Risk::Lists::Upsert`（D15）作为一键加黑的**唯一写入口**；
  - 导航 `pallastrade_admin_navigation.rb`（Orders position 64）、`navigation_consistency_spec` 子项数组、`sidekiq_schedule.rb`、`ability`（读=争议/订单，写=争议 manage）。
- **明确不改**：`Disputes::OpsReport` 既有输出与语义；`Dispute` 模型状态机；任何 provider 代码。

## 3. 跨层搜索结果（Step 0，6 层，逐层独立）

| 层 | 路径 | 关键词 | 结论 |
|---|---|---|---|
| App | `backend/app/` | Dispute | 0 命中（宿主无争议实现） |
| Core | `.../pallastrade_core/app/` | dispute / rate / threshold / 看板 | `Disputes::OpsReport`（胜诉率/时限/时长/**无分母无阈值**）、`DeadlinePolicy`（策略范式）、`ScanDeadlines`+`AlertDeadlines`（台账范式）、`Risk::Lists::Upsert`（名单写入）、`Payments::Health::Metrics`（窗口聚合范式）；`Dispute` **无 `opened_at`（取 `created_at`）**、**无 BIN 列** |
| API | `.../pallastrade_api/app/` | dispute | 0 命中 → **零契约变更** |
| Admin | `.../pallastrade_admin/app/` | dispute | `disputes_ops_controller.rb` + 视图（D14b 期限看板，`deadline_board_for` 计数同源范式可复用）；无拒付率看板 |
| Storefront | `storefront/src/` | dispute | 0 命中 |
| Platform | `platform/packages/` | dispute | 0 命中 |

**避免的反模式**：AP-SEARCH-1（未止步于 `Dispute` 模型，六层搜完）；AP-SEARCH-2（按「拒付率/阈值/看板」域概念搜索而非类名）；AP-SEARCH-3（未假设 API/前台已有对应能力）。

## 4. Skill Consultation Evidence Table（每格真实结论）

| Skill | 读取结论（对本任务的实际约束） |
|---|---|
| `pallastrade-customization` | 决策树优先级：本切片全部走 **1–4 级**（Settings/策略 metadata + Admin 扩展 + 复用既有服务），**不改 Gem 已有视图语义**，不新增 provider 依赖；新页面为净新增模块（`backend/app/views/` 无需介入，落在 gem admin 视图）。 |
| `pallastrade-payments` | 支付事实口径：分母用 `Payment.completed` + `order_id ∈ store.orders`（与 D13c 成本报表同口径）；卡品牌取自 `CreditCard#cc_type`（归一 `mastercard|maestro → master`、`amex → american_express`）；组合支付 `order_id` 可空 → 归 `unattributed` 计数而不静默丢弃；**零资金副作用**是支付域铁律。 |
| `pallastrade-data-model` | 新表命名 `pallastrade_dispute_rate_alerts`；比率用 bps 整数（避免浮点漂移）；观察值金额 decimal(12,2)；`triggered_metrics`/`metadata` 用 jsonb；只新增表不回填；不手改 `schema.rb`。 |
| `pallastrade-admin` | 后台范式：`BaseController` + 自定义 `audit_actor`；筛选用 `filter_by` 且**计数与列表同源**（`data-count-scope`）；`::CSV.generate`（命名空间陷阱）；导航新子项必须同步 `navigation_consistency_spec`；危险动作（加黑）要 confirm + 权限 + 审计。 |
| `pallastrade-events-webhooks` | 新事件 `dispute.rate_threshold` 只在**档位变化**时发布；发布失败只日志（不阻断台账写入）；巡检作业结构化 JSON 指标日志；`sidekiq_schedule.rb` 注册（每小时 `45 * * * *`）。 |
| `pallastrade-security` | 页面/CSV 不得出现凭证或 PII；卡指纹一律掩码（`abcd***3456` 形制）；两档权限（读=争议/订单、写=争议 manage）；导出写审计。 |
| `pallastrade-testing` | 每能力必须有 rspec（model/service/job/request）；**负向断言必须显式**（零资金副作用前后全等、桶合计==汇总、未配置不预警、跨币种不混算、查询数不随行数增长）。 |
| `pallastrade-i18n` | gem `en.yml` 与 host `zh-CN` 同步键集（键集一致性可断言）。 |
| `pallastrade-prd` | 一句话需求 → PRD（payments 分类，查重通过）→ **用户确认** → gate + REQ → AC↔测试映射（标记 `# PRD-… AC-0xx`）→ 知识同步门 `sync-check --ack`。 |

## 5. 交付物清单

| # | 类型 | 路径 | 状态 |
|---|---|---|---|
| 1 | 迁移 | `backend/db/migrate/20260916260000_create_pallastrade_dispute_rate_alerts.rb` | 待实施 |
| 2 | 模型 | `.../pallastrade_core/app/models/pallastrade/dispute_rate_alert.rb` | 待实施 |
| 3 | 服务 | `.../app/services/pallastrade/disputes/rate_policy.rb`（值对象） | 待实施 |
| 4 | 服务 | `.../app/services/pallastrade/disputes/rate_report.rb`（只读：汇总 + 下钻 + 降级） | 已实施 |
| 5 | 服务 | `.../app/services/pallastrade/disputes/rate_alert.rb`（台账 + 升级事件） | 已实施 |
| 6 | 作业 | `.../app/jobs/pallastrade/disputes/rate_alert_sweeper_job.rb` + `backend/config/sidekiq_schedule.rb` | 已实施 |
| 7 | 后台 | `.../pallastrade_admin/app/controllers/pallastrade/admin/dispute_rates_controller.rb` + `views/pallastrade/admin/dispute_rates/index.html.erb` | 已实施（另加 `dispute_rates_helper.rb`） |
| 8 | 修改 | `pallastrade_admin_navigation.rb`（position 64）、`routes.rb`、`ability`/permission、`en.yml` | 已实施 |
| 9 | i18n | `backend/config/locales/admin_dispute_rates.zh-CN.yml` | 已实施（90 键，与 gem 键集一致） |
| 10 | 测试 | PRD §8 的 6 个新 spec + `navigation_consistency_spec` 回归 | 已实施（79 例 0 失败） |
| 11 | Harness | verifier `d14c-dispute-rates-rspec`、GS-163（GS-159 已被占用）、`AGENTS.md` §6 行 | 已实施 |
| 12 | 文档 | 4 个 Skill + 业务方案 §71.3/§78-D14 回写 + PRD `done` | 已实施 |

## 6. 验证策略

- **主验证**：注册 verifier `d14c-dispute-rates-rspec`（6 个 spec 文件 + 导航回归），`harness evidence run --verifier` 采 test 证据。
- **负向证据**：AC-014 断言「评估前后 payments/orders/refunds/ledger/inventory/争议状态计数与金额全等」+「查询数不随行数增长」。
- **契约**：`harness generated:check`（预期零漂移，证明未误改 API）。
- **dev 冒烟**：比率与状态（ok/approaching/breached/unconfigured）→ 台账幂等与档位升级 → 下钻自洽（桶合计==汇总）→ 卡指纹脱敏 → 一键加黑写名单 → 零资金副作用 → `/up` 与新页面可达。

## 7. 实施记录

| 项 | 结果 |
|---|---|
| 迁移 | `20260916260000` 已应用（1 表 + 唯一键 `idx_dispute_rate_alerts_dedupe` + 2 索引；`schema.rb` +28 行） |
| 服务/模型/作业 | 均已落地（`RatePolicy` / `RateReport` / `RateAlert` / `RateAlertSweeperJob` + `dispute_rate_alert_sweep` 注册） |
| 后台 | `/admin/dispute_rates`（Orders position 64）+ 5 个 action（index / policy / reevaluate / export / add_to_denylist）+ 权限 `manage DisputeRateAlert` |
| i18n | gem `en.yml` 90 键 + host `zh-CN` 90 键（键集一致，含 `denylist_ambiguous`） |
| 测试 | verifier `d14c-dispute-rates-rspec`：**79 examples, 0 failures** |
| 跨层搜索结论保持 | Host App / API v3 / storefront / platform 均无命中 → 本切片**零契约变更**（`generated:check` 零漂移） |
| 设计变更（相对 PRD 初稿） | ① 一键加黑改为「页面只提交**掩码** + 服务端**唯一反解**」（初稿未约束）—— 避免原始卡指纹进入 HTML；② 权限由「读=争议或订单」收敛为 **统一 `manage DisputeRateAlert`**（实现更简单且与导航门控一致）；③ 场景编号 GS-159 → **GS-163**（占用冲突） |
| 遗留 | 提醒**外发渠道**（邮件/IM）；BIN 级下钻不可得（无 BIN 列）→ 以卡指纹替代 |
