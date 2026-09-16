# PRD-20260916-payments-d13d-fx-snapshot

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-16 |
| 来源 | 需求：D13 切片4 汇率快照与结算汇率对比（业务方案 §70.4） |
| 分类 | payments |
| 关联 Skill | `pallastrade-payments`、`pallastrade-admin`、`pallastrade-data-model`、`pallastrade-events-webhooks`、`pallastrade-security`、`pallastrade-testing`、`pallastrade-i18n` |
| 关联 PRD | `PRD-20260916-payments-d13-reconciliation-cases`（差异队列，本切片复用为 fx 归属）、`PRD-20260916-payments-d13b-payout-ledger`（结算事实来源）、`PRD-20260916-payments-d13c-fee-cost-report`（成本口径） |
| 需求类型 | 新功能（汇率域从零到一：汇率表 + 下单锁汇快照 + 结算汇率对比入队） |

## 1. 背景与目标

业务方案 §70.4：

| 项 | 内容 |
|---|---|
| 来源 | provider / 第三方汇率 / 手工录入（可多源优先级） |
| 快照 | 下单时锁定展示汇率 → 与结算汇率逐笔对比，差异入对账队列 |
| 加点（up-charge） | 可配；展示「含货币转换费」 |
| 与定价边界 | 市场定价汇率由多市场方案负责；支付侧只做**结算差核算** |

现状（6 层搜索，0 命中）：平台**没有任何汇率能力**——
买家看到的价格、支付金额与最终结算之间如果存在币种转换，转换率**完全没有记录**，更无从核对；
D13 切片1 的对账队列只有 transaction/payment/refund/payout 四类，汇率差异无处归属。

**本切片目标**：
1. **汇率来源表**（多源 + 优先级）：手工 / provider / 第三方统一入库，解析时按「优先级 → 生效时间更晚 → id 更大」确定性取值；店铺级优先于全局。
2. **下单锁汇快照**：`order.submitted` 时锁定「展示汇率 + 加点后实际汇率」，形成逐单可追溯的汇率凭证（**只记录，不改价格、不动资金**）。
3. **结算汇率对比**：结算台账（D13b）落地后，用 provider 报文里的显式汇率（如结算 CSV 提供）或**由结算金额推导**的隐含汇率，与该单快照逐笔对比，偏差按基点（bips）计；超阈值 → 差异进入 D13 切片1 对账队列（`kind: 'fx'`），恢复一致 → **自动销案**。
4. **加点可配**：店铺 `fx_policy.up_charge_percent`，快照同时保留 `display_rate` 与 `effective_rate`，满足「展示『含货币转换费』」的读模型需要。

**范围纪律（不做）**：
- 不做市场定价/多币种标价（业务方案明确划归多市场方案）。
- 不调用任何外部汇率 API（第三方汇率以**手工/批量导入**形态入库；provider 汇率为结算报文派生）—— 零外呼。
- 不改订单/支付金额、不做换汇、不写资金流水；快照与对比**只读事实 + 只写快照/案例/审计**。
- 不新增 storefront 展示（前端「含货币转换费」文案属后续多市场切片；本切片提供数据）。
- 复用 D13 切片2 的结算行，**新增**可选列 `fx_rate` 的导入支持（向后兼容：缺列即走推导）。

## 2. 用户故事 / 场景

| # | 角色 | 场景 | 期望 |
|---|---|---|---|
| U1 | 财务 | 想知道某单当时锁的展示汇率是多少 | 快照页按订单可查 `display_rate` / `effective_rate` / 来源 / 加点 |
| U2 | 财务 | provider 结算汇率与我锁定的不一致，差在哪 | 快照行标出偏差 bips + 结算汇率来源（报文显式/推导） |
| U3 | 财务 | 需要人去跟 provider 对 | 超阈值差异自动出现在 `/admin/reconciliation_cases`（`kind=fx`），可指派/备注/关闭 |
| U4 | 运营 | 手工维护某币种汇率 | 汇率表新增/撤销，立即影响后续锁汇 |
| U5 | 运营 | 加了 0.5% 加点，想确认展示与实际 | 快照同时保存 `display_rate` 与 `effective_rate`（加点可见） |
| U6 | 审计 | 需要导出核对 | CSV 导出（快照与偏差；不含任何凭证） |

## 3. 功能需求（FR）

- **FR-1 汇率表**（`pallastrade_currency_rates`）
  - 字段：`store_id`（可空 = 全局）、`base_currency`（结算侧基准）、`quote_currency`（展示侧）、`rate` decimal(20,10)、
    `source`（`manual` / `provider` / `third_party`）、`priority` int（默认按来源：provider 30 > third_party 20 > manual 10，可显式覆写）、
    `effective_from`、`effective_until`、`status`（active/revoked）、`revoked_at`、`note`、`created_by_id`、`metadata`
  - 幂等键：`identity_key = SHA256("rate:<store|global>:<base>:<quote>:<source>:<effective_from_iso>")`，唯一索引
  - 索引：`(base_currency, quote_currency, status)`、`(store_id, status)`、`(status, effective_from)`
  - 校验：币种经 `Money::Currency` 存在性校验且大小写归一；`rate > 0`；`base != quote`；`priority >= 0`
- **FR-2 汇率解析**（`Currencies::Rates::Resolver`）
  - 候选：`for_store(store)`（全局 + 本店）∩ `active` ∩ `effective_at(at)`
  - 排序：`priority DESC` → **本店优先于全局** → `effective_from DESC` → `id DESC`（确定性）
  - 无候选 → `policy: nil` + `signals: ['no_rate']`（**不猜**，不写快照）
- **FR-3 下单锁汇**（`Currencies::Fx::Lock`）
  - 前置：`store.fx_policy.enabled`；`order.currency != store.default_currency`（同币种无需锁汇 → `signals: ['same_currency']`，不写行）
  - 取值：`display_rate = resolved rate`；`effective_rate = round(display_rate × (1 + up_charge_percent/100), 10)`
  - 写 `pallastrade_fx_snapshots`（幂等：`(order_id, base_currency, quote_currency)` 唯一）；`locked_on = 'order.submitted'`
  - 无可用汇率 → **不写快照**，返回 `signals: ['no_rate']`（后续人工补录汇率后可重锁）
  - 事件：`order.submitted` → 订阅者调用（异常只记日志，**绝不阻断下单**）
- **FR-4 结算汇率对比**（`Currencies::Fx::Compare`）
  - 候选：期间内 `variance_status ∈ {pending, undetermined}` 的快照；为每单找**已完成支付**及其结算行（`payout_line.payment_id`、`refund_id IS NULL`）
  - 结算汇率来源（优先级）：① 结算行 `raw['fx_rate']`（provider 报文显式）→ `settlement_source: 'provider_reported'`；
    ② 推导 `line.gross_amount / payment.amount`（结算币种 ≠ 订单币种时）→ `'implied'`；
    ③ 都拿不到 → `variance_status = 'undetermined'` + `signals: ['settlement_rate_unavailable']`
  - 偏差：`variance_bips = round((settlement_rate − effective_rate) / effective_rate × 10000)`
  - 判定：`|variance_bips| <= tolerance_bips` → `matched`；否则 `mismatch`；无结算数据 → 保持 `pending`（下次扫继续）
  - 幂等：同快照重复比对结果一致（写入 `compared_at` + `occurrences` 递增），**零资金副作用**
- **FR-5 差异入队**（`Currencies::Fx::SyncCases`）
  - `mismatch` → upsert `ReconciliationCase`（`kind: 'fx'`、`difference_type: fx_rate_mismatch`、`dedupe_key = "fx:<snapshot_id>:<signature>"`、
    `expected_amount` = 模型净额? —— 采用「预期结算额 vs 实际结算额」口径：`expected = payment.amount × effective_rate`、`observed = line.gross_amount`）；
    `matched`/恢复一致 → 对应开放案例**自动销案**（`fixed` + auto）；人工判定（explained/dismissed/fixed by human）**永不被覆盖**
  - 新开案例发布事件 `fx.settlement.mismatch`（下游告警可订阅）
- **FR-6 策略**（`Currencies::Fx::Policy`，存 `Store#private_metadata['fx_policy']`）
  - 键：`enabled`（默认 `true`）、`up_charge_percent`（默认 0）、`variance_tolerance_bips`（默认 **50**，即 0.5%）、`auto_reconcile`（默认 `true`）、`default_source`（默认 nil = 用优先级）
  - 归一化：非数值/负数 → 默认；`up_charge_percent` ∈ [0, 100]；`variance_tolerance_bips` ∈ [0, 10000]
- **FR-7 后台**（权限 `can?(:manage, PallasTrade::CurrencyRate)`）
  - `/admin/currency_rates`（Orders → 汇率表）：筛选（币种对/来源/状态）+ **同源计数** + 分页 + 新增 + 软撤销 + 审计（`currency_rate_changed` / `currency_rate_revoked`）
  - `/admin/fx_snapshots`（Orders → 汇率快照）：筛选（状态/期间/币种对）+ 汇总卡（锁定/已比对/匹配/差异/平均偏差 bips）+ 明细（订单、锁定汇率、加点后汇率、结算汇率与来源、偏差、案例链接）+ CSV 导出 + 与 D13 队列联动（差异行跳 `/admin/reconciliation_cases`）
  - 差异归属：既有 `/admin/reconciliation_cases` 的 `kind` 筛选纳入 `fx`
- **FR-8 结算导入扩展**（D13b 向后兼容）：`Reconciliations::Payouts::ImportCSV` 接受可选列 `fx_rate`（写入 `line.raw['fx_rate']`），缺列行为不变
- **FR-9 巡检**：`Currencies::Fx::CompareSweeperJob`（注册于 `config/sidekiq_schedule.rb`，默认每 30 分钟），带指标日志（`scanned/compared/matched/mismatched/pending/undetermined/cases_opened/cases_closed`）
- **FR-10 i18n**：gem `en.yml` + host `zh-CN`，键集一致
- **FR-11 零副作用铁律**：任何路径不得写 Payment/Refund/账本/库存/订单金额，不得外呼

## 4. 非功能需求（NFR）

- **NFR-1 性能**：对比批量装载（快照、支付、结算行各一次查询）；查询数不随行数增长（AC 断言）。
- **NFR-2 精度**：汇率 decimal(20,10)；bips 取整；金额对比用 BigDecimal。
- **NFR-3 可解释**：每条快照能说明「用了哪条汇率、加点多少、结算汇率从哪来、偏差多少」；差异案例带 summary 快照。
- **NFR-4 幂等**：锁汇按订单币种对幂等；对比可重复执行；案例 dedupe 键稳定。
- **NFR-5 安全**：后台页仅管理员；CSV 不含凭证/卡号；审计只记汇率与偏差字段。
- **NFR-6 兼容**：新增 2 表 + 1 可选 CSV 列；不改既有列；不手改 `schema.rb`。

## 5. 验收标准（AC，与测试一一映射）

| AC | 描述 | 映射测试 |
|---|---|---|
| AC-1 | 汇率表归一化（币种大写、rate > 0、base≠quote、priority 默认按来源）与身份键幂等 | `currency_rate_spec.rb` |
| AC-2 | 解析排序：priority → 本店>全局 → effective_from → id；过期/撤销不命中；无候选返回 `no_rate` | `currencies/rates/resolver_spec.rb` |
| AC-3 | 手工汇率 upsert 幂等 + 撤销保留历史 + 审计 | `currencies/rates/upsert_spec.rb` |
| AC-4 | 策略归一化与默认值（enabled/up_charge/tolerance/auto_reconcile） | `currencies/fx/policy_spec.rb` |
| AC-5 | 锁汇：加点后 `effective_rate` 正确；同币种跳过；无汇率**不写行**；重复锁幂等 | `currencies/fx/lock_spec.rb` |
| AC-6 | 订阅者：`order.submitted` → 产生快照；异常不阻断（只日志） | `fx/order_submitted_subscriber_spec.rb` |
| AC-7 | 对比：报文显式汇率优先；无则推导；都无 → `undetermined`；bips 计算与容差判定（matched/mismatch） | `currencies/fx/compare_spec.rb` |
| AC-8 | 差异入队：`kind=fx` + dedupe 稳定 + 恢复一致自动销案 + 人工判定不被覆盖 + 事件 `fx.settlement.mismatch` | 同上 + `sync_cases` |
| AC-9 | 跨店隔离：他店快照/汇率不参与；期间左闭右开 | 同上 |
| AC-10 | 零资金副作用 + 查询数不随行数增长 | 同上 |
| AC-11 | 后台汇率表：计数同源 + 新增/撤销 + 审计 + 权限 | `d13d_currency_rates_spec.rb` |
| AC-12 | 后台快照页：汇总/筛选/明细/偏差/CSV（无凭证）+ 权限 | `d13d_fx_snapshots_spec.rb` |
| AC-13 | 结算导入可选 `fx_rate` 列写入 `raw`，缺列行为不变（回归） | `d13b_import_csv_spec.rb` 扩展 |
| AC-14 | 导航一致性 + 队列 kind 筛选含 `fx` | `navigation_consistency_spec.rb` / `d13_reconciliation_cases_spec.rb` |

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 搜索路径 | 关键词 | 结果 |
|---|---|---|---|
| App | `backend/app/` | currency_rate / exchange_rate / fx / 汇率 | **0 命中** |
| Core | `backend/pallastrade_gems/pallastrade_core/app/` | 同上；模型目录 | 仅 `currency.rb`（币种元数据）、`shipping_rate.rb` / `tax_rate.rb`（与汇率无关）；**无汇率模型/服务** |
| API | `.../pallastrade_api/app/` | currency_rate / exchange_rate | 0 命中 |
| Admin | `.../pallastrade_admin/app/` | 同上 | 0 命中 |
| Storefront | `storefront/src/` | exchangeRate / currencyRate | 0 命中 |
| Platform | `platform/packages/` | exchangeRate / exchange_rate | 0 命中 |

**复用点（跨层已存在的能力）**：
- 差异队列：`ReconciliationCase`（切片1）—— 需扩展 `KINDS`（+`fx`）、`DIFFERENCE_TYPES`（+`fx_rate_mismatch`）、`REASON_DIFFERENCE_TYPES`（+`FX_RATE_MISMATCH`）；`SyncCases` 范式（切片2 `Payouts::SyncCases`）复用（dedupe/自动销案/人工判定保护）。
- 结算事实：`pallastrade_payout_lines`（`payment_id` / `currency` / `gross_amount` / `raw`）—— 结算汇率推导/报文来源。
- 事件：`order.submitted`（`Carts::Submit` 发布）+ 订阅者范式（D15 `Risk::OrderSubmittedSubscriber`）。
- 作业调度：`backend/config/sidekiq_schedule.rb`（D14b deadline sweeper 为例）。
- 后台范式：`audit_actor`、`filter_by` + 计数同源、`data-count-scope`、`::CSV.generate`、导航子项 + `navigation_consistency_spec`。
- 成本域（切片3）：`Payments::Fees::Calculate` 的 `currency_conversion_percent` 是**费用**口径；本切片是**汇率**口径，两者互补不重复（PRD 与 Skill 交叉引用）。

## 7. 技术影响

- 新增表：`pallastrade_currency_rates`、`pallastrade_fx_snapshots`（2 张，迁移 `20260916250000`）
- 新增模型：`PallasTrade::CurrencyRate`、`PallasTrade::FxSnapshot`
- 新增服务：`Currencies::Rates::{Upsert,Resolver}`、`Currencies::Fx::{Policy,Lock,Compare,SyncCases}`
- 新增订阅者：`Currencies::Fx::OrderSubmittedSubscriber`（engine 注册）
- 新增作业：`Currencies::Fx::CompareSweeperJob`（+ 调度）
- 新增后台：`/admin/currency_rates`、`/admin/fx_snapshots` + 导航（Orders 子项 62/63）+ 权限 + i18n
- 修改：`ReconciliationCase` 常量与队列筛选、`Payouts::ImportCSV` 可选 `fx_rate` 列、`sidekiq_schedule.rb`、`engine.rb`
- 不改动：订单/支付金额与状态、账本、库存、既有 API 契约

## 8. 测试计划

| 层 | 文件 | 覆盖 |
|---|---|---|
| Model | `spec/models/pallastrade/d13d_currency_rate_spec.rb` | AC-1 |
| Model | `spec/models/pallastrade/d13d_fx_snapshot_spec.rb` | AC-5（状态/偏差辅助） |
| Service | `spec/services/pallastrade/currencies/rates/d13d_resolver_spec.rb` | AC-2 |
| Service | `spec/services/pallastrade/currencies/rates/d13d_upsert_spec.rb` | AC-3 |
| Service | `spec/services/pallastrade/currencies/fx/d13d_policy_spec.rb` | AC-4 |
| Service | `spec/services/pallastrade/currencies/fx/d13d_lock_spec.rb` | AC-5 |
| Service | `spec/services/pallastrade/currencies/fx/d13d_compare_spec.rb` | AC-7/8/9/10 |
| Subscriber | `spec/subscribers/pallastrade/currencies/fx/d13d_order_submitted_spec.rb` | AC-6 |
| Job | `spec/jobs/pallastrade/currencies/fx/d13d_compare_sweeper_spec.rb` | FR-9 指标 |
| Request | `spec/requests/pallastrade/admin/d13d_currency_rates_spec.rb` | AC-11 |
| Request | `spec/requests/pallastrade/admin/d13d_fx_snapshots_spec.rb` | AC-12 |
| Regression | `spec/services/pallastrade/reconciliations/payouts/d13b_import_csv_spec.rb`、`navigation_consistency_spec.rb` | AC-13/14 |

**Verifier**：`harness verify d13d-fx-snapshot-rspec`

## 9. 收口清单

- [x] PRD approved → 用户确认（2026-09-16「确认，按此实施」）
- [x] gate + REQ（含 Skill 表）
- [x] 迁移（2 表）+ 2 模型 + 6 服务 + 订阅者 + 作业 + 后台 2 页 + i18n
- [x] spec 文件（11 + 2 回归）+ verifier 注册
- [x] AGENTS §6 新增行 + GS-158 场景
- [x] 知识同步（Skills / 业务方案 §70.4 / §78 D13 行）
- [x] `generated:check` / `eval-ai --scenarios`（159/159）/ `prd-status-sync --check`
- [x] dev 冒烟：锁汇 → 结算对比（报文/推导）→ 差异入队/自动销案 → 零资金副作用

### 9.1 实施记录（2026-09-16）

**交付物**

| # | 类型 | 路径 |
|---|---|---|
| 1 | 迁移（2 表） | `backend/db/migrate/20260916250000_create_pallastrade_currency_rates.rb` |
| 2 | 模型 | `.../pallastrade_core/app/models/pallastrade/currency_rate.rb`、`fx_snapshot.rb` |
| 3 | 服务 | `.../app/services/pallastrade/currencies/rates/{upsert,resolver}.rb` |
| 4 | 服务 | `.../app/services/pallastrade/currencies/fx/{policy,lock,compare,sync_cases}.rb` |
| 5 | 订阅者 / 作业 | `.../app/subscribers/pallastrade/currencies/fx/order_submitted_subscriber.rb`、`.../app/jobs/.../compare_sweeper_job.rb` |
| 6 | 后台 | `.../pallastrade_admin/app/controllers/pallastrade/admin/{currency_rates,fx_snapshots}_controller.rb` + 视图 2 个 |
| 7 | 修改 | `reconciliation_case.rb`（KINDS/DIFFERENCE_TYPES/REASON 映射）、`payouts/import_csv.rb`（可选 `fx_rate`）、`sidekiq_schedule.rb`、`engine.rb`、路由/导航（Orders 62/63）/权限 |
| 8 | i18n | gem `en.yml` + `backend/config/locales/admin_currency_fx.zh-CN.yml` |
| 9 | 工厂 | `.../testing_support/factories/{currency_rate,fx_snapshot}_factory.rb` |
| 10 | 测试 | 见 §8（11 新文件 + 2 回归）；**103 例全绿** |
| 11 | Harness | verifier `d13d-fx-snapshot-rspec`、GS-158、`AGENTS.md` §6 行 |

**口径决策（实施中确定）**

- 汇率语义：`rate` = **1 个 quote（展示币种）对应的 base（结算币种）数量**；快照 `base = store.default_currency`、`quote = order.currency`。
- 解析优先级：`priority DESC` → **本店优先于全局** → `effective_from DESC` → `id DESC`；来源默认优先级 provider 30 / third_party 20 / manual 10（可显式覆写）。
- 锁汇时机：`order.submitted`（与业务方案「下单时锁定展示汇率」一致）；同币种/无汇率/策略关闭 → **不写行**（不猜）。
- 结算汇率来源优先级：结算行 `raw['fx_rate']`（报文显式）→ `line.gross_amount / payment.amount`（推导，要求结算币种 == 快照 base）→ `undetermined`（不猜）。
- 容差：`variance_tolerance_bips` 默认 **50**（0.5%）；`|bips| <= tolerance` → matched，否则 mismatch。
- 复核路径：巡检只扫 `pending`/`undetermined` + 结算行在上次比对后被改动的 `mismatch`（修正后翻回 matched 并自动销案）；后台「重新比对」可显式复算当前筛选集合。
- 差异归属：复用 D13 切片1 队列（`kind: 'fx'`、`difference_type: 'fx_rate_mismatch'`、`dedupe_key = "fx:<snapshot_id>:<status>"`）；人工判定（explained/fixed/dismissed）永不被覆盖。
- 与成本域边界：切片3 的 `currency_conversion_percent` 是**费用**口径，本切片是**汇率**口径，互不替代。

**实施中发现并修复的问题**

1. `priority` 列默认值（DB default 10）会让模型的「按来源赋默认」永远不触发 → 去掉列默认，改由模型归一化赋值。
2. `engine.rb` 订阅者列表改用逗号（新增元素时漏写逗号导致语法错误）。
3. 订单币种必须在该店 `supported_currencies` 内（否则 `Currency is not supported by this store`）→ 汇率相关 fixture 显式声明支持币种。
4. 同名关键字参数陷阱复现（`provider: provider` 求值为 nil）→ 一律改用不同名（`payment_provider:`）。
5. `ServiceModule::Base` 的 `call` 由 prepend 提供，RSpec 不支持 `any_instance_of` 覆盖 → 改为 stub 内部读取路径（`FxSnapshot.for_store`）验证失败隔离。
6. 性能断言口径：拉链路每行必有一次结果 UPDATE + 案例 upsert（与 `Payouts::SyncCases` 同范式）→ 断言改为「**读**查询数不随行数增长」并显式注释原因（诚实口径，不掩盖按行写入）。

**验证**

- `harness verify d13d-fx-snapshot-rspec`：**103 examples, 0 failures**（11 个新文件 + d13b 导入回归 + 导航一致性回归）
- `harness generated:check` no drift；`harness eval-ai --scenarios` **159/159 valid**（含新增 GS-158）
- dev 冒烟：汇率解析与优先级 → 锁汇（含加点）→ 结算汇率（报文显式 / 推导）→ bips 与容差 → 差异入队（kind=fx）+ 修正后自动销案 → 跨店隔离 → **零资金副作用** → `/up` 与 `/admin/currency_rates`、`/admin/fx_snapshots` 可达

### 9.2 知识同步结论（`harness sync-check --id PRD-20260916-payments-d13d-fx-snapshot`）

| 触发项 | 资产 | 结论 |
|---|---|---|
| Model / DB 变更 | 领域 Skill（pallastrade-payments） | 已更新（汇率域章节：两表/服务语义/bips/与成本域边界） |
| Model / DB 变更 | pallastrade-data-model Skill | 已更新（汇率域两表字段与约束） |
| Model / DB 变更 | 测试 | 已更新（11 新 spec + 2 回归 + verifier `d13d-fx-snapshot-rspec`） |
| Model / DB 变更 | 场景库 | 已更新（GS-158；eval-ai 159/159） |
| 后台路由变更 | backend/public/api-docs | 不适用（仅后台 HTML 页面，未动 /api/v3） |
| 后台路由变更 | pallastrade-api-v3 Skill | 不适用（API 契约不变） |
| 后台路由变更 | SDK 类型(generated:check) | 已评估无需变更（generated:check 无漂移） |
| 事件 / 订阅者 | pallastrade-events-webhooks Skill | 已更新（order.submitted 锁汇 + `fx.settlement.mismatch` + 巡检） |
| Skill / PRD 机制 | pallastrade-prd Skill | 已评估无需变更（流程未变） |
| Skill / PRD 机制 | AGENTS.md | 已更新（§6 矩阵新增汇率快照行） |
| Skill / PRD 机制 | copilot-instructions.md | 不适用（规则已落在领域 Skill） |
| Skill / PRD 机制 | scenarios.json | 已更新（GS-158） |
| — | pallastrade-admin Skill | 已更新（汇率两页：筛选/计数同源/重新比对/CSV/权限） |
| — | pallastrade-storefront Skill / 组件测试 | 不适用（未改动 `storefront/src`；后台页面由请求级 spec 覆盖） |

## 10. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-09-16 | 初稿（D13 切片4，业务方案 §70.4） |
| 2026-09-16 | 实施完成：2 表 + 6 服务 + 订阅者/作业 + 后台 2 页 + 13 个 spec 文件（103 例绿）；§9.1 回填 |
| 2026-09-16 | 知识同步完成（§9.2）：4 个领域 Skill 更新、AGENTS §6、GS-158、prd 状态索引；`prd-status-sync --check` 169/169 一致 |
