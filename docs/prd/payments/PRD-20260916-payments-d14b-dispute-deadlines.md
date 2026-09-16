# PRD-20260916-payments-d14b-dispute-deadlines

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-16 |
| 来源 | 需求：D14 切片2 争议期限提醒与超期处理 —— T-3/T-1 分档告警（不遗漏、不重复）+ 超期自动置 lost（业务方案 §78-D14 / §71.2） |
| 分类 | payments |
| 关联 Skill | `pallastrade-payments`、`pallastrade-admin`、`pallastrade-data-model`、`pallastrade-security`、`pallastrade-testing` |
| 关联 PRD | `PRD-20260916-payments-d14-refund-approval`（切片1：退款审批）、`PRD-20260912-payments-dsp-p7-5-dispute-deadline-sweep`（只读期限扫描底座）、`PRD-20260913-payments-dsp-p7-10-…`（B2/FR-007 提醒与升级订阅者） |
| 需求类型 | 新功能（在既有只读期限扫描上扩展：分档 + 幂等台账 + 超期处理） |

## 1. 背景与目标

- **一句话需求原文**：超期自动置为 lost（§71.2）——「期限提醒：截止前 T-3 天 / T-1 天告警，超期自动置为 lost」。
- **背景（代码事实）**：
  - **已有**：`Disputes::ScanDeadlines`（**只读**扫描 `active` + 有 `evidence_due_at` 的争议，单一 72h 窗口分 `due_soon` / `overdue`，携带 `missing_evidence`）；`Disputes::DeadlineSweeperJob`（每日 01:00，逐条发布 `dispute.evidence_due_soon` / `dispute.evidence_overdue` + JSON 日志，**铁律：不改任何状态**）；`Disputes::DeadlineAlertSubscriber`（due_soon 仅审计；overdue 在不覆盖既有标记前提下写 `attention_reason = 'evidence_overdue'`）。
  - **缺口**：① **无分档**（只有 72h 单窗口，T-3/T-1 不可区分）；② **无幂等档位记忆** —— 每轮 sweeper 都重复发同一档事件的审计（噪音 + 无法回答「这一档提醒过没有」）；③ **无超期处理** —— 逾期只打人工关注标记，**不会**按 §71.2 置 `lost`；④ 后台看不到「谁在 T-3/T-1/已超期」。
- **目标**：把「期限」从**一次性提示**升级为**可追溯、分档、幂等**的提醒 + **策略化**的超期处置：
  1. T-3 / T-1 分档**不遗漏**（达到档位即落台账）且**不重复**（每争议每档仅一次）；
  2. 超期在**显式开启策略**时自动置 `lost`（审计 actor = system；零资金副作用）；
  3. 后台 `disputes_ops` 提供分档看板/筛选与提醒历史。
- **成功指标**：① 同一争议同一档位重复运行 sweeper **不产生第二行台账、不发第二次提醒**；② 跨越档位的争议在**下一次扫描**即落该档（含跳档补齐）；③ `auto_lose_on_overdue` 开启时，超期且**未提交证据**的争议在下一次扫描变 `lost` 且审计可查；关闭时行为与今天一致；④ 后台可按档位筛选并看到提醒历史；⑤ **零资金副作用**（不动 Payment/Refund/Journal/Order/库存，零 provider 调用）。

## 2. 用户故事 / 场景

- 作为**争议运营**，我要在**截止前 3 天与 1 天**各收到一次提醒（含缺失证据清单），且**不重复**提醒已提醒过的档位。
- 作为**争议运营**，我要在后台按 `T-3 / T-1 / 已超期` 筛选，并看到某争议**已经提醒过哪些档**（时间与当时的剩余小时）。
- 作为**风控/财务主管**，我要能选择「超期未提交证据 → 自动置 lost」（默认**关闭**），并在开启后能从审计里追溯每一次自动置 lost。
- 场景：① 争议进入 T-3 窗口 → 落 `t3` 台账 + 发一次提醒；② 再跑一次 sweeper → 无新增、无重发；③ 进入 T-1 → 落 `t1` + 发提醒；④ 超期且策略关闭 → 只升级 `attention_reason`；⑤ 超期且策略开启、未提交证据 → `lost` + 审计；⑥ 已提交证据的超期争议 → **不自动置 lost**（provider 裁决中）；⑦ 终态争议 → no-op。

## 3. 功能需求（FR）

- **FR-001　分档策略（店铺级，唯一口径）** —— 策略存 `Store#private_metadata['dispute_deadline_policy']`，读入口 `PallasTrade::Disputes::DeadlinePolicy.for(store)`：
  - 字段：`tiers_days`（数组，默认 `[3, 1]`；即「截止前 N 天」的档位）、`auto_lose_on_overdue`（布尔，默认 **false**）、`auto_lose_limit`（单轮自动置 lost 上限，默认 100）。
  - 归一化**保守**：非法/空 `tiers_days` → 回默认 `[3, 1]`；`auto_lose_limit` 非法 → 默认 100；`auto_lose_on_overdue` 非真值 → **关闭**（默认关闭 = 行为与今天一致）。
  - 档位键：`t{n}`（如 `t3` / `t1`）+ 特殊档 `overdue`；`tier_for(hours_remaining:)` 返回**已到达的最高档**；`reached_tiers(hours_remaining:)` 返回**所有已到达档位**（按紧迫度升序，用于补齐台账）。
  - 只读、零写库、零 provider I/O。
- **FR-002　分档台账（幂等记忆）** —— 新表 `pallastrade_dispute_deadline_alerts`：`store_id` / `dispute_id` / `tier` / `alerted_at` / `evidence_due_at` / `hours_remaining` / `metadata` / timestamps；
  **唯一键 `(dispute_id, tier)`** —— 「不遗漏」= 达到档位即落行；「不重复」= 同档第二次写入被唯一键挡下（服务内 find_or_create + `RecordNotUnique` 兜底）。
- **FR-003　分档提醒服务 `Disputes::AlertDeadlines`（唯一写入口）** ——
  - 输入：`store:`（可选，缺省全店）/ `now:` / `limit:`；内部用 `ScanDeadlines`（**复用只读扫描**，不另写一套筛选）。
  - 对每个候选争议：计算 `reached_tiers`；对**尚未落台账**的档位建行；
    - **只对「本轮最新到达且未曾提醒」的档位发提醒事件**（`dispute.evidence_deadline_tier`，payload 含 `tier` / `due_at` / `hours_remaining` / `missing_evidence`）；跳档补齐的历史档位仅落台账（`metadata['backfilled'] = true`），**不补发过期提醒**（避免噪音）。
  - 保留对既有事件的兼容：`dispute.evidence_due_soon`（首次进入 due_soon 窗口的那一轮）与 `dispute.evidence_overdue`（首次记录 `overdue` 档的那一轮）**只在有新档位时**发布（收窄既有「每轮都发」的行为 → 记入 PRD §4 兼容说明）。
  - 返回摘要：`{ scanned:, tiers_recorded:, alerted:, auto_lost:, skipped_submitted:, scanned_at: }`。
- **FR-004　超期自动置 lost（策略门控）** —— 策略 `auto_lose_on_overdue` **开启**时：
  - 条件（全部满足）：`evidence_due_at < now`；非终态；**未提交证据**（`evidence_submitted_at` 空 且 无 `evidence_submissions`）；状态 ∈ `opened` / `needs_response` / `under_review`（provider 已进入裁决的 `submitted` **不自动置 lost**）。
  - 动作：`transition_to!('lost')`（沿用模型阶段序，只前进）+ 若 `attention_reason` 为空则置 `evidence_overdue` + 审计 `dispute_auto_lost_overdue`（actor = `system`，metadata：`due_at` / `hours_remaining` / `policy`）。
  - 上限：单轮最多 `auto_lose_limit` 条（防批量误伤，超出记 `metadata['truncated']`）。
  - **关闭时**：保持今天的行为（overdue 只升级 `attention_reason`，由订阅者完成）。
- **FR-005　订阅者扩展** —— `Disputes::DeadlineAlertSubscriber` 新增订阅 `dispute.evidence_deadline_tier`：
  - `tier = overdue` → 打 `attention_reason`（不覆盖既有非空值）+ 审计 `dispute_deadline_tier_alerted`；
  - `t3` / `t1` → 仅审计 `dispute_deadline_tier_alerted`（留痕 + 指标），**不改状态**；
  - 既有两类事件的处理语义**保持不变**（回归保护）。
- **FR-006　后台可见性 `/admin/disputes_ops`** ——
  - **期限看板**（index 顶部）：`T-3` / `T-1` / `已超期` 三档计数（源自台账 + 只读扫描），点击即按档筛选；
  - **列表**：新增「期限」列（分档徽章 + `evidence_due_at` + 剩余小时）；
  - **详情**：显示该争议的分档提醒历史（档位 / 时间 / 当时剩余小时 / 是否 backfill）；
  - 权限沿用 `can?(:manage, PallasTrade::Dispute)`；只读展示，处置动作（提交证据/接受）沿用既有危险操作入口。
- **FR-007　审计与零资金副作用** —— 新审计：`dispute_deadline_tier_alerted` / `dispute_auto_lost_overdue`；spec 断言：全链路**不**改 Payment / Refund / FinancialLedgerEntry / Order / 库存，**不**调 provider，**不**写 funds 时间戳（因此不触发资金入账事件）。

## 4. 非功能需求（NFR）

- **安全**：自动置 lost 是**策略门控**的资金语义动作（默认关闭）；策略改动写审计；单轮上限 + 只处理「未提交证据」的争议，避免误伤。
- **性能**：分档扫描复用 `ScanDeadlines`（既有复合索引 + `limit`）；台账唯一键保证幂等；看板计数用一次聚合查询（避免逐行）。
- **兼容**：既有 `dispute.evidence_due_soon` / `dispute.evidence_overdue` 事件**名称与 payload 不变**，但发布时机收窄为「有新档位时」；`ScanDeadlines` 只读语义不变；订阅者既有行为不变（回归 spec 兜底）。
- **范围纪律（本切片不做）**：§71.3 拒付率看板与卡组织阈值；提醒渠道（邮件/IM/Slack）实际外发（本切片只落台账 + 发内部事件 + 审计）；`expired` 等其它终态语义调整；期限的 provider 二次校验。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001** ← FR-001：策略归一化矩阵（未配置 = 默认 `[3,1]` + auto_lose 关闭；非法 tiers/limit 回落默认；显式开启）；读取零写、零 provider。
- **AC-002** ← FR-002/FR-003：分档计算与台账幂等 —— T-3 窗口落 `t3`、T-1 窗口落 `t1`、超期落 `overdue`；**重复运行不产生重复行/不重复提醒**；**跳档补齐**（首次扫描时已过 T-1 → `t3`+`t1` 都落台账，仅最新档发提醒并标记 backfill）。
- **AC-003** ← FR-003/FR-005：提醒事件（`dispute.evidence_deadline_tier`）只在**新档位**发布；订阅者对 `t3/t1` 仅审计、对 `overdue` 升级 `attention_reason`；既有事件语义回归。
- **AC-004** ← FR-004：策略开启 + 超期 + 未提交证据 → `lost` + 审计（actor system）+ `attention_reason`；**已提交证据 / 终态 / `submitted` 状态不自动置 lost**；策略关闭 → 不改状态；单轮上限生效。
- **AC-005** ← FR-006：后台看板计数与列表筛选一致、详情显示提醒历史；无权限用户被拒。
- **AC-006** ← FR-007：零资金副作用（Payment/Refund/FinancialLedgerEntry/Order 行数与金额不变；无 funds 事件、无 provider 调用）。
- **AC-007** ← FR-003：sweeper 摘要新增指标（`tiers_recorded` / `auto_lost` / `skipped_submitted`）且既有字段保留；既有 DSP-P7-5 扫描/告警 spec 全绿。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | `dispute` / `deadline` | 无命中 | ❌ 未满足 |
| Core | `pallastrade_core/app/` | `deadline` / `evidence_due_at` | `Disputes::ScanDeadlines`（只读扫描，单档 72h）、`Disputes::DeadlineSweeperJob`（只发事件 + 日志）、`Disputes::DeadlineAlertSubscriber`（due_soon 审计 / overdue 打 attention 标记）、`Dispute`（状态机 + `evidence_due_at` + `attention_reason` + `evidence_submissions`） | ⚠️ 部分（有扫描与单档提醒；**缺分档幂等与超期处置**） |
| API | `pallastrade_api/app/` | `dispute` | 无期限相关端点（Dispute 走 admin HTML + provider webhook 入站） | ✅ 无需变更 |
| Admin | `pallastrade_admin/app/` | `dispute` | `disputes_ops_controller`（index/show，只读展示 + 危险操作入口）、`views/…/disputes_ops/{index,show}.html.erb` | ⚠️ 部分（需加分档看板/列/提醒历史） |
| Storefront | `storefront/src/` | — | 不涉及前台 | ✅ 无需变更 |
| Platform | `platform/packages/` | `dispute` | 无命中 | ✅ 无需变更 |

**结论**：承载点 = **Core**（1 表 + 1 策略值对象 + 1 服务 `AlertDeadlines` + sweeper 接入 + 订阅者扩展）+ **Admin**（`disputes_ops` 看板/列/详情历史）；API / Storefront / Platform **零改动**。
**复用而非重写**：分档扫描**复用** `ScanDeadlines`（唯一筛选口径）；`overdue` 的 `attention_reason` 升级**复用**既有订阅者语义；`lost` 转换**复用** `Dispute#transition_to!`（阶段序保护），不新增状态机。

## 7. 技术影响

- **Core**：迁移（新表 `pallastrade_dispute_deadline_alerts` + 唯一键 + 店铺/时间索引）；模型 `DisputeDeadlineAlert` + `Dispute#deadline_alerts`；`Disputes::DeadlinePolicy`（策略值对象）、`Disputes::AlertDeadlines`（唯一写入口）；`DeadlineSweeperJob` 接入 + 摘要扩展；`DeadlineAlertSubscriber` 增事件订阅。
- **Admin**：`disputes_ops_controller` 增期限看板数据与筛选参数；`index`/`show` 视图增列与历史块；i18n（gem en + 宿主 zh-CN）。
- **数据库**：只新增表/索引，不回填、不改既有列。
- **调度**：沿用 `dispute_deadline_sweep`（每日 01:00）；不新增 cron。
- **测试**：策略矩阵 / 分档服务（幂等/补齐/超期/auto-lose 分支/上限）/ sweeper 摘要与事件 / 订阅者扩展与回归 / 后台看板与权限 / 零资金副作用。

## 8. 测试计划

| 层 | 文件 | 覆盖 |
|---|---|---|
| 策略 | `backend/spec/services/pallastrade/disputes/d14b_deadline_policy_spec.rb` | AC-001 |
| 服务 | `backend/spec/services/pallastrade/disputes/d14b_alert_deadlines_spec.rb` | AC-002/003/004/006 |
| Job | `backend/spec/jobs/pallastrade/disputes/d14b_deadline_sweeper_spec.rb` | AC-007/003 |
| 订阅者 | `backend/spec/subscribers/pallastrade/disputes/d14b_deadline_subscriber_spec.rb` | AC-003 |
| 后台 | `backend/spec/requests/pallastrade/admin/d14b_disputes_ops_deadline_spec.rb` | AC-005 |
| 回归 | `spec/services/pallastrade/disputes/scan_deadlines_spec.rb` + `spec/jobs/pallastrade/disputes/deadline_sweeper_job_spec.rb` + `spec/subscribers/pallastrade/disputes/deadline_alert_subscriber_spec.rb` | AC-007 零回归 |

## 9. 收口清单

- [x] 本 PRD（approved → 实施后 done）
- [x] REQ：`harness/requirements/REQ-20260916-d14b-dispute-deadlines.md`
- [x] gate + prep 清理（critical：恢复计划随 gate 记录）
- [x] 用户确认：用户 2026-09-16「继续」（承接 §78 D14 批次）
- [x] 知识同步：`pallastrade-payments`（DSP-P7-5 章节扩展）/ `pallastrade-admin` Skill + `pallastrade-events-webhooks`（新事件）/ `pallastrade-data-model`（新表）+ AGENTS §6 verifier 行 + 场景库 GS-149 + 业务方案 §71.2 回写
- [x] 契约：无需 `generated:check`（零 API 契约变更）；仍跑一次确认无漂移

### 9.1 实施记录（2026-09-16）

| 项 | 结果 |
|---|---|
| 迁移 | `20260916200000_create_pallastrade_dispute_deadline_alerts.rb`（dev + 测试库已 migrate；`schema.rb` 仅含本表变更） |
| Core | `DisputeDeadlineAlert`（唯一键 `(dispute_id, tier)`）/ `Disputes::DeadlinePolicy` / `Disputes::AlertDeadlines` / `DeadlineSweeperJob` 接入 / `DeadlineAlertSubscriber` 分档分支 / `Dispute#deadline_alerts` |
| Admin | `disputes_ops` 看板卡 + `?deadline=` 筛选（**覆盖 `search_collection`**）/ `:deadline_tier` 列（position 27）/ 详情提醒历史卡 / 列表徽章；gem `en.yml` + 宿主 `admin_dispute_deadlines.zh-CN.yml` |
| API / Storefront / Platform | **零改动**（无契约变更） |
| 测试 | `harness verify d14b-dispute-deadlines-rspec` = **41 examples, 0 failures**（含 DSP-P7-5 三份回归）；证据 `EVD-20260916060158-ba2f00c517` |
| 实测语义 | `50h → [t3]`；`10h → [t3, t1]`；`-3h → [t3, t1, overdue]`；重复运行不重复落行 / 不重复发事件 |
| 兼容 | 既有 `dispute.evidence_due_soon` / `dispute.evidence_overdue` 名称与 payload 不变；发布时机收窄为「有新档位时」→ 既有 job spec 改为「放行其它事件名 + 保留原断言」 |
| 修过的坑 | ①`safe_value` 只适用于 outcome（传数组 → `NoMethodError` 被吞 → 静默空列表）；②在 action 内改 `params[:q]` 对筛选**无效**（`load_resource` 已先取 `collection`）→ 改为覆盖 `search_collection`；③台账的 `overdue?` 是实例方法（不是 scope）；④`Audit.record` 的 payload 在 `after`（`actor: 'system'` 时 `actor_type` 为 nil） |

## 10. 变更记录

| 版本 | 日期 | 变更 |
|---|---|---|
| 0.1 | 2026-09-16 | 初版（切片2：T-3/T-1 分档幂等提醒 + 超期策略化自动 lost + 后台分档看板/历史） |
| 0.2 | 2026-09-16 | 实施完成（41 examples 全绿）+ 知识同步 + §9.1 实施记录；状态 → done |
