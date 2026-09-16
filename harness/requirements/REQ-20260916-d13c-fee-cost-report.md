# REQ-20260916-d13c-fee-cost-report

> 任务：`TASK-20260916081649-bdf47935`
> Gate：`GATE-2026-09-16T08-17-55`
> PRD：`docs/prd/payments/PRD-20260916-payments-d13c-fee-cost-report.md`
> 类型：feature（新功能）
> 业务方案依据：§70.3（费率模型 + 支付成本报表）；下游 §67.1 成本路由

## 1. 需求摘要

建立**支付费率策略模型**（rate card，可按 provider / 入口 method / 卡类型 / 地区配置，含百分比费、固定费、跨境费、货币转换费、平台费），并据此提供**只读支付成本报表**：总额、单均成本、按入口成本排名，且**可下钻到入口逐笔明细**，同时与 D13b 结算单实际扣费对比给出偏差。

## 2. 新建 vs 修改判据

- **修改已有**：无既有费率/成本能力（6 层搜索 0 命中，见 PRD §6）→ 本切片为**净新增域**，必须新增文件。
- 复用而非新建的部分：入口身份读模型（`PaymentMethod#effective_payment_option` 等）、实际费用（`payout_lines.fee_amount`）、后台模式（`RiskListsController` 的 `audit_actor` / CSV / 计数同源）、i18n 双语文档结构。

## 3. 跨层搜索结果（Step 0，6 层，逐层独立）

| 层 | 路径 | 关键词 | 结论 |
|---|---|---|---|
| App | `backend/app/` | fee_policy / payment_fee / cost_report / fee_calculat | 无既有实现（0 命中） |
| Core | `backend/pallastrade_gems/pallastrade_core/app/` | fee / cost | 仅 `payout_line.rb#fee_amount`（D13b 实际扣费）；无费率模型/无成本核算 |
| API | `backend/pallastrade_gems/pallastrade_api/app/` | fee / cost | 命中均无关（price_lists、fulfillments 等字符串）；无费用端点 |
| Admin | `backend/pallastrade_gems/pallastrade_admin/app/` | fee_polic / payment_cost / cost_report | 无后台页面（0 命中） |
| Storefront | `storefront/src/` | payment_fee / cost_report | 0 命中 |
| Platform | `platform/packages/` | payment_fee / cost_report | 0 命中 |

**避免的反模式**：
- AP-SEARCH-1（STOP_EARLY）：未止步于 core 的 `fee_amount`，六层全部搜完；
- AP-SEARCH-2（NAME_MISMATCH）：以域概念（fee/cost/费率）而非类名搜索；
- AP-SEARCH-3（LAYER_ASSUME）：未因 core 无能力而假设 admin 有页面（实际 admin 为 0 命中）。

## 4. Skill Consultation Evidence Table（每格真实结论，非「已读」）

| Skill | 读取结论（对本任务的实际约束） |
|---|---|
| `pallastrade-customization` | 决策树：本任务无既有类可改（净新增）→ 走「新建模型 + Service + Admin 控制器」路径；若未来要改支付链路行为，应优先 Settings/事件而非装饰器。因此本切片**不装饰任何既有支付类**，成本核算完全外置为只读服务。 |
| `pallastrade-payments` | 支付事实源为 `pallastrade_payments`（`amount`/`state`/`payment_method_id`/`order_id`/`payment_session_id`），**无 option 列**；已完成态与 `Payment` 状态机同源；退款/对账台已有 D13/D13b 口径。→ 报表统计域以 `state` 同源口径 + 门店作用域限定，入口维度必须显式声明为「当前映射」。 |
| `pallastrade-data-model` | 新表命名遵循 `pallastrade_*` + §74.1 索引规范（`(scope_type, scope_id)`）；金额列 `decimal` 精度参照既有 `payout_lines`（12,2）；jsonb 用于 `metadata`；不手改 `schema.rb`。 |
| `pallastrade-admin` | 后台控制器继承 `PallasTrade::Admin::BaseController`；权限走 CanCan `can :manage, ...`；审计用 `PallasTrade::AuditLog`（`audit_actor` 需控制器自定义，`BaseController` 未提供，D15 已验证）；列表计数需与筛选同源（`filter_by` + 同一 `collection`）；导航项需与路由同源，否则 `navigation_consistency_spec` 失败。 |
| `pallastrade-security` | 报表与导出仅管理员可访问；CSV/页面**不得**输出任何凭证、卡号、密钥；审计记录只含策略字段与操作者，不含敏感值；费率策略不含任何 provider 密钥。 |
| `pallastrade-testing` | 每组新能力必须有对应 rspec（model/service/request 三层）；负向断言必须显式（零资金副作用需比较前后计数与金额）；请求 spec 需 stub `current_store` 与权限。 |
| `pallastrade-i18n` | 新增后台页面必须在 gem `en.yml` 与 host `zh-CN` 同步键集，避免 `translation missing`。 |
| `pallastrade-prd` | 一句话需求 → PRD（分类 payments，查重）→ 用户确认 → gate + REQ → AC↔测试映射 → 知识同步门（`sync-check --ack`）。 |

## 5. 交付物清单

| # | 类型 | 路径 |
|---|---|---|
| 1 | 迁移 | `backend/db/migrate/20260916230000_create_pallastrade_payment_fee_policies.rb` |
| 2 | 模型 | `backend/pallastrade_gems/pallastrade_core/app/models/pallastrade/payment_fee_policy.rb` |
| 3 | 服务 | `.../pallastrade_core/app/services/pallastrade/payments/fees/resolver.rb` |
| 4 | 服务 | `.../pallastrade_core/app/services/pallastrade/payments/fees/calculate.rb` |
| 5 | 服务 | `.../pallastrade_core/app/services/pallastrade/payments/costs/report.rb` |
| 6 | 后台控制器 | `.../pallastrade_admin/app/controllers/pallastrade/admin/payment_fee_policies_controller.rb` |
| 7 | 后台控制器 | `.../pallastrade_admin/app/controllers/pallastrade/admin/payment_costs_controller.rb` |
| 8 | 视图 | `.../pallastrade_admin/app/views/pallastrade/admin/payment_fee_policies/{index,new,edit,_form}.html.erb` |
| 9 | 视图 | `.../pallastrade_admin/app/views/pallastrade/admin/payment_costs/index.html.erb` |
| 10 | 路由/导航/权限 | `.../pallastrade_admin/config/routes.rb`、navigation、`ability.rb` |
| 11 | i18n | gem `config/locales/en.yml` + `backend/config/locales/admin_payment_fee_costs.zh-CN.yml` |
| 12 | 测试 | 5+2 个 spec 文件（见 PRD §8） |
| 13 | Harness | `harness.config.mjs`（verifier）、`harness/scenarios/scenarios.json`（GS-154）、`AGENTS.md` §6 |
| 14 | 文档 | PRD、REQ、业务方案 §70.3 / §78（D13、D15 遗留行） |

## 6. 验收与证据计划

- 主证据：`harness evidence run --task TASK-20260916081649-bdf47935 --type test --verifier d13c-cost-report-rspec`
- 辅助：`generated:check`、`eval-ai --scenarios`、`prd-status-sync --check`、`sync-check --ack`
- dev 冒烟（真实数据）：创建费率策略 → 报表总额/排名 → 下钻明细条数 == 入口 payment_count → 实际 vs 模型偏差 → **零资金副作用断言** → `/up` 200、`/admin/payment_costs` 302

## 7. 实施记录

**完成状态**：已实施（2026-09-16）。

| 项 | 结果 |
|---|---|
| 迁移 | `20260916240000_create_pallastrade_payment_fee_policies.rb`（1 表 + 3 索引，`(scope_type, scope_id)` 符合 §74.1） |
| 服务 | `Payments::Fees::Resolver`（含 `Context`）/ `Payments::Fees::Calculate` / `Payments::Costs::Report` —— 全部只读 |
| 后台 | `/admin/payment_costs`（期间/维度筛选 + 汇总卡 + 入口排名 + 下钻 + CSV 含入口键）+ `/admin/payment_fee_policies`（新增/编辑/软撤销 + 审计 + 权限）；导航 Orders 子项 60/61；`can :manage, PallasTrade::PaymentFeePolicy` |
| i18n | gem `en.yml` + host `zh-CN`（键集一致，含 CSV `entry_key`） |
| 测试 | 7 文件 / **162 例全绿**（含 `navigation_consistency_spec` 回归） |
| 辅助 | `generated:check` no drift；`eval-ai` 156/156；`prd-status-sync` 167/167 |
| 实施中发现 | ① `joins(:order)` 与 `includes(order:)` 同用会丢预加载 → 每笔一次查询（已改为子查询 + 显式注入 store 对象，AC-14 断言查询数恒定）；② `PallasTrade::CSV` 遮蔽标准库 → `::CSV.generate`；③ 报表页断言需容忍模板换行（正则）；④ CSV 增 `entry_key` 列 |
| dev 冒烟 | 解析优先级 / 单笔分量 / 跨境不计费留痕 / 汇总与排名 / 下钻条数 == 入口 payment_count / 实际 vs 模型偏差 / 跨店隔离 / **零资金副作用** / 撤销回落 / HTTP 可达 —— 全部通过 |

**证据**：`harness evidence run --task TASK-20260916081649-bdf47935 --type test --verifier d13c-cost-report-rspec`
