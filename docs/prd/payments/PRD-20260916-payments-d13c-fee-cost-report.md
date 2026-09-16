# PRD-20260916-payments-d13c-fee-cost-report

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-16 |
| 来源 | 需求：D13 切片3 费率模型与支付成本报表（业务方案 §70.3） |
| 分类 | payments |
| 关联 Skill | `pallastrade-payments`、`pallastrade-admin`、`pallastrade-data-model`、`pallastrade-security`、`pallastrade-testing`、`pallastrade-i18n` |
| 关联 PRD | `PRD-20260916-payments-d13b-payout-ledger`（实际扣费来源）、`PRD-20260916-payments-d16-payment-method-presentation`（入口读模型）、`PRD-20260915-payments-d8`（适用范围与策略门控范式） |
| 需求类型 | 新功能（费用域从零到一：费率模型 + 只读成本报表） |

## 1. 背景与目标

支付成本当前**不可见**：本地只掌握「收了多少钱」（`pallastrade_payments.amount`）与「结算实际被扣了多少」（`pallastrade_payout_lines.fee_amount`，且仅在导入结算单后才有）。缺少**事前费率模型**，导致三个后果：

1. 无法回答「某笔/某入口的真实成本率是多少」——只能等结算单漂到，且只能拿到批次口径。
2. 无法对比「**预期费率 vs 结算实际扣费**」，费率谈错、涨价、错配只能靠人肉。
3. 无法支撑 §67.1 **成本路由**（按成本选入口/选 provider），因为成本没有模型化。

业务方案 §70.3 要求：
- **费率模型**：百分比 + 固定费 + 跨境费 + 货币转换费 + 平台费；可按 provider / method / 卡类型 / 地区配置。
- **报表**：支付成本、单均成本、按 option 成本排名 → 支撑成本路由（§67.1）。

**本切片目标（验收锚点：「成本可下钻到入口」）**：
1. 建立**费率策略**（rate card）：可并存多条，按 scope 优先级解析，支持币种/卡类型/地区条件与生效窗口。
2. 提供**单笔费用计算**（纯计算、零写库、零 provider I/O），分解为各费用分量与净额。
3. 提供**成本报表**：按期间/维度聚合（总额、单均成本、按入口排名），并**可下钻**到「入口 × 币种 × 期间」的逐笔支付明细。
4. 报表中并列展示**结算实际费用**（来自 D13b 的 `payout_lines.fee_amount`）与**模型预期费用**，差异即费率偏差信号。

**范围纪律（不做）**：
- 不做汇率快照与结算汇率差异（§70.4，D13 切片4）。
- 不对支付链路做任何写入（不在 create/complete 时落费用）——本切片是**只读核算**。
- 不新增 `pallastrade_payment_options` 表：入口身份沿用 D1/D8/D16 的读模型（`payment_method` × `method_key`）。
- 不做真实 provider 费率 API 拉取（第三方源属 §70.4 后续）。

## 2. 用户故事 / 场景

| # | 角色 | 场景 | 期望 |
|---|---|---|---|
| U1 | 财务 | 想知道某月支付成本总额与单均成本 | 报表页选期间 → 看到 total_gross / total_fee / net / fee_rate / 单均成本 |
| U2 | 财务 | 想知道「哪个入口最贵」 | 按入口排名表（入口 = 支付方式 × method_key），带占比与单均成本 |
| U3 | 财务 | 想核对某入口的费率是否与合同一致 | 下钻到该入口逐笔明细（时间/订单/币种/金额/各项费用） |
| U4 | 运营 | 收款方新报价单来了，想先测算 | 维护费率策略 → 报表立即按新费率重算（不影响历史数据） |
| U5 | 财务 | 想知道模型费率与结算实际扣费的偏差 | 报表并列实际费用（payout_line）与模型费用，差值/偏差率可见 |
| U6 | 风控/审计 | 需要导出给外部 | CSV 导出（下钻明细与排名） |

## 3. 功能需求（FR）

- **FR-1 费率策略模型**（表 `pallastrade_payment_fee_policies`）
  - 字段：`store_id`（可空 = 全局）、`name`、`scope_type`（global/store/provider/method）、`scope_id`（provider=payment_method_id；method=method_key 字符串）、`currency`（可空 = 全部）、`card_type`（可空 = 全部）、`region`（可空 = 全部，ISO 国家码，匹配订单账单国家）、`percent_fee`、`fixed_fee`、`cross_border_percent`、`cross_border_fixed`、`currency_conversion_percent`、`platform_percent`、`min_fee`、`max_fee`、`home_country`（可空，跨境判定基准国）、`settlement_currency`（可空，货币转换判定基准币）、`effective_from`、`effective_until`、`status`（active/revoked）、`metadata`、`created_by_id`、`revoked_at`
  - 索引：`(scope_type, scope_id)`（§74.1 要求）、`(store_id, status)`、`(status, effective_from)`
  - 约束：`percent_fee/平台费/跨境费/转换费` 非负且 ≤ 100；`fixed_fee/cross_border_fixed` 非负；`min_fee ≤ max_fee`（若两者皆存在）；`scope_type=provider/method` 时 `scope_id` 必填，`global/store` 时必须为空
- **FR-2 策略解析**（`Payments::Fees::Resolver`）
  - 优先级：`method` > `provider` > `store` > `global`（同优先级取 `effective_from` 更晚者，再取 id 更大者，保证确定性）
  - 条件匹配：币种（空=全部）、卡类型（空=全部；取 `payment.source` 的 `cc_type`）、地区（空=全部；取订单账单国家 ISO）
  - 状态与窗口：仅 `active` 且 `effective_from <= 参照时刻` 且（`effective_until` 为空或 `>= 参照时刻`）
  - 无匹配 → 返回 nil（报表将该笔归入「无费率」桶，**不臆造成本**）
- **FR-3 单笔费用计算**（`Payments::Fees::Calculate`）
  - 分量：`percent`（金额 × percent_fee）、`fixed`、`platform`（金额 × platform_percent）、`cross_border`（条件成立时才计：`home_country` 存在且订单账单国家 ≠ home_country）、`conversion`（条件成立时才计：`settlement_currency` 存在且支付币种 ≠ settlement_currency）
  - 保底/封顶：`min_fee` / `max_fee` 对**百分比类分量之和**封顶/保底后与固定费相加？→ **口径确定**：先算 `variable = percent + platform + cross_border_percent + conversion`，对 `variable` 应用 min/max（视为对费率类费用的保底封顶），再 `total = variable_clamped + fixed + cross_border_fixed`
  - 输出：各分量、`total_fee`、`net_amount`（金额 − total_fee）、`signals`（如 `conversion_undetermined` / `cross_border_undetermined`，条件数据缺失时留痕且**不计费**）
  - 纯函数：**零写库、零外部调用**
- **FR-4 成本报表**（`Payments::Costs::Report`）
  - 输入：`store`、`from`/`to`、可选 `payment_method_id`、可选 `currency`、可选 `method_key`
  - 统计域：所属门店 + 支付在 `[from, to)` 内 + `state` 为已完成（`completed`/`checkout` 等已完成态，取 `Payment::COMPLETED_STATES` 同源口径）
  - 输出：`totals`（gross/fee/net/`fee_rate`/`average_order_cost`（按订单去重）/`order_count`/`payment_count`/`unpriced_count`）、`by_entry`（入口维度：payment_method + method_key，含 gross/fee/net/单均/占比，按 fee 降序，tie-break 稳定）、`by_provider`、`by_currency`、`series`（按日或按币种，二选一实现：按币种）
  - **下钻**：`detail` 返回入参口径下的逐笔支付（时间/订单号/入口/币种/金额/分量/total/net），有界（默认上限 500 行并标记 `truncated`）
  - **实际 vs 模型**：对存在 `payout_line` 关联的支付，并列 `actual_fee`，并给 `variance`（actual − modeled）与 `variance_rate`
  - 只读：**零写库、零外部调用**
- **FR-5 后台：费率维护**（`/admin/payment_fee_policies`）
  - index（列表 + 图表计数 + 状态/scope 筛选）、new/create、edit/update、`revoke`（软撤销，保留审计）
  - 审计：`payment_fee_policy_changed`（增改）/`payment_fee_policy_revoked`
  - 权限：`can :manage, PallasTrade::PaymentFeePolicy`
- **FR-6 后台：成本报表**（`/admin/payment_costs`）
  - 期间（默认近 30 天）+ 维度筛选（provider / 币种 / 入口）+ 汇总卡 + 入口排名表（行可下钻）+ 逐笔明细 + 未定价提示 + CSV 导出（`send_data`）
  - 导航：新增一个导航项（成本报表，位于 `risk_lists` 之后，position 60）；费率维护页从报表页头部入口进入（避免导航项膨胀）
- **FR-7 i18n**：`en.yml` + `backend/config/locales/admin_payment_fee_costs.zh-CN.yml`，键集一致
- **FR-8 零副作用铁律**：本切片任何路径**不得**产生资金流水、不得写入 `pallastrade_payments`/`refunds`/`financial_ledger_entries`/库存，不得发起 provider HTTP

## 4. 非功能需求（NFR）

- **NFR-1 性能**：报表按期间 + 门店走索引查询；入口聚合在内存中按已加载集合归并，明细默认上限 500；列表页不出现 N+1（`includes(:payment_method, :order)`）。
- **NFR-2 精度**：金额用 BigDecimal，四舍五入到 ISO 币种的小数位（JPY=0 等按 `PallasTrade::Money` 口径），最终 `round(2)` 与本地事实一致（本地全部 2 位）。
- **NFR-3 可解释**：每个汇总数可在明细中复现（计数/金额自洽），报表顶部展示口径说明（已完成支付、期间左闭右开、入口=当前映射）。
- **NFR-4 幂等/只读**：报表与计算可重复调用，结果只依赖输入与数据库快照；不写任何状态。
- **NFR-5 安全**：仅管理员可访问；CSV 导出不包含任何凭证/卡号（仅订单号、金额、入口名）。
- **NFR-6 兼容**：新增表与外键均为新增，不改动既有列；不触碰 `db/schema.rb` 手改（走迁移）。

## 5. 验收标准（AC，与测试一一映射）

| AC | 描述 | 映射测试 |
|---|---|---|
| AC-1 | 费率策略归一化：空字符串转 nil、百分比超界/负值被拒、min>max 被拒、scope 与 scope_id 一致性校验 | `payment_fee_policy_spec.rb` |
| AC-2 | 解析优先级 method > provider > store > global；同优先级取更晚 `effective_from`；过期/撤销/未生效不命中 | `payments/fees/resolver_spec.rb` |
| AC-3 | 条件匹配：币种不符不命中、卡类型不符不命中、地区不符不命中；条件缺失（如无 source）时按「全部」处理但留 signal | 同上 |
| AC-4 | 单笔计算：百分比 + 固定 + 平台费正确；跨境费仅在 `home_country` 不匹配时计；转换费仅在币种 ≠ `settlement_currency` 时计；min/max 作用域明确（费率类分量） | `payments/fees/calculate_spec.rb` |
| AC-5 | 无匹配费率时不计费并计入 `unpriced_count`（不臆造成本） | 同上 + 报表 spec |
| AC-6 | 报表汇总自洽：`totals.fee == Σ detail.fee`、`totals.gross == Σ detail.amount`、入口排名 fee 之和 == totals.fee | `payments/costs/report_spec.rb` |
| AC-7 | **成本可下钻到入口**：按入口排名行下钻得到该入口逐笔明细，且明细条数 == 该入口 `payment_count` | 同上 |
| AC-8 | 期间左闭右开、跨店隔离（他店支付不入选）、未完成支付不入选 | 同上 |
| AC-9 | 实际 vs 模型：有 `payout_line` 关联的支付并列 `actual_fee` 与 `variance`；无则 `actual_fee` 为 nil | 同上 |
| AC-10 | 零资金副作用：报表/计算调用前后 payments/refunds/ledger/inventory 计数与金额不变 | 同上 |
| AC-11 | 后台费率维护：创建/更新/撤销 + 审计落库 + 权限（无权限 302/拒绝）+ 校验失败回显 | `requests/pallastrade/admin/payment_fee_policies_spec.rb` |
| AC-12 | 后台成本报表：汇总与排名渲染、筛选生效、下钻明细渲染、CSV 导出包含明细行且不含卡号、无权限被拒 | `requests/pallastrade/admin/payment_costs_spec.rb` |
| AC-13 | 导航一致性：新增导航项与路由同源（导航未列出的 admin 路由需在导航中出现） | `navigation_consistency_spec.rb` |
| AC-14 | 报表性能与 N+1：明细/排名查询在给定规模下不随行数增长（查询数断言） | `payments/costs/report_spec.rb` |

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 搜索路径 | 关键词 | 结果 |
|---|---|---|---|
| App | `backend/app/` | fee_policy / payment_fee / cost_report / fee_calculat | 0 命中（无既有实现） |
| Core | `backend/pallastrade_gems/pallastrade_core/app/` | fee / cost | 仅 `payout_line.rb`（`fee_amount` 实际扣费，D13b）、`dispute.rb`/`order.rb` 中与「费用」无关的字符串命中；**无费率模型、无成本核算** |
| API | `.../pallastrade_api/app/` | fee / cost | 命中均为无关（contact_messages、price_lists、fulfillments 的字符串）；无费用端点 |
| Admin | `.../pallastrade_admin/app/` | fee_polic / payment_cost / cost_report | 0 命中（无后台页面） |
| Storefront | `storefront/src/` | payment_fee / cost_report | 0 命中 |
| Platform | `platform/packages/` | payment_fee / cost_report | 0 命中 |

**入口（option）身份复用**：`PaymentMethod#payment_options/effective_payment_option/effective_payment_options/option_identifier`（读模型，D1/D8/D16）+ 序列化口径 `option_id`/`method_key`/`display_name`。**注意**：逐笔支付**未持久化**所选 option（`pallastrade_payments` 无 option/method_key 列），因此报表的入口维度采用「**当前映射口径**」（按 `payment_method` 当前生效 option 归因），并在报表口径说明中显式标注 + 留待后续切片（若需逐笔历史归因需在支付落库时记录 option）。

**实际费用复用**：`pallastrade_payout_lines.fee_amount`（D13b 已落库）→ 作为 `actual_fee` 与模型费用对比。

**后台模式复用**：`RiskListsController`（D15）的 `audit_actor` 自定义、`send_data` CSV 导出、`filter_by` + 计数同源、`data-count-scope` 卡片模式。

## 7. 技术影响

- **新增表**：`pallastrade_payment_fee_policies`（1 张，迁移 `backend/db/migrate/20260916230000_create_pallastrade_payment_fee_policies.rb`）
- **新增模型**：`PallasTrade::PaymentFeePolicy`
- **新增服务**：`Payments::Fees::Resolver`、`Payments::Fees::Calculate`、`Payments::Costs::Report`
- **新增后台**：`PaymentFeePoliciesController`、`PaymentCostsController` + 视图 + 路由 + 导航（1 项）+ 权限 + 审计事件
- **i18n**：gem `en.yml` + host `zh-CN`
- **不改动**：支付创建/完成链路、webhook、账本、库存、既有 API 序列化
- **下游**：§67.1 成本路由（D11 v2）将以 `Payments::Fees::Resolver` + `Costs::Report` 为成本数据源

## 8. 测试计划

| 层 | 文件 | 覆盖 |
|---|---|---|
| Model | `spec/models/pallastrade/payment_fee_policy_spec.rb` | AC-1 |
| Service | `spec/services/pallastrade/payments/fees/resolver_spec.rb` | AC-2/3 |
| Service | `spec/services/pallastrade/payments/fees/calculate_spec.rb` | AC-4/5 |
| Service | `spec/services/pallastrade/payments/costs/report_spec.rb` | AC-6/7/8/9/10/14 |
| Request | `spec/requests/pallastrade/admin/payment_fee_policies_spec.rb` | AC-11 |
| Request | `spec/requests/pallastrade/admin/payment_costs_spec.rb` | AC-12 |
| Regression | `spec/requests/pallastrade/admin/navigation_consistency_spec.rb` | AC-13 |

**Verifier**：`harness verify d13c-cost-report-rspec`（注册于 `harness.config.mjs`）

## 9. 收口清单

- [x] PRD approved → 用户确认（2026-09-16「确认，按此实施」）
- [x] gate + REQ（含 Skill 表）
- [x] 迁移 + 模型 + 服务 + 后台 + i18n
- [x] 7 个 spec 文件 + verifier 注册
- [x] AGENTS §6 新增行 + GS-155 场景
- [x] 知识同步（Skills / 业务方案 §70.3 / §78 D13 行）
- [x] `generated:check` / `eval-ai --scenarios` / `prd-status-sync --check`
- [x] dev 冒烟：费率解析 + 报表聚合 + 下钻 + 零资金副作用

### 9.1 实施记录（2026-09-16）

**交付物**

| # | 类型 | 路径 |
|---|---|---|
| 1 | 迁移 | `backend/db/migrate/20260916240000_create_pallastrade_payment_fee_policies.rb` |
| 2 | 模型 | `backend/pallastrade_gems/pallastrade_core/app/models/pallastrade/payment_fee_policy.rb` |
| 3 | 服务 | `.../app/services/pallastrade/payments/fees/resolver.rb`（含 `Resolver::Context`） |
| 4 | 服务 | `.../app/services/pallastrade/payments/fees/calculate.rb` |
| 5 | 服务 | `.../app/services/pallastrade/payments/costs/report.rb` |
| 6 | 后台 | `.../pallastrade_admin/app/controllers/pallastrade/admin/{payment_fee_policies,payment_costs}_controller.rb` |
| 7 | 视图 | `.../views/pallastrade/admin/payment_fee_policies/{index,new,edit,_form}.html.erb`、`.../payment_costs/index.html.erb` |
| 8 | 接线 | gem `config/routes.rb`（`payment_costs` / `payment_fee_policies`）、导航 Orders 子项 position 60/61、`permission_sets/configuration_management.rb`（`can :manage, PallasTrade::PaymentFeePolicy`） |
| 9 | i18n | gem `config/locales/en.yml`（`payment_costs` / `payment_fee_policies`）+ `backend/config/locales/admin_payment_fee_costs.zh-CN.yml` |
| 10 | 工厂 | `.../testing_support/factories/payment_fee_policy_factory.rb` |
| 11 | 测试 | `spec/models/pallastrade/d13c_payment_fee_policy_spec.rb`、`spec/services/pallastrade/payments/fees/d13c_{resolver,calculate}_spec.rb`、`spec/services/pallastrade/payments/costs/d13c_report_spec.rb`、`spec/requests/pallastrade/admin/d13c_{payment_fee_policies,payment_costs}_spec.rb`、`navigation_consistency_spec.rb`（子项 + 双语 label 回归） |
| 12 | Harness | `harness.config.mjs` verifier `d13c-cost-report-rspec`、`harness/scenarios/scenarios.json` GS-155、`AGENTS.md` §6 行 |

**口径决策（实施中确定，与 §3 一致）**

- 解析优先级 `method > provider > store > global`；同优先级 `effective_from` 更晚者优先，再取 id 更大者（`by_priority` 单一 SQL 口径，Resolver 与页面共用）。
- `min_fee`/`max_fee` **只作用于费率类分量之和**（percent + platform + cross-border + conversion），固定费在封顶之后相加。
- 跨境/转换「**不猜**」：策略声明了 `home_country`/`settlement_currency` 而本地拿不到对照值 → 不计费 + signal（计入未定价原因）。
- 入口身份 = `PaymentMethod#effective_payment_option['kind']`（与 API 序列化器同源）；**未选项化**的支付方式返回其 default kind（如 `check`/`bogus`），已在报表页口径说明中标注「入口按当前映射归因」。
- `global`/`store` 适用范围下 `scope_id` **归一为 NULL**（不报错），`provider`/`method` 必填。
- 报表统计域：本店 + `Payment.completed` + `[from, to)`；成本基数 = `payment.amount`；单均成本按**订单去重**。
- 实际费用来源：`payout_lines.fee_amount`（`refund_id` 为空的行，单次查询建索引），偏差 = 实际 − 模型（分析口径，非资金事实）。

**实施中发现并修复的问题**

1. 报表首版用 `joins(:order)` + `includes(order:)`，预加载被丢弃 → **每笔支付一次查询**（10 笔 13 次查询）；改为 `where(order_id: 子查询)` + `includes`，查询数恒定（AC-14 断言）。
2. `PallasTrade::CSV` 命名空间遮蔽 Ruby 标准库 → 控制器内改用 `::CSV.generate`。
3. admin 报表页汇总卡 HTML 含换行缩进 → 断言改为正则（`data-cost-metric="fee">\s*4\.0`）。
4. CSV 增加 `entry_key`（入口键）列，便于按入口做成本路由分析。

**验证**

- `harness verify d13c-cost-report-rspec`：**162 examples, 0 failures**（7 个 spec 文件，含导航一致性回归）
- `harness generated:check`：no drift；`harness eval-ai --scenarios`：**156/156 valid**（含新增 GS-155）；`node scripts/ci/prd-status-sync.mjs --check`：167/167 一致
- dev 冒烟：费率解析优先级（method > global）→ 单笔分量计算 → 跨境基准不可证则不计费 → 报表汇总/入口排名/**下钻条数 == 入口 payment_count** → 实际 vs 模型偏差 → 跨店隔离 → 零资金副作用（payments/refunds/ledger/inventory 计数与金额零变化）→ 撤销后回落 global → `/up` 与 `/admin/payment_costs`、`/admin/payment_fee_policies` 可达


## 10. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-09-16 | 初稿（D13 切片3，业务方案 §70.3） |
| 2026-09-16 | 实施完成：费率策略 + 解析/计算/报表三服务 + 后台两页 + 7 spec（162 例绿）；§9.1 回填 |
