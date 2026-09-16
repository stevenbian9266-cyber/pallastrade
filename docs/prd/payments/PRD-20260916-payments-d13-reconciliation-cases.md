# PRD-20260916-payments-d13-reconciliation-cases

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-16 |
| 来源 | 需求：D13 切片1 对账差异队列 —— 只读对账结果 → 可指派/可备注/可关单的差异案例 + 后台工作台 + CSV 导出（业务方案 §78-D13 / §70.1） |
| 分类 | payments |
| 关联 Skill | `pallastrade-payments`、`pallastrade-admin`、`pallastrade-data-model`、`pallastrade-security`、`pallastrade-testing` |
| 关联 PRD | `PRD-20260906-payments-fin-p4-6-…`（源级只读对账）、`PRD-20260906-payments-fin-p4-7-…`（交易级只读对账，本批数据源）、`PRD-20260906-payments-fin-p4-8-…`（sweeper/runbook，本批接入点） |
| 需求类型 | 新功能 |

## 1. 背景与目标

- **一句话需求原文**：D13 对账与结算 —— 对账差异队列 + 结算台账导入匹配 + 手续费/成本报表 + 汇率快照（本切片：**对账差异队列**）。
- **背景（代码事实）**：
  - **已有（P4-6/7/8）**：`Reconciliations::{ReconcilePayment,ReconcileRefund,ReconcileTransaction}` 是**只读、幂等**的对账纯函数，输出 `SourceResult` / `TransactionResult`（status ∈ PENDING/MATCHED/MISMATCH/NEEDS_ATTENTION/NOT_APPLICABLE/UNSUPPORTED + §42 原因码）；`ReconcileSweeperJob` 周期扫描：journal-missing 自动 repair，**mismatch / needs_attention / pending 仅计数 + warn 日志**；runbook（`docs/operations/financial-reconciliation-runbook.md`）用 rake 命令人工介入。
  - **缺口（grep 事实）**：`TransactionResult`/`SourceResult` 注释明确「**不落表**（P4 §25：P4-8 决定 reconciliation 持久化形态）」；6 层搜索 `reconciliation_case|ReconciliationCase` **零命中**；admin 有 `payments_ops` / `refunds_ops` / `disputes_ops` 三个**只读**财务页，**无**对账队列页。⇒ 差异无队列、无指派、无备注、无状态流转、无法导出，只能靠日志 + rake 命令。
- **目标**：把「只读对账结论」变成**持久、可运营**的差异案例（case）：自动生成/自动销案、可指派责任人、可备注、可标记「已解释/已修正/已忽略」、可按条件筛选并**导出 CSV** 交财务归档。
- **成功指标**：① 对账发现的差异在 sweeper 运行后 **100% 进入队列**（每交易每个差异签名 1 条，幂等不重复）；② 差异消失后自动销案（人工已判定解释/忽略的**不被覆盖**）；③ 后台可按 status/类型/provider/责任人筛选 + CSV 导出（与筛选一致）；④ 所有案例动作写审计，且**零资金副作用**。

## 2. 用户故事 / 场景

- 作为**财务运营**，对账发现金额/状态差异时我要看到一个队列（而不是日志），并能把案例**指派**给同事。
- 作为**财务运营**，我要在案例上写**备注**（沟通过程/凭证），并把案例标记为「已解释」「已修正」「已忽略」。
- 作为**财务主管**，我要按状态/差异类型/provider/责任人筛选并**导出 CSV** 交给外部审计。
- 场景：① 交易出现 AMOUNT_MISMATCH → sweeper 落案例（open）→ 人工指派 + 备注 → 标记已修正；② 差异在下一次对账中消失 → 案例**自动**销案（fixed/auto）；③ 人工已忽略的案例：即使差异仍在也不重开；④ 差异签名变化（新原因码）→ 旧案例自动销案 + 新案例入队；⑤ 筛选 + 导出与页面口径一致。

## 3. 功能需求（FR）

- **FR-001　案例模型（持久化）** —— 新表 `pallastrade_reconciliation_cases` + 模型 `PallasTrade::ReconciliationCase`：
  - 归属：`store_id`（必填）、`transaction_id`（可空 FK）、`payment_id` / `refund_id`（可空 FK，源级案例）。
  - 事实：`kind`（`transaction` / `payment` / `refund`）、`status`（`open` / `investigating` / `explained` / `fixed` / `dismissed`）、`difference_type`、`severity`（`critical` / `attention` / `info`）、`reason_codes`（jsonb 数组）、`provider`、`currency`、`expected_amount` / `observed_amount`、`summary`（jsonb 快照）、`detected_at` / `last_seen_at` / `occurrences`、`resolved_at` / `resolution_source`（`human` / `auto`）。
  - 运营：`assignee_id`（可空）、`dedupe_key`（**唯一**）。
  - 备注：新表 `pallastrade_reconciliation_case_notes` + 模型 `ReconciliationCaseNote`（`case_id` / `author_id` / `body`）——备注**留痕**，不覆盖历史。
  - 语义：`difference_type` 由原因码**确定性**映射（amount_mismatch / allocation_mismatch / refund_mismatch / one_sided / settlement_pending / journal_missing / provider_issue / duplicate / needs_attention / unsupported）；`severity`：MISMATCH → critical，NEEDS_ATTENTION → attention，PENDING/UNSUPPORTED → info。
- **FR-002　同步服务（唯一写入口）** —— `Reconciliations::SyncCases.call(transaction:)`：
  - 调既有只读 `ReconcileTransaction` → 结果 MATCHED/NOT_APPLICABLE 时**自动销案**该交易下仍开放且未被人工判定的案例（`fixed` + `resolution_source: 'auto'`）；
  - 差异态 → 按 `dedupe_key = "txn:<txn_id>:<signature>"`（signature = 排序去重后的原因码，空则 `NEEDS_ATTENTION`）**upsert**；已存在且人工已判定（explained/dismissed/fixed）→ **不动**（只 `last_seen_at`/`occurrences`）；
  - 同一交易旧签名仍在开放态、而新签名出现 → 旧案例自动销案（finding superseded）；
  - 幂等：重复调用不产生重复案例、不重复销案；**零资金副作用**（只写案例表 + 审计）。
- **FR-003　巡检接入** —— `ReconcileSweeperJob` 在既有 ReconcileTransaction 之后调用 `SyncCases`（保留 journal-missing 自动 repair 与结构化 metrics 日志，行为不变）；新增 metrics 字段 `cases_opened` / `cases_auto_closed`。
- **FR-004　后台工作台** —— `/admin/reconciliation_cases`（新控制器 `ReconciliationCasesController`）：
  - **index**：筛选 status / kind / difference_type / severity / provider / assignee / 交易号或订单号搜索；状态计数徽标；分页；
  - **show**：案例全字段 + 关联交易/支付/退款链接 + 原因码 + 金额对照 + 备注时间线 + 审计轨迹；
  - **动作**（全部 `authorize! :update` + 审计）：`assign`（指派给自己或指定用户）、`note`（追加备注，必填正文）、`mark_explained`、`mark_fixed`、`dismiss`（必填原因）、`reopen`；
  - **export**：`GET /admin/reconciliation_cases/export.csv` —— 导出**当前筛选**结果（同 index 口径），上限 10,000 行并在响应头/日志注明截断。
- **FR-005　权限与导航** —— 权限 `can :manage, PallasTrade::ReconciliationCase`（`configuration_management` 权限集，默认管理员角色）；导航「Orders → 对账队列」（`if: can?(:manage, …)`），导航一致性 spec 通过。
- **FR-006　零资金副作用（硬约束）** —— 案例队列**绝不**：修改 Payment/Refund/Transaction/库存/订单/Journal、触发 provider 调用或自动资金动作（与 P4 §44/§46、runbook 边界一致）；系统只会**新建/更新案例行**。
- **FR-007　降级与性能** —— 后台页面任一依赖（关联交易缺失、provider 数据缺失）降级为占位而非 500；index 走索引（status/provider/assignee/transaction_id）；export 有界；sweeper 每交易 ≤ 常数级查询。

## 4. 非功能需求（NFR）

- **安全**：所有案例动作写 `Audit`（actor = 当前后台用户 / 系统）；不落 provider 凭证与 payload 全文；`dismiss` 必须填原因。
- **兼容**：新增表 + 新增页面，**不改**既有对账语义/状态机/API v3 契约（无 API 端点变更）；对既有行为零回归（sweeper 的 repair 分支不变）。
- **数据**：迁移仅建 2 张新表 + 索引（无回填、无破坏性变更）。
- **范围纪律（本切片不做）**：§70.2 结算（payout）台账导入、§70.3 费率模型与成本报表、§70.4 汇率快照 —— 留待 D13 后续切片。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001** ← FR-001：模型口径正确 —— `difference_type` / `severity` 由 status+原因码确定性映射；`dedupe_key` 唯一约束生效；备注关联可读（时间序）。
- **AC-002** ← FR-002：`SyncCases` 幂等 —— 同一交易重复同步不产生重复案例；`occurrences`/`last_seen_at` 递增。
- **AC-003** ← FR-002：差异消失 → 自动销案（`fixed` + `resolution_source: auto`）；**人工已判定（explained/dismissed）不被覆盖**。
- **AC-004** ← FR-002：签名变化 → 旧案例自动销案 + 新案例入队（不并存两条开放案例）。
- **AC-005** ← FR-003：`ReconcileSweeperJob` 运行后队列与对账结论一致（metrics 含 `cases_opened`/`cases_auto_closed`），且 journal repair 行为不变。
- **AC-006** ← FR-004：index 筛选（status/类型/severity/provider/责任人/搜索）与计数正确；show 渲染案例 + 备注时间线，缺失关联时页面仍 200。
- **AC-007** ← FR-004：四个状态动作 + 指派 + 备注可用，均写审计；`dismiss` 缺原因不改变状态。
- **AC-008** ← FR-004/FR-007：CSV 导出口径与筛选一致、有列头、有上限保护；无权限用户被拒。
- **AC-009** ← FR-006：案例动作**零资金副作用** —— 执行前后 Payment/Refund/Transaction/Journal 行数与关键字段不变。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | `Reconciliation` / `reconciliation_case` | 无命中 | ❌ 未满足 |
| Core | `pallastrade_core/app/` | `reconciliations` / `case` | `services/pallastrade/reconciliations/*`（7 个只读服务/VO：`reconcile_{payment,refund,transaction,dispute}`、`source_result`、`transaction_result`、`transaction_financial_summary`）、`jobs/…/reconcile_sweeper_job.rb`；**无**案例模型/表 | ⚠️ 部分（数据源已有，持久化与队列缺） |
| API | `pallastrade_api/app/` | `reconcil` | 仅无关命中（role_grant_guard 等）；**无**对账端点 | ✅ 无需变更（后台 HTML 页面；API v3 零改动） |
| Admin | `pallastrade_admin/app/` | `reconcil` / finance ops | `payments_ops_controller` / `refunds_ops_controller` / `disputes_ops_controller`（只读财务页范式：`ResourceController` + `TableConcern` + Ransack + show 内联只读对账、异常降级 nil）；**无**对账队列页 | ⚠️ 部分（需新增控制器/视图/权限/导航） |
| Storefront | `storefront/src/` | — | 前台不涉及财务运营 | ✅ 无需变更 |
| Platform | `platform/packages/` | `reconcil` | 无命中 | ✅ 无需变更 |

**结论**：承载点 = **Core**（案例表/模型 + `SyncCases` 唯一写入口 + sweeper 接入）+ **Admin**（工作台页面/动作/CSV/权限/导航）；API / Storefront / Platform **零改动**；复用 P4 只读对账结论作为唯一数据源，不新建第二套对账逻辑。

## 7. 技术影响

- **Core**：2 迁移（`pallastrade_reconciliation_cases`、`pallastrade_reconciliation_case_notes`）；2 模型（`ReconciliationCase`、`ReconciliationCaseNote`）；1 服务（`Reconciliations::SyncCases`）+ 1 常量映射（差异类型/严重级）；`ReconcileSweeperJob` 接入 + metrics 扩展。
- **Admin**：`ReconciliationCasesController`（index/show/actions/export）+ 2 视图 + 导航项 + 权限集 + i18n（gem en + 宿主 zh-CN）。
- **数据库**：只新增表与索引；无回填。
- **测试**：模型、同步服务（幂等/销案/签名变化/人工判定保护）、sweeper 回归、admin 请求（筛选/动作/导出/权限/降级）。

## 8. 测试计划

| 层 | 文件 | 覆盖 |
|---|---|---|
| 模型 | `backend/spec/models/pallastrade/d13_reconciliation_case_spec.rb` | AC-001 |
| 服务 | `backend/spec/services/pallastrade/reconciliations/d13_sync_cases_spec.rb` | AC-002/003/004/009 |
| 作业 | `backend/spec/jobs/pallastrade/reconciliations/reconcile_sweeper_job_spec.rb`（扩展） | AC-005 |
| 请求 | `backend/spec/requests/pallastrade/admin/d13_reconciliation_cases_spec.rb` | AC-006/007/008 |
| 回归 | `harness verify finance-reconciliation-rspec`（P4 全套） | 零回归 |

## 9. 收口清单

- [x] 本 PRD（approved → done）
- [x] REQ：`harness/requirements/REQ-20260916-d13-reconciliation-cases.md`
- [x] gate + prep 清理
- [x] 用户确认：用户 2026-09-16「继续」（承接 §78 D13 批次）
- [x] 知识同步：`pallastrade-payments` / `pallastrade-admin` Skill + runbook §8 + AGENTS §6 verifier 行 + 场景库 GS-143 + 业务方案 §70 回写

### 9.1 实施记录（2026-09-16，切片1）

| 项 | 内容 |
|---|---|
| 数据库 | 新迁移 `20260916170000_create_pallastrade_reconciliation_cases.rb`（2 表 + 唯一键/组合索引；无回填） |
| Core 模型 | `ReconciliationCase`（映射/签名/状态机/`filter_by`/`search_by`）+ `ReconciliationCaseNote` |
| Core 服务 | `Reconciliations::SyncCases`（唯一写入口：upsert / 触碰 / 自动销案 / 签名取代；并发唯一键回退） |
| 巡检 | `ReconcileSweeperJob` 接入 `SyncCases`（异常降级 warn 不中断）+ metrics `cases_opened`/`cases_auto_closed` |
| Admin | `ReconciliationCasesController`（index/show/export + 7 个动作）+ 2 视图 + 路由 + 导航（Orders→ 对账队列，position 55）+ 权限 `can :manage, PallasTrade::ReconciliationCase` + i18n（gem en + 宿主 zh-CN） |
| 验证 | 新增验证器 `d13-reconciliation-cases-rspec`（39 例全绿）+ P4 回归 `finance-reconciliation-rspec` ✅ + 导航一致性回归（D12 verifier）✅ + `nav-validate-static` ✅ |
| 决策 1 | **关联名 `commerce_transaction`**：`belongs_to :transaction` 与 ActiveRecord 内建 `transaction` 方法冲突（实测 ArgumentError） |
| 决策 2 | **provider 口径**走 `PaymentMethod#default_option_kind`（不假设每个网关都实现 `api_type`，Bogus 实测无此方法） |
| 决策 3 | **export 与 index 共用 `filters` 备忘**：export 不先设 `@filters` 会因 `**nil` 静默不过滤（实测命中） |
| 决策 4 | 自动逻辑只处理**开放态**；人工判定（explained/fixed/dismissed）永不被覆盖（即使差异消失 / 签名取代） |
| 延后 | §70.2 结算（payout）台账、§70.3 费率与成本报表、§70.4 汇率快照 |

## 10. 变更记录

| 版本 | 日期 | 变更 |
|---|---|---|
| 0.1 | 2026-09-16 | 初版（切片1：对账差异队列 + 工作台 + CSV；结算台账/费率成本/汇率快照留后续切片） |
| 1.0 | 2026-09-16 | **实施完成（切片1）→ done**：案例模型（2 表）+ `SyncCases`（幂等/自动销案/签名取代/零资金副作用）+ sweeper 接入 + 后台工作台（筛选/动作/CSV/权限/导航）+ 验证器 39 例全绿 + P4 回归无漂移 | AI |
