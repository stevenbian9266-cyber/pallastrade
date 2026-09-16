# REQ-20260916-d13-reconciliation-cases

| 项 | 值 |
|---|---|
| 任务 | D13 切片1 对账差异队列（业务方案 §78-D13 / §70.1） |
| PRD | `docs/prd/payments/PRD-20260916-payments-d13-reconciliation-cases.md` |
| 类型 | feature（standard 风险） |
| 用户确认 | 用户 2026-09-16「继续」（承接 §78 D13 批次） |

## 6 层跨层搜索结果（gate 强制）

| 层 | 路径 | 关键词 | 结果 | 满足 |
|---|---|---|---|---|
| App | `backend/app/` | `Reconciliation` / `reconciliation_case` | 无命中 | ❌ |
| Core | `pallastrade_core/app/` | `reconciliations` / case | 只读服务 7 个 + sweeper（`reconcile_sweeper_job.rb`）；VO 注释明确「不落表」；无案例模型/表 | ⚠️ 部分 |
| API | `pallastrade_api/app/` | `reconcil` | 无对账端点 | ✅ 无需变更 |
| Admin | `pallastrade_admin/app/` | finance ops | `payments_ops` / `refunds_ops` / `disputes_ops`（只读财务页范式）；无对账队列页 | ⚠️ 部分 |
| Storefront | `storefront/src/` | — | 不涉及 | ✅ 无需变更 |
| Platform | `platform/packages/` | `reconcil` | 无命中 | ✅ 无需变更 |

## Skill Consultation Evidence Table（gate 强制，真实结论）

| Skill | 关键结论（本批采用） |
|---|---|
| `pallastrade-payments` | 财务边界铁律：**对账/repair 只写 Journal/案例，绝不触发资金动作**（P4 §44/§46）；只读对账结论（`TransactionResult`/`SourceResult` + §42 原因码）是唯一数据源，禁止再写第二套判定；sweeper 只做安全自动子集（journal missing → repair） |
| `pallastrade-admin` | 财务运营页范式：`<X>OpsController < ResourceController` + `TableConcern` + Ransack 过滤；show 内联只读对账并以 `rescue → nil` 降级（页面恒 200）；导航条目需登记 + `nav-validate`/导航一致性 spec；i18n 同时更新 gem `en.yml` 与宿主 `zh-CN`；admin 路径参数用 **prefixed_id** |
| `pallastrade-data-model` | 新增表须带 `store_id` + 索引（status/provider/assignee/transaction_id）+ 唯一约束（`dedupe_key`）；jsonb 存快照而非重复列；迁移只建表不回填；软删除/审计沿用既有范式（`AuditLog`） |
| `pallastrade-security` | 案例动作 = 财务敏感操作：`authorize! :update` + 审计（actor + 原因）；`dismiss` 必填原因；不落凭证/payload 全文；CSV 导出需权限门禁且不含敏感字段 |
| `pallastrade-testing` | 新功能须注册验证器 + 覆盖幂等/降级/权限；spec 环境无关（不假设预置数据）；`harness evidence` typed evidence |

## 设计要点（实施依据）

1. **唯一写入口**：`Reconciliations::SyncCases.call(transaction:)` —— 读既有只读 `ReconcileTransaction`，写案例表 + 审计；其他任何地方不得直接写案例。
2. **幂等键**：`dedupe_key = "txn:<transaction_id>:<signature>"`，`signature = reasons.sort.uniq.join('+')`（空 → `NEEDS_ATTENTION`）；DB 唯一索引兜底。
3. **自动 vs 人工边界**：自动只做「新建 / 触碰（`last_seen_at`+`occurrences`）/ 自动销案（finding 消失或签名被取代）」；人工状态（`explained` / `fixed(human)` / `dismissed`）**永不被自动逻辑覆盖**。
4. **差异类型映射**（确定性，禁止散落判断）：`AMOUNT_MISMATCH|CURRENCY_MISMATCH → amount_mismatch`；`ALLOCATION_MISMATCH → allocation_mismatch`；`REFUND_MISMATCH → refund_mismatch`；`LOCAL_PAYMENT_MISSING|PROVIDER_PAYMENT_MISSING|LOCAL_*_MISSING → one_sided`；`SETTLEMENT_PENDING → settlement_pending`；`JOURNAL_POSTING_MISSING → journal_missing`；`PROVIDER_UNAVAILABLE|PROVIDER_CONTRACT_UNSUPPORTED → provider_issue`；`UNLINKED_LEGACY_PAYMENT|AMBIGUOUS_CAPTURE → needs_attention`；其余 → `needs_attention`；status UNSUPPORTED → `unsupported`。
5. **严重级**：MISMATCH → `critical`；NEEDS_ATTENTION → `attention`；PENDING / UNSUPPORTED → `info`。
6. **备注留痕**：独立表 `ReconciliationCaseNote`（author + body + created_at），不做就地覆盖。
7. **CSV**：`send_data ::CSV.generate(...)`（stdlib，范式见 `pallastrade_api/…/imports_controller.rb#template`），上限 10,000 行并 `Rails.logger.warn` 截断。
8. **零资金副作用**：案例动作/同步只写 `pallastrade_reconciliation_cases*` + `AuditLog`；spec 断言 Payment/Refund/Order/Journal 行数与关键字段不变。

## 切片拆分

- 切片 1（本批）：案例模型 + 同步服务 + sweeper 接入 + 后台工作台（index/show/动作/CSV）+ 权限导航 + 验证器。
- 后续：§70.2 payout 台账导入匹配、§70.3 费率模型与成本报表、§70.4 汇率快照与加点。

## 实施记录（2026-09-16，切片1 完成）

- **改动清单**
  - 迁移：`backend/db/migrate/20260916170000_create_pallastrade_reconciliation_cases.rb`（2 表 + 唯一键/组合索引）。
  - Core 模型：`reconciliation_case.rb`（`KINDS/STATUSES/DIFFERENCE_TYPES/SEVERITIES`、`REASON_DIFFERENCE_TYPES` 映射、
    `difference_type_for` / `severity_for` / `signature_for` / `dedupe_key_for`、`close!` / `reopen!` / `assign_to!`、
    `filter_by` / `search_by`）；`reconciliation_case_note.rb`。
  - Core 服务：`reconciliations/sync_cases.rb`（唯一写入口；`save_case` 并发唯一键回退 + warn）。
  - 巡检：`reconciliations/reconcile_sweeper_job.rb`（`sync_cases` 辅助 + metrics 两字段；异常降级不中断）。
  - Admin：`reconciliation_cases_controller.rb`（index/show/export/assign/note/mark_investigating/mark_explained/mark_fixed/dismiss/reopen）、
    `config/routes.rb`、`views/.../reconciliation_cases/{index,show}.html.erb`、导航项（Orders→对账队列 position 55）、
    `permission_sets/configuration_management.rb`（`can :manage, PallasTrade::ReconciliationCase`）、
    i18n（gem `en.yml` + 宿主 `config/locales/admin_reconciliation_cases.zh-CN.yml`）。
  - 规格：`spec/models/pallastrade/d13_reconciliation_case_spec.rb`、`spec/services/pallastrade/reconciliations/d13_sync_cases_spec.rb`、
    `spec/jobs/pallastrade/reconciliations/reconcile_sweeper_job_spec.rb`（+2 例）、`spec/requests/pallastrade/admin/d13_reconciliation_cases_spec.rb`、
    `spec/requests/pallastrade/admin/navigation_consistency_spec.rb`（Orders 子项 + reconciliation_cases）。
  - 验证器：`harness.config.mjs` 注册 `d13-reconciliation-cases-rspec`（39 例全绿）+ P4 回归 `finance-reconciliation-rspec` ✅。
- **决策与偏差**
  1. `belongs_to :commerce_transaction`（`transaction` 与 AR 内建方法冲突）。
  2. provider 口径统一走 `PaymentMethod#default_option_kind`（网关不保证实现 `api_type`）。
  3. `filters` 备忘供 index/export 共用（否则 export `**nil` 静默不过滤）。
  4. 自动逻辑只动开放态；人工判定不可覆盖（差异消失/签名取代都不覆盖）。
  5. 取消原计划中的「源级 payment/refund 案例」细化写入：`kind` 列已预留（transaction/payment/refund），
     本切片只从交易级结果建案（`difference_type` 已精确到原因码），源级建案作为后续切片按需开启。
- **延后**：§70.2 payout 台账、§70.3 费率与成本报表、§70.4 汇率快照。
