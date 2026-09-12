# PRD-20260912-payments-dsp-p7-5-dispute-deadline-sweep（争议证据期限扫描与告警）

| 元数据 | 值 |
|---|---|
| 状态 | approved（2026-09-12 用户显式确认实施） |
| 创建日期 | 2026-09-12 |
| 来源 | 用户指令「继续」→ 承接 DSP-P7-4 的下一切片（P7-4 PRD 已显式预留 Sweeper） |
| 分类 | payments（`harness prd new` 自动判定，关键词「退款」命中） |
| 关联 Skill | `pallastrade-payments`、`pallastrade-data-model`、`pallastrade-events-webhooks`、`pallastrade-testing` |
| 关联 REQ | `REQ-20260912-dsp-p7-5-dispute-deadline-sweep.md` |
| 关联 PRD | 源计划 §44/§45；前置：`PRD-20260911-payments-dsp-p7-1-*`（`evidence_due_at` 一等列）、`-p7-4-dispute-evidence-snapshot`（`missing_evidence` 输入） |
| 需求类型 | 新功能（周期 job + 只读扫描；**0 migration**、0 API/UI） |

> **切片定位（源计划 §44/§45）**：`evidence_due_at` 是一等事实；第一版 sweeper 只做 **alert + admin visible + audit**，
> **不自动** submit evidence / accept dispute / refund customer。Admin 展现归 P7-7；收敛动作归 P7-6；证据提交归 P7-8。

---

## 1. 背景与目标

- **一句话需求原文**：「继续」（承接 P7-4 交付后的下一包）。
- **背景**：
  1. **截止日已落库但无人盯**：`pallastrade_disputes.evidence_due_at` 自 P7-1/P7-2 起由 provider 载荷落列，
     但**没有任何机制**在临近截止时提醒——错过了就是默认败诉（资金已扣回）。
  2. **系统里已有 sweeper 惯例可复用**：`PALLAS_CART_SCHEDULE`（`backend/config/sidekiq_schedule.rb` +
     `config/initializers/pallastrade_sidekiq_cron.rb`）已注册 3+ 个周期任务（弃购、交易恢复、库存预留到期、核销到期），
     core gem 也有同类 `ReconcileSweeperJob` 先例——本切片沿用同一模式，不发明新调度。
  3. **告警必须与决策分离**（源计划 §45）：sweeper 只**提示**，绝不自动提交证据/接受争议/退款；
     同时不能"猜"——只有 `evidence_due_at` 存在且未终态的争议才进告警。
  4. **P7-4 已给出缺口清单**：证据快照的 `missing_evidence[]`（无送达证明/无单号/无客户沟通…）正是运营在截止前需要补的项，
     本切片的告警 payload 直接带上它，让提醒可行动。
- **目标**：
  1. 落地 `PallasTrade::Disputes::ScanDeadlines.call(window_hours: 72, now: Time.current)`（**只读**）：
     返回 `{ due_soon: [...], overdue: [...], window_hours:, scanned_at: }`，每项含
     `dispute_id / state / evidence_due_at / hours_remaining / missing_evidence`。
  2. 落地 `PallasTrade::Disputes::DeadlineSweeperJob`：调用扫描 → 逐条发布事件
     `dispute.evidence_due_soon` / `dispute.evidence_overdue` + 结构化日志（供告警/指标消费）；
     **零业务动作**、单条异常隔离、可重跑。
  3. 在 `backend/config/sidekiq_schedule.rb` 登记调度 `dispute_deadline_sweep`（**每日 01:00**，
     `window_hours` 默认 72），避免每小时重复告警造成的噪音。
  4. 不改任何状态机与资金链路；无 migration / API / UI。
- **成功指标**（可验证）：
  1. 给定 3 条争议（未到期 72h 内 / 已逾期 / 终态）→ 只有前两条进入对应桶，终态与无 `due_at` 者被排除；
  2. 扫描**只读**：调用前后 disputes 行数与属性零变化；
  3. job 发布事件数与候选数一致、payload 含 `hours_remaining` 与 `missing_evidence`；
  4. job **不调用**任何 provider 写操作、不改状态（负向断言）；
  5. 回归：P7-1..4 + FIN-P4 specs 全绿；`generated:check` / `doc-impact` 通过。

## 2. 用户故事 / 场景

- 作为**运营/风控**：我希望在证据截止前收到提醒（含还差多少小时、缺哪些材料），以便及时准备应诉。
- 作为**财务**：我希望逾期争议持续可见，避免"错过截止 → 默认败诉"在无人知晓的情况下发生。
- 作为**工程**：我希望 sweeper 绝不替商户做法律/资金决策，且可以安全重跑、单条坏数据不拖垮整批。

| # | 场景 | 类型 | 描述 |
|---|---|---|---|
| S1 | 临近截止 | 正常 | `due_at = now + 48h`，window 72h → 进 `due_soon`，`hours_remaining ≈ 48` |
| S2 | 已逾期 | 异常 | `due_at < now` → 进 `overdue`（持续提醒直到终态） |
| S3 | 边界相等 | 边界 | `due_at == now` → 进 `due_soon`（未逾期），不进 `overdue` |
| S4 | 终态争议 | 边界 | `won/lost/accepted/expired/closed` → 两个桶都不进 |
| S5 | 无截止日 | 边界 | `evidence_due_at` 为空 → 不进任何桶（不猜） |
| S6 | 窗口收窄 | 边界 | `window_hours: 24` → 72h 后的争议被排除 |
| S7 | 单条坏数据 | 异常 | 某条 dispute 在处理时抛错 → 记录日志并继续其余（job 不整体失败） |
| S8 | 重复运行 | 边界 | 同一 `now` 两次扫描结果一致；job 可重跑（无副作用） |
| S9 | 误触发风险 | 安全 | **断言**：job 不提交证据、不接受争议、不触发退款、不改 dispute 状态、不调用 provider |

## 3. 功能需求（FR）

- **FR-P75-01**：`PallasTrade::Disputes::ScanDeadlines.call(window_hours: 72, now: Time.current, limit: 500)`（只读）：
  返回 `ServiceModule::Result`，值 = `{ due_soon: [], overdue: [], window_hours:, scanned_at:, scanned_count: }`。
- **FR-P75-02**：候选筛选——`Dispute.active`（非 `TERMINAL_STATES`）**且** `evidence_due_at` 非空**且** `evidence_due_at <= now + window_hours`；
  排序：`evidence_due_at` 升序（最紧急在前）；`limit` 截断并如实返回 `scanned_count`。
- **FR-P75-03**：分桶——`overdue`（`due_at < now`）/ `due_soon`（`now <= due_at <= now + window_hours`）；
  每项含 `dispute_id`、`state`、`evidence_due_at`、`hours_remaining`（可为负=逾期小时）、`payment_id`、`order_id`、
  `missing_evidence`（复用 `Disputes::BuildEvidenceSnapshot` 的缺失清单；构建失败降级为空数组 + `evidence_unavailable: true`，不阻断扫描）。
- **FR-P75-04**：`PallasTrade::Disputes::DeadlineSweeperJob.perform(window_hours: 72)`：调用扫描 →
  逐条 `publish_event('dispute.evidence_due_soon' | 'dispute.evidence_overdue', { id:, due_at:, hours_remaining:, missing_evidence: })`
  + 结构化 JSON 日志（`{ event:, dispute_id:, state:, due_at:, hours_remaining:, missing_evidence: [] }`）。
- **FR-P75-05**：**零业务动作**——不提交证据、不接受/关闭争议、不退款、不改任何 dispute/payment/order 状态、不调用 provider 写接口（源计划 §45）。
- **FR-P75-06**：异常隔离——单条 dispute 处理异常 → `rescue` + 日志，继续其余；job 整体不 raise（返回 `{ published:, failed:, skipped: }` 摘要）。
- **FR-P75-07**：调度登记——`backend/config/sidekiq_schedule.rb` 新增 `dispute_deadline_sweep`
  （`class: 'PallasTrade::Disputes::DeadlineSweeperJob'`，`cron: '0 1 * * *'`，`queue: 'default'`，`args: [{ 'window_hours' => 72 }]`），
  由既有 `pallastrade_sidekiq_cron.rb` 初始化器自动注册（不新增注册机制）。
- **FR-P75-08**：只读边界——扫描服务零写；job 除事件发布/日志外零写（事件发布是既有机制，不新增表/列）。
- **FR-P75-09**：边界——无 migration、无 API/UI、无自动决策、不改 P7-1..4 既有行为。

## 4. 非功能需求（NFR）

- **只读与幂等**：扫描纯函数（同 `now` 同结果）；job 可重跑，重复运行不产生额外副作用。
- **确定性排序与截断**：`evidence_due_at` 升序 + 稳定 id 次序；`limit` 明确（避免大表全量）。
- **噪音控制**：默认**每日一次**扫描（而非每小时），`window_hours` 可配置；同一争议每日最多一条提醒。
- **隔离**：单条异常不拖垮整批；扫描失败不影响既有链路。
- **性能**：单次查询命中 `index_pallastrade_disputes_on_state_and_evidence_due_at`（已有索引），避免 N+1（`missing_evidence` 逐条构建，`limit` 上限约束）。
- **兼容**：无 schema/API/SDK 变更；不触碰 P7-1..4 行为。

## 5. 验收标准（AC，与测试一一映射）

- **AC-P75-01 ← FR-P75-02/03**：`due_at = now + 48h`（window 72h）→ `due_soon` 且 `hours_remaining` 合理（47.9~48.1）；`due_at < now` → `overdue`。
- **AC-P75-02 ← FR-P75-03**：边界 `due_at == now` → `due_soon`（不进 `overdue`）。
- **AC-P75-03 ← FR-P75-02**：`window_hours: 24` 时 48h 后的争议被排除。
- **AC-P75-04 ← FR-P75-02**：终态（won/lost/accepted/expired/closed）与 `evidence_due_at` 为空的争议均不进桶。
- **AC-P75-05 ← FR-P75-03**：候选项携带 `missing_evidence`（含 `PROOF_OF_DELIVERY_NOT_AVAILABLE` 等）；证据构建失败时降级为 `evidence_unavailable: true` 且不抛错。
- **AC-P75-06 ← FR-P75-04**：job 发布事件数 = 候选数；事件名按桶；payload 含 `id/due_at/hours_remaining/missing_evidence`；结构化日志逐条输出。
- **AC-P75-07 ← FR-P75-05**：**零业务动作断言**——运行前后 dispute 状态/属性与 payment/order/ledger 行数不变；未调用任何 provider 方法（负向断言）。
- **AC-P75-08 ← FR-P75-06**：单条异常隔离（打桩使某条抛错）→ 其余仍处理，job 返回摘要含 `failed: 1`，不 raise。
- **AC-P75-09 ← FR-P75-07**：`PALLAS_CART_SCHEDULE` 含 `dispute_deadline_sweep` 条目（cron `0 1 * * *`、class、args `window_hours=72`）。
- **AC-P75-10 ← FR-P75-01/08**：只读断言——扫描与 job 调用前后 `Dispute`/`Payment`/`Order`/`Refund`/`FinancialLedgerEntry` 行数与属性零变化。
- **AC-P75-11 ← FR-P75-09**：回归——P7-1..4 + FIN-P4 specs 全绿、无既有断言修改（除新增用例文件）。

## 6. 跨层搜索记录（6 层，gate 强制）

关键词：`deadline` / `sweeper` / `evidence_due_at` / `sidekiq-cron` / `Dispute`

| 层 | 路径 | 找到的文件 | 是否满足需求 |
|---|---|---|---|
| App | `backend/app/` | 无 dispute/deadline 命中；**调度配置在宿主层** `backend/config/sidekiq_schedule.rb` + `config/initializers/pallastrade_sidekiq_cron.rb` | ⚠️ 需在宿主 config 登记新 job（既有机制复用） |
| Core | `pallastrade_core/app/` | `jobs/pallastrade/reconciliations/reconcile_sweeper_job.rb`（同类 sweeper 先例）、`services/pallastrade/disputes/*`（P7-1..4）、`models/pallastrade/dispute.rb`（`evidence_due_at` / `TERMINAL_STATES` / `active` scope） | ⚠️ 部分：模型与先例已有，**扫描/告警不存在** → 本切片补 |
| API | `pallastrade_api/app/` | 无命中 | ❌ 本切片无 API 变更（期限可见性归 P7-7） |
| Admin | `pallastrade_admin/app/` | 无命中 | ❌ 本切片无 Admin UI（归 P7-7） |
| Storefront | `storefront/src/` | 无命中 | ❌ 不适用 |
| Platform | `platform/packages/` | 无命中 | ❌ 无 SDK 变更 |

**结论**：扫描/告警能力 6 层均无 → 新增；落点 = `pallastrade_core`（job + 服务）+ 宿主 `backend/config/sidekiq_schedule.rb`（调度登记，先例 `PALLAS_CART_SCHEDULE`）。

## 7. 技术影响

- **代码**：core gem 新增 2 文件（`ScanDeadlines` 服务 + `DeadlineSweeperJob`）+ 宿主 config 1 行条目 + specs。
- **数据**：零 schema 变更（`evidence_due_at` / `state` 已有，且已有复合索引 `index_pallastrade_disputes_on_state_and_evidence_due_at`）。
- **调度**：复用既有 sidekiq-cron 初始化器；每日 01:00（避免每小时告警噪音）。
- **兼容**：不触碰 P7-1..4 行为；事件发布走既有 `PallasTrade::Events`。
- **回滚**：删除调度条目即停（幂等、无数据影响），代码可 revert。
- **风险**：①误把告警当决策（AC-P75-07 负向断言兜住）；②噪音（每日一次 + window 可配）；③大表全量扫描（`limit` + 索引 + `evidence_due_at` 条件）。

## 8. 测试计划（AC ↔ 测试文件）

| AC | 测试文件（新增） | 类型 |
|---|---|---|
| AC-P75-01..05、AC-P75-10 | `backend/spec/services/pallastrade/disputes/scan_deadlines_spec.rb` | 服务/单元 |
| AC-P75-06/07/08 | `backend/spec/jobs/pallastrade/disputes/deadline_sweeper_job_spec.rb` | job（事件/日志/零动作/隔离） |
| AC-P75-09 | 同上（断言 `PALLAS_CART_SCHEDULE` 含条目） | 配置 |
| AC-P75-11 | P7-1..4 + FIN-P4 既有 specs 全量回归 | 回归 |

命令：`docker exec pallastrade-web-1 bash -lc "cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec <files>"`；
全量：注册 verifier `backend-rspec`。

## 9. 文档同步清单（实施后必做）

| 资产 | 计划 |
|---|---|
| `ai/skills/pallastrade-payments/SKILL.md` | 新增 DSP-P7-5 段（扫描分桶/零决策铁律/调度条目/噪音控制） |
| `ai/skills/pallastrade-deployment/SKILL.md` 或 `platform` 文档 | 评估：新增周期任务是否需要运维文档登记（如 sidekiq-cron 清单） |
| `harness/scenarios/scenarios.json` | 新增 GS 场景（期限告警只提示不决策 + 只读幂等） |
| `docs/prd/README.md` | 登记本 PRD 索引行 |
| `ai/skills/pallastrade-data-model/SKILL.md` | 评估后不更新（无 schema 变更） |

## 10. 变更记录

| 日期 | 变更 | 说明 |
|---|---|---|
| 2026-09-12 | 创建（draft） | 承接 P7-4 预留的 Sweeper 切片；源计划 §44/§45；待用户确认后实施 |
| 2026-09-12 | draft → approved | 用户问答工具选择『确认实施 P7-5』；批准证据已记录；Gate `GATE-2026-09-12T13-53-09` preparation 已清；恢复计划 `REC-61c24a36045b15` |
| 2026-09-12 | 实施（待验证） | 新增 `Disputes::ScanDeadlines`（只读分桶扫描 + limit）+ `Disputes::DeadlineSweeperJob`（事件/日志/单条隔离）+ 宿主调度条目 `dispute_deadline_sweep`；域内 54 examples 全绿（含 P7-1..4）；rubocop 干净。实现注释：①边界 `due_at == now` 归 `due_soon`（`hours_remaining = 0.0`）；②扫描从 DB 重载 dispute，故「构建失败降级」用例需对**任意实例**打桩（`allow_any_instance_of`，附加注释）；③调度常量仅 Sidekiq server 进程加载，用例显式 `require config/sidekiq_schedule`。 |
| 2026-09-12 | 既有 spec 触碰（flaky 真根因修复） | verifier 复跑命中 `spec/services/pallastrade/transactions/reserve_inventory_spec.rb` 的**既有 flaky**（与 P7-5 无关）：失败断言 `released.count == 1` 实得 0，说明 order_a 的预留**根本没建**（而非补偿未释放）。**真根因**：`Store#default_stock_location` 取**全局首个** `default: true` 库存点（`store.rb:400-407`），而 `StockReservations::Reserve#select_stock_item` 取 `variant.stock_items.detect { 第一个 active+非缺货+有库存 }` —— DB 中已存在别的默认库存点时两处判断分岐。**修复**：① spec 自己声明为默认库存点（示例内清掉其他 `default` 标记，让工厂建的 stock_item 落在同一位置）；② 收敛变体库存项（保留此前的 `destroy_all`）；③ 补前置断言「本次确实为 order_a 建过 1 条预留」，使未来失败点不再指向错误归因。 |
