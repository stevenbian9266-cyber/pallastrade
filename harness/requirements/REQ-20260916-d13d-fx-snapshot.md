# REQ-20260916-d13d-fx-snapshot

> 任务：`TASK-20260916110524-85b88ed2`
> Gate：`GATE-2026-09-16T11-05-35`
> PRD：`docs/prd/payments/PRD-20260916-payments-d13d-fx-snapshot.md`
> 类型：feature（新功能）
> 业务方案依据：§70.4（汇率与货币转换：来源/快照/加点/边界）；下游 §67.1 成本路由参考

## 1. 需求摘要

建立**汇率域**：多源汇率表（手工/provider/第三方 + 优先级）→ **下单锁汇快照**（展示汇率 + 加点后实际汇率，逐单可追溯）→ 结算落地后用**显式或推导的结算汇率**逐笔对比 → 偏差按基点计，超阈值进入既有对账队列（`kind: 'fx'`），恢复一致自动销案。仅做**结算差核算**，不动定价与资金。

## 2. 新建 vs 修改判据

- **新建**：6 层搜索 0 命中（无汇率模型/服务/页面/事件）→ 净新增域，必须新增 2 表 + 模型 + 服务 + 订阅者 + 作业 + 后台 2 页。
- **修改已有（复用）**：`ReconciliationCase`（扩 `KINDS`/`DIFFERENCE_TYPES`/`REASON_DIFFERENCE_TYPES`）、`Payouts::ImportCSV`（可选 `fx_rate` 列）、`sidekiq_schedule.rb`、`engine.rb`（订阅者注册）、导航与权限。

## 3. 跨层搜索结果（Step 0，6 层，逐层独立）

| 层 | 路径 | 关键词 | 结论 |
|---|---|---|---|
| App | `backend/app/` | currency_rate / exchange_rate / fx / 汇率 | 0 命中 |
| Core | `.../pallastrade_core/app/` | 同上 | 仅 `currency.rb`（币种元数据）与 `*_rate.rb`（shipping/tax rate，无关） |
| API | `.../pallastrade_api/app/` | currency_rate / exchange_rate | 0 命中 |
| Admin | `.../pallastrade_admin/app/` | 同上 | 0 命中 |
| Storefront | `storefront/src/` | exchangeRate / currencyRate | 0 命中 |
| Platform | `platform/packages/` | exchangeRate / exchange_rate | 0 命中 |

**避免的反模式**：AP-SEARCH-1（未止步于 `currency.rb`，六层搜完）；AP-SEARCH-2（按域概念而非类名搜索）；AP-SEARCH-3（未假设 admin/storefront 有对应能力）。

## 4. Skill Consultation Evidence Table（每格真实结论）

| Skill | 读取结论（对本任务的实际约束） |
|---|---|
| `pallastrade-payments` | 结算事实在 `payout_lines`（`payment_id`/`currency`/`gross_amount`/`raw`）；成本域（切片3）已有 `currency_conversion_percent` **费用**口径，本切片是**汇率**口径，须显式区分避免重复计费；对账队列是差异唯一出口。 |
| `pallastrade-events-webhooks` | 下游副作用走事件订阅者；`order.submitted` 由 `Carts::Submit` 发布，payload 三种形态需兼容；订阅者默认 async、异常**只日志不阻断**；engine 注册。 |
| `pallastrade-data-model` | 新表命名 `pallastrade_*`；金额 decimal 精度参照既有（汇率用 20,10）；jsonb 存 signals/metadata；不手改 `schema.rb`；只新增表不回填。 |
| `pallastrade-admin` | 后台范式：`audit_actor` 控制器自定义、`filter_by` + **计数同源**、`data-count-scope`、`::CSV.generate`、导航子项必须同步 `navigation_consistency_spec`；权限走 CanCan `can :manage, ...`。 |
| `pallastrade-security` | 只读事实 + 仅写快照/案例/审计；CSV 与页面不得含凭证/卡号；权限门控两页。 |
| `pallastrade-testing` | 每能力必须有 rspec（model/service/request/job/subscriber）；负向断言显式（零资金副作用比较前后计数与金额、无汇率不写行、跨店隔离）。 |
| `pallastrade-i18n` | 新后台页必须在 gem `en.yml` 与 host `zh-CN` 同步键集。 |
| `pallastrade-prd` | 一句话需求 → PRD（payments 分类）→ 用户确认 → gate + REQ → AC↔测试映射 → 知识同步门。 |

## 5. 交付物清单

| # | 类型 | 路径 |
|---|---|---|
| 1 | 迁移 | `backend/db/migrate/20260916250000_create_pallastrade_currency_rates.rb`（2 表） |
| 2 | 模型 | `.../pallastrade_core/app/models/pallastrade/currency_rate.rb` |
| 3 | 模型 | `.../pallastrade_core/app/models/pallastrade/fx_snapshot.rb` |
| 4 | 服务 | `.../app/services/pallastrade/currencies/rates/{upsert,resolver}.rb` |
| 5 | 服务 | `.../app/services/pallastrade/currencies/fx/{policy,lock,compare,sync_cases}.rb` |
| 6 | 订阅者 | `.../app/subscribers/pallastrade/currencies/fx/order_submitted_subscriber.rb` |
| 7 | 作业 | `.../app/jobs/pallastrade/currencies/fx/compare_sweeper_job.rb` |
| 8 | 后台 | `.../pallastrade_admin/app/controllers/pallastrade/admin/{currency_rates,fx_snapshots}_controller.rb` + 视图 |
| 9 | 修改 | `reconciliation_case.rb`（常量）、`payouts/import_csv.rb`（可选 `fx_rate`）、`sidekiq_schedule.rb`、`engine.rb`、`routes.rb`、导航、`ability` |
| 10 | i18n | gem `en.yml` + `backend/config/locales/admin_currency_fx.zh-CN.yml` |
| 11 | 工厂 | `.../testing_support/factories/{currency_rate,fx_snapshot}_factory.rb` |
| 12 | 测试 | 见 PRD §8（10+2 文件） |
| 13 | Harness | verifier `d13d-fx-snapshot-rspec`、GS-156、`AGENTS.md` §6 |
| 14 | 文档 | PRD、REQ、业务方案 §70.4 / §78-D13 |

## 6. 验收与证据计划

- 主证据：`harness evidence run --task TASK-20260916110524-85b88ed2 --type test --verifier d13d-fx-snapshot-rspec`
- 辅助：`generated:check`、`eval-ai --scenarios`、`prd-status-sync --check`、`sync-check --ack`
- dev 冒烟：建汇率 → 锁汇（含加点）→ 导入带 `fx_rate` 的结算 CSV（与不带列的推导）→ 偏差与容差判定 → 差异入队 + 恢复一致自动销案 → **零资金副作用** → `/up` 与两个新页面可达

## 7. 实施记录

**完成状态**：已实施（2026-09-16）。

| 项 | 结果 |
|---|---|
| 迁移 | `20260916250000_create_pallastrade_currency_rates.rb`（2 表 + 身份键唯一 + 币对/状态/期间索引；`(order_id, base, quote)` 唯一） |
| 模型 | `CurrencyRate`（归一化/身份键/优先级/生效窗口/软撤销）、`FxSnapshot`（锁汇字段 + 结算对比字段 + 展示 helper） |
| 服务 | `Currencies::Rates::{Upsert,Resolver}`、`Currencies::Fx::{Policy,Lock,Compare,SyncCases}` —— 只读事实 + 只写快照/案例/审计 |
| 接线 | `order.submitted` 订阅者（engine 注册）+ `CompareSweeperJob`（`*/30 * * * *`）+ `ReconciliationCase` 扩 `fx` 常量 + 结算导入可选 `fx_rate` 列 |
| 后台 | `/admin/currency_rates`（计数同源/新增/软撤销/审计）+ `/admin/fx_snapshots`（汇总/筛选/重新比对/CSV/案例跳转）；导航 Orders 62/63；权限 `can :manage, PallasTrade::CurrencyRate` |
| i18n | gem `en.yml` + host `zh-CN`（键集一致） |
| 测试 | 11 新文件 + 2 回归（d13b 导入 / 导航）；**103 examples, 0 failures** |
| 辅助 | `generated:check` no drift；`eval-ai` 159/159；`prd-status-sync` 一致 |
| 实施中发现 | ① `priority` 列默认值使模型默认逻辑失效（去列默认）；② engine 订阅者列表漏逗号；③ 订单币种须在店铺 `supported_currencies` 内；④ 同名关键字参数求值为 nil（改为 `payment_provider:`）；⑤ `ServiceModule::Base` 不支持 `any_instance_of` stub（改为 stub 内部读取路径）；⑥ 性能断言改为「读查询数不随行数增长」并注明按行写入原因 |
| dev 冒烟 | 优先级解析 / 锁汇（加点）/ 结算汇率（报文与推导）/ bips 与容差 / 差异入队 kind=fx + 修正后自动销案 / 跨店隔离 / **零资金副作用** / HTTP 可达 —— 全部通过 |

**证据**：`harness evidence run --task TASK-20260916110524-85b88ed2 --type test --verifier d13d-fx-snapshot-rspec`
