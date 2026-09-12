# PRD-20260912-payments-dsp-p7-6-dispute-recovery（争议收敛动作 / Dispute Recovery）

| 元数据 | 值 |
|---|---|
| 状态 | done（2026-09-12 实施 / 验证 / 知识同步完成；已提交 `a455bb13`） |
| 创建日期 | 2026-09-12 |
| 来源 | 用户指令「继续」→ 承接 DSP-P7-5 的下一切片（P7-0 FR-006；源计划 §47–§53） |
| 分类 | payments（`harness prd new` 自动判定，关键词「退款」命中） |
| 关联 Skill | `pallastrade-payments`、`pallastrade-data-model`、`pallastrade-events-webhooks`、`pallastrade-testing` |
| 关联 REQ | `REQ-20260912-dsp-p7-6-dispute-recovery.md`（gate 时生成） |
| 关联 PRD | 源计划 §47–§53；前置：`PRD-20260911-payments-dsp-p7-1-*`（durable 模型 + `attention_reason`）、`-p7-2-*`（`ResolveFact` 裁决 / `stale_local` 输入）、`-p7-3-*`（`PostDispute` 幂等入账 + `ReconcileDispute` 对账）、`-p7-5-*`（sweeper + 调度先例） |
| 需求类型 | 新功能（收敛服务 + 批量 job；**0 migration**、0 API/UI） |

> **切片定位（源计划 §47–§53）**：`Disputes::Recover` / `RecoverJob` / `RecoverSweeperJob`。
> Recovery 的输入**必须是 Facts**（本地 Dispute + provider 当前只读快照 + FinancialFact + Journal + Reconciliation），
> 决策只有五种：**repair local lifecycle / repair missing financial fact / repair journal / repair reconciliation / manual review**。
> 铁律：不因 `lost`/`mismatch`/`withdrawal` **重新扣款**（§49）；不为争议**自动退款**（§50）；
> 乱序事件（`lost` 先到、`created` 迟到）**no-op + audit**（§51）；漏事件由 `fetch_dispute → 单调收敛` 兜底（§52）；
> 双层幂等（`WebhookEvent(provider, provider_event_id)` + `Dispute(provider, provider_dispute_reference)`，§53）。
> **下一片**：P7-7 Admin Console 展现；P7-8 多 provider + 证据提交。

---

## 1. 背景与目标

- **一句话需求原文**：「继续」（承接 P7-5 交付后的下一包；P7-0 FR-006 = Dispute Recovery）。
- **背景**：
  1. **裁决有了，但没人收敛**：P7-2 已能把 provider 权威状态与本地状态的差异判成 `stale_local` / `stale_provider` / `conflict`
     （`DisputeFact::ATTENTION_RESOLUTIONS`），P7-5 只是把它**告警**出去；**没有任何机制**把 provider 的当前真相
     收敛回本地（源计划 §52 Missing Event Recovery：「不依赖必须收到每一个 webhook」）。缺事件 → 本地永远停在 `opened`，
     运营看到的是错的终局（资金已扣回但系统认为还在应诉期）。
  2. **对账能识别缺口，但没人补**：P7-3 `ReconcileDispute` 能判 `journal_missing`，但 subscriber 吞异常窗口 /
     部署中断 / 人工干预都可能让「已证实的资金事实」永久缺账（`funds_withdrawn_at` 有值、账本无行进）。
  3. **人工通道至今为空**：P7-1 起就落 `attention_reason`（`unlinked_payment` / `non_positive_amount` / `invalid_transition`），
     但**没有任何消费方**；P7-2 PRD 明确「`attention_reason` 扩展（当前无 writer，延后至 P7-6）」。冲突/孤儿账行需要人类裁决。
  4. **收敛必须受限**（源计划 §49/§50）：任何修复都**不得**「重新扣款」「自动退款」「新建 Payment」「改 order/inventory/
     CommerceTransaction」；只允许 **单调前进 + 幂等补记 + 标记人工**——这是本切片全部的动作集合。
  5. **原语已齐，只缺编排**：`ResolveFact`（只读裁决）/ `ReconcileDispute`（只读对账）/ `PostDispute`（幂等入账，
     含 `skip_reason` 封闭枚举）/ `Dispute#transition_to!`（单调状态机 + `InvalidTransition`）/ sidekiq-cron 调度（P7-5 先例）。
     本切片**不新增任何事实来源**，只做决策编排与受限执行。
- **目标**：
  1. 落地 `PallasTrade::Disputes::Recover.call(dispute:, fetch: true, apply: true, now: Time.current)`：单条收敛
     （决策 + 受限执行），返回**封闭决策枚举** + 动作清单 + 前后状态，供日志/事件/（P7-7）Console 消费。
  2. **生命周期收敛**：**仅**在 `resolution == 'stale_local'` 且快照非降级时，`transition_to!` 到
     `ProviderPayload::STATE_BY_PROVIDER_STATUS[provider_status]`（单调前进，执行前再校验阶段序）；
     降级（`unsupported` / `unavailable` / `unknown`）/ `conflict` / `stale_provider` 一律**零写**。
  3. **账行补记**：`reconciliation == 'journal_missing'` 时，按 funds 时间戳逐条调用
     `FinancialLedger::PostDispute.call(dispute:, fact_type: <事件作用域类型>)` **幂等补记**（恰好一次）；
     不可补时如实返回 `skip_reason`（不重试轰炸、不猜时间戳）。
  4. **人工复核通道**：`conflict` / `orphan_entry` / `amount_mismatch` / 资金时间戳缺失 → 标 `attention_reason`
     + `state = manual_review`（`ATTENTION_REASONS` 扩展 3 个值：`provider_conflict` / `journal_gap` /
     `funds_evidence_missing`；**零 migration**，列无 CHECK 约束）。
  5. **批量收敛**：`Disputes::ScanRecoveryCandidates`（本地预筛，**零 provider I/O**，3 类 selection）+
     `Disputes::RecoverSweeperJob`（逐条收敛 + 事件发布 + 结构化日志 + 单条异常隔离 + 摘要）+
     调度登记 `dispute_recovery_sweep`（每日 01:30，`limit: 50`）。
- **成功指标**（可验证）：
  1. 漏事件场景（provider = `lost`，本地 = `opened`）→ 收敛到 `lost`；**第二次运行 `noop`**（幂等，零写）；
  2. 乱序场景（本地已 `lost`，provider 仍 `opened`）→ **零写**（绝不倒退），如实返回 `stale_provider` 观察；
  3. `journal_missing` → 补记**恰好一条**（`-amount`，方向/币种/`effective_at` 正确），重跑**不重复**；已有 `won` 的争议
     补记 `funds_reinstated` 时**不被终态吞掉**（沿用 P7-3 事件作用域 `fact_type` 提示）；
  4. 终局冲突（本地 `won` / provider `lost`）→ **零覆盖** + `attention_reason = provider_conflict` + `manual_review`；
  5. 降级路径（无只读契约 / provider 报错）→ **零写**，返回 `unsupported` / `unavailable`；
  6. **负向断言**：不创建 `Payment` / `Refund` / `StockReservation`，不改 `Order` / `CommerceTransaction` / `InventoryUnit`，
     不调用任何 provider **写**接口，不改写既有账行（append-only）；
  7. 回归：P7-1..5 + FIN-P4 specs 全绿；`generated:check` 无漂移、`doc-impact` synced。

## 2. 用户故事 / 场景

- 作为**运营/风控**：我希望系统自己跟住 provider 的终局（别等我收到每一封邮件），把真正需要人裁决的争议**挑出来**给我。
- 作为**财务**：我希望「已证实的资金事实」永远有账可查——缺账能被自动补上，且**不会重复入账**。
- 作为**工程**：我希望收敛动作**有界、幂等、可 dry-run、可重跑**，并且绝不做资金决策（不重扣、不退款）。

| # | 场景 | 类型 | 描述 |
|---|---|---|---|
| S1 | 漏终态事件 | 正常 | provider `lost` / 本地 `opened` → `stale_local` → 收敛 `lost`；重跑 `noop` |
| S2 | 乱序事件 | 边界 | 本地已 `lost` / provider 仍 `opened` → `stale_provider` → **零写**（不倒退） |
| S3 | 终局冲突 | 异常 | 本地 `won` / provider `lost` → **零覆盖** + `manual_review` + `provider_conflict` |
| S4 | 缺账行 | 异常 | `funds_withdrawn_at` 有值但无 `DISPUTE_FUNDS_WITHDRAWN` 行 → 补记 `-amount`（幂等） |
| S5 | 孤儿账行 | 异常 | 有账行但事实不可证（`orphan_entry`）→ **零账本写** + `manual_review` + `journal_gap` |
| S6 | 金额/币种不符 | 异常 | `amount_mismatch` → 不修改既有账行（append-only）→ `manual_review` + `journal_gap` |
| S7 | provider 降级 | 异常 | 无只读契约 / 网络报错 → `unsupported` / `unavailable` → **零写**（不猜、不标脏） |
| S8 | 无本地锚点 | 边界 | `unlinked_payment`（无 Payment）→ 零写 + `manual_review`（保留既有 attention 原因） |
| S9 | 资金时间戳缺失 | 异常 | provider 终态显示资金已移动但本地无 funds 时间戳 → **不猜时间戳** → `manual_review` + `funds_evidence_missing` |
| S10 | dry-run | 边界 | `apply: false` → 返回**计划**决策与动作，`applied: false`，数据库零变化 |
| S11 | 人工态再收敛 | 边界 | 本地 `manual_review` 且 provider 已到**终态** → 允许收敛到终态；provider 非终态 → 不动 |
| S12 | 批量扫描 | 正常 | 3 类 selection 混合 → 各自收敛；单条抛错 → 隔离并继续，摘要含 `failed` |
| S13 | 重复调度 | 边界 | 同一批连续两次运行 → 第二次全 `noop`（无新账行、无新标记） |

## 3. 功能需求（FR）

- **FR-P76-01**：`PallasTrade::Disputes::Recover.call(dispute:, fetch: true, apply: true, now: Time.current)`
  → `ServiceModule::Result` success(Hash)：
  `{ dispute_id:, state_before:, state_after:, dry_run:, decision:, actions: [], fact: { fact_type:, status:, resolution:, provider_status: },
  reconciliation: { classification:, reasons: }, attention_reason:, manual_review:, observed_at: }`。
  入参缺失 → failure。
- **FR-P76-02**：**决策封闭枚举** `DECISIONS = %w[noop lifecycle_repaired journal_repaired
  lifecycle_and_journal_repaired manual_review_flagged manual_review_pending unavailable unsupported]`；
  多动作时优先级 `manual_review_flagged > lifecycle_and_journal_repaired > journal_repaired > lifecycle_repaired > noop`
  （`actions[]` 完整列出实际/计划动作）。
- **FR-P76-03**：**生命周期收敛（唯一允许的状态写）**——条件**全部**满足才执行：
  ① `fetch: true` 且 provider 快照可得（`fact.source == 'provider_fetch'`，非降级）；② `fact.provider_status` 可映射
  （`ProviderPayload::STATE_BY_PROVIDER_STATUS`）且目标 ≠ 本地状态；③ **允许来源**：`resolution == 'stale_local'`
  **或**（本地 `manual_review` 且目标为 `TERMINAL_STATES`）；④ 阶段序校验 `STATE_ORDER[target] >= STATE_ORDER[local]`
  或本地 `manual_review`。执行 `transition_to!(target)`；`InvalidTransition` → 不抛错，记入 `actions` 的 `blocked` 并
  走人工复核（`invalid_transition` 语义与 P7-1 一致，绝不丢事实）。
- **FR-P76-04**：**账行补记（唯一允许的账本写）**——`reconciliation[:classification] == 'journal_missing'` 时，
  对 `expected_entries[]` 逐条映射 `fact_type`（`DISPUTE_FUNDS_WITHDRAWN` / `DISPUTE_FUNDS_REINSTATED`，
  **事件作用域提示**，沿用 FR-P73-05 语义）→ `FinancialLedger::PostDispute.call(dispute:, fact_type:)`；
  `skipped: true` → 记录 `skip_reason`（封闭枚举）并**不**重试；`skipped: false` → 记录 `entry_id`。
  **不触碰** `orphan_entry` / `amount_mismatch`（既有账行不可改写：append-only）。
- **FR-P76-05**：**人工复核通道**——以下情形标人工：① `resolution == 'conflict'` → `provider_conflict`；
  ② `reconciliation ∈ {orphan_entry, amount_mismatch}` → `journal_gap`；③ `journal_missing` 但补记被 skip
  （`entry_type_not_activated` / `commerce_transaction_missing` / `amount_or_currency_missing` / `effective_at_missing`
  / `fact_status_not_confirmed`）→ `journal_gap`；④ provider 状态为终局但本地对应 funds 时间戳缺失 → `funds_evidence_missing`；
  ⑤ 既有 `attention_reason == 'unlinked_payment'` 且无锚点 → 保持并 `manual_review`。
  **标人工 = `attention_reason`（仅当为 nil 时写入，不覆盖既有人工原因）+ `state = 'manual_review'`（若尚未）**。
- **FR-P76-06**：**铁律负向边界**（用例负向断言钉死）：不创建/更新 `Payment` / `Refund` / `PaymentSession` /
  `StockReservation` / `InventoryUnit`；不改 `Order` / `CommerceTransaction` / `Shipment`；不调用 provider 任何写方法
  （`create_dispute` / `submit_evidence` / `refund` / `capture` / `void`）；不删除/改写既有 `FinancialLedgerEntry`。
- **FR-P76-07**：**dry-run**——`apply: false` 时执行全部**只读**判定并返回计划（`dry_run: true`、`actions[].applied = false`），
  数据库零变化（快照断言）。
- **FR-P76-08**：**幂等**——同一 dispute 以相同事实重复 `apply: true`：第二次不再产生状态迁移、不再新增账行
  （`PostDispute` 幂等键）、不再重复标人工（已 `manual_review` 且有 attention → `manual_review_pending`）。
- **FR-P76-09**：**审计痕迹**——`apply: true` 且发生动作时，写入
  `private_metadata['recovery'] = { 'at' =>, 'decision' =>, 'actions' => [...], 'from' =>, 'to' => }`
  （仅保留**最近一次**，非数组累积，避免 jsonb 膨胀）；无动作时**不写**（保持行干净、不刷新 `updated_at` 语义）。
- **FR-P76-10**：`PallasTrade::Disputes::ScanRecoveryCandidates.call(now:, limit: 50, verify_after_hours: 24)`
  （**零 provider I/O**）→ `{ candidates: [], observed_at:, scanned_count: }`；每项
  `{ dispute_id:, selection:, state:, attention_reason:, age_hours: }`；`selection` 封闭枚举：
  `'attention'`（`attention_reason` 非空）/ `'journal_gap'`（**纯 SQL**：`funds_withdrawn_at` 有值但无对应
  `DISPUTE_FUNDS_WITHDRAWN` 账行，或 `funds_reinstated_at` 有值但无对应 `DISPUTE_FUNDS_REINSTATED` 账行）/
  `'stale_active'`（非终态且 `updated_at <= now - verify_after_hours`）。排序：`attention` → `journal_gap` →
  `stale_active`，组内按 `updated_at` 升序 + `id` 稳定；`limit` 截断并如实返回 `scanned_count`。
- **FR-P76-11**：`PallasTrade::Disputes::RecoverSweeperJob.perform(limit: 50, verify_after_hours: 24)`：
  调 `ScanRecoveryCandidates` → 逐条 `Recover.call(dispute:, fetch: selection != 'journal_gap', apply: true)`
  （`journal_gap` 走**纯本地**路径，零 provider I/O）→ 发布事件 `dispute.recovery_repaired` /
  `dispute.recovery_manual_review`（仅当 `decision != 'noop'` 且非降级）+ 结构化 JSON 日志；
  返回摘要 `{ scanned:, recovered:, manual_review:, noop:, unavailable:, journal_entries_posted:, failed:, limit:, observed_at: }`。
- **FR-P76-12**：**异常隔离**——单条 dispute 处理异常 → `rescue` + 日志 + `failed += 1`，继续其余；job 整体不 raise。
- **FR-P76-13**：**调度登记**——`backend/config/sidekiq_schedule.rb` 新增 `dispute_recovery_sweep`
  （`class: 'PallasTrade::Disputes::RecoverSweeperJob'`，`cron: '30 1 * * *'`，`queue: 'default'`，
  `args: [{ 'limit' => 50, 'verify_after_hours' => 24 }]`），由既有 `pallastrade_sidekiq_cron.rb` 注册（不新增机制）；
  默认每日一次、`limit` 有界（最坏 50 次 provider 只读调用）。
- **FR-P76-14**：**边界**——无 migration（`attention_reason` 列无 CHECK 约束，扩枚举零 DDL）、无 API/UI、无 provider 写、
  不改 P7-1..5 既有行为与既有断言。

## 4. 非功能需求（NFR）

- **幂等与可重跑**：收敛动作全部经幂等原语（`transition_to!` 同状态返回 false、`PostDispute` 幂等键、attention 只补不覆盖）。
- **有界**：`limit`（默认 50）限制单次批量规模与 provider 只读调用次数；`verify_after_hours` 限制 `stale_active` 频率。
- **零猜测**（FIN-INV-09）：快照降级 / provider 状态未知 / 金额不可证 / 时间戳缺失 → **一律不写**，以封闭枚举如实返回。
- **单调性**：状态只能向前（`STATE_ORDER`）；`manual_review` 仅允许自动收敛到 provider **终态**。
- **可观测**：每条事件的决策 + 动作 + 原因进结构化 JSON 日志与返回值；摘要可被指标消费。
- **性能**：候选 SQL 预筛（单查询 + 既有索引 `index_pallastrade_disputes_on_state_and_evidence_due_at`、
  `financial_ledger_entries.dispute_id`），逐条只读快照上限 = `limit`；避免 N+1（账行查询按 dispute 批量预取）。
- **兼容**：零 schema / API / SDK 变更；不触碰 P7-1..5 行为；`attention_reason` 既有 3 值与语义不变。

## 5. 验收标准（AC，与测试一一映射）

- **AC-P76-01 ← FR-P76-03**：provider `lost` / 本地 `opened`（快照非降级）→ `state_after == 'lost'`，
  `decision == 'lifecycle_repaired'`，`actions` 含 `{ type: 'lifecycle_repair', from: 'opened', to: 'lost' }`；
  `resolved_at` 被写入（`transition_to!` 既有语义）。
- **AC-P76-02 ← FR-P76-03/08**：同一 dispute 连续两次 `Recover` → 第二次 `decision == 'noop'`、`state_after` 不变、零新账行、零新 `updated_at` 变化（幂等）。
- **AC-P76-03 ← FR-P76-03**：本地已 `lost` / provider `opened` → **零写**（`state` 仍 `lost`）、
  `fact.resolution == 'stale_provider'`、`decision == 'noop'`、`actions == []`。
- **AC-P76-04 ← FR-P76-05**：本地 `won` / provider `lost` → `state` 不变（仍 `won`）、
  `attention_reason == 'provider_conflict'`、`state == 'manual_review'`（人工通道打开）、`decision == 'manual_review_flagged'`。
- **AC-P76-05 ← FR-P76-04**：`funds_withdrawn_at` 有值且无账行 → 补记 1 条 `DISPUTE_FUNDS_WITHDRAWN`、金额为
  **负数**且等于 dispute 金额、`effective_at == funds_withdrawn_at`；`decision == 'journal_repaired'`；
  **再次调用不新增账行**（唯一键幂等）。
- **AC-P76-06 ← FR-P76-04（P7-3 语义回归）**：已 `won` 且 `funds_reinstated_at` 有值而无账行 → 补记
  `DISPUTE_FUNDS_REINSTATED`（**不被终态 `DISPUTE_WON` 吞掉**，使用事件作用域 `fact_type` 提示）。
- **AC-P76-07 ← FR-P76-05**：`orphan_entry` / `amount_mismatch` → **零账本写**（账行数不变、内容不变）+
  `attention_reason == 'journal_gap'` + `manual_review`。
- **AC-P76-08 ← FR-P76-05**：`journal_missing` 但 `PostDispute` skip（如无 `commerce_transaction`）→
  **零账行** + `actions[]` 含 `skip_reason` + `attention_reason == 'journal_gap'`。
- **AC-P76-09 ← FR-P76-05**：provider 终态（如 `lost`）但本地 `funds_withdrawn_at` 为空且无账行 →
  **不写入任何时间戳/账行** + `attention_reason == 'funds_evidence_missing'` + `manual_review`。
- **AC-P76-10 ← FR-P76-03/05（降级）**：`fetch: true` 但无只读契约 → `decision == 'unsupported'`；provider 抛错 →
  `decision == 'unavailable'`；两者均**零写**、零 attention 标记（不把暂时故障钉成人工工单）。
- **AC-P76-11 ← FR-P76-06**：**负向断言**——运行前后 `Payment` / `Refund` / `Order` / `CommerceTransaction` /
  `Shipment` / `InventoryUnit` / `StockReservation` 行数与属性零变化；未调用 provider 写方法（对 payment_method 打桩并断言未被调用）。
- **AC-P76-12 ← FR-P76-07**：`apply: false` → 返回计划（`dry_run: true`、`actions[].applied == false`），
  数据库快照（state / attention / 账行数 / `updated_at`）零变化。
- **AC-P76-13 ← FR-P76-03（人工态）**：本地 `manual_review` + provider 终态（`lost`）→ 收敛到 `lost`；
  本地 `manual_review` + provider 非终态（`needs_response`）→ 零写。
- **AC-P76-14 ← FR-P76-09**：发生动作 → `private_metadata['recovery']` 含 `at/decision/actions/from/to`；
  无动作且无人工标记 → `private_metadata` 不被改写（保持原值）。
- **AC-P76-15 ← FR-P76-10**：3 类候选各造 1 条 → `selection` 分别为 `attention` / `journal_gap` / `stale_active`；
  排序为 attention → journal_gap → stale_active；`limit: 1` 只返回第一条且 `scanned_count == 1`；
  非终态且刚更新（`updated_at > now - verify_after_hours`）的争议**不**入选 `stale_active`。
- **AC-P76-16 ← FR-P76-10**：扫描**零 provider I/O**（对 `fetch_dispute_details` 打桩并断言从未被调用）。
- **AC-P76-17 ← FR-P76-11/12**：job 处理 3 条候选（1 收敛 / 1 人工 / 1 降级）→ 摘要计数正确、
  事件仅对非 `noop` 发布、结构化日志逐条输出；某条抛错 → `failed == 1` 且其余仍处理，job 不 raise。
- **AC-P76-18 ← FR-P76-13**：`PALLAS_CART_SCHEDULE` 含 `dispute_recovery_sweep`
  （`cron == '30 1 * * *'`、`class`、`args` = `limit 50` / `verify_after_hours 24`）。
- **AC-P76-19 ← FR-P76-14**：回归——P7-1..5 + FIN-P4 specs 全绿，无既有断言修改（除新增用例文件）。

## 6. 跨层搜索记录（6 层，gate 强制）

关键词：`dispute` / `chargeback` / `attention_reason` / `Recover` / `manual_review` / `reconcile`

| 层 | 路径 | 找到的文件 | 是否满足需求 |
|---|---|---|---|
| App | `backend/app/` | 无 dispute 命中；仅 Devise `:recoverable`（`user.rb` / `admin_user.rb`）与 CommerceTransaction 的 `recovery_attempts`（**不同域**） | ❌ 无既有收敛能力 |
| Core | `pallastrade_core/app/` | `services/pallastrade/disputes/{resolve_fact,handle_provider_event,provider_payload,evidence_snapshot,build_evidence_snapshot,scan_deadlines}.rb`、`jobs/pallastrade/disputes/deadline_sweeper_job.rb`、`models/pallastrade/dispute.rb`、`services/pallastrade/financial_ledger/post_dispute.rb`、`services/pallastrade/reconciliations/reconcile_dispute.rb`、`services/pallastrade/financial_facts/resolve_dispute.rb` | ⚠️ **原语齐、编排缺** → 本切片新增 `Recover` + `ScanRecoveryCandidates` + `RecoverSweeperJob` |
| API | `pallastrade_api/app/` | 无命中（无 dispute 端点） | ❌ 无 API 变更（展现归 P7-7） |
| Admin | `pallastrade_admin/app/` | 无命中 | ❌ 无 Admin UI（归 P7-7） |
| Storefront | `storefront/src/` | 无命中 | ❌ 不适用 |
| Platform | `platform/packages/` | 仅 `docs/dist/integrations/payments/adyen.md` 文本提及 chargeback | ❌ 无 SDK 变更 |

**结论**：dispute **收敛编排**在 6 层均不存在 → 本切片新增，落点 = `pallastrade_core`
（`Disputes::Recover` / `Disputes::ScanRecoveryCandidates` / `Disputes::RecoverSweeperJob`）
+ 宿主 `backend/config/sidekiq_schedule.rb`（调度登记，复用 P7-5 机制）。
**防重复判定**：不新建 provider 判定逻辑（复用 `ResolveFact`）、不新建对账逻辑（复用 `ReconcileDispute`）、
不新建入账逻辑（复用 `PostDispute`）、不新建状态机（复用 `transition_to!`）——本切片**只做编排**。

## 7. 技术影响

- **代码**：core gem 新增 3 文件（`Disputes::Recover` / `Disputes::ScanRecoveryCandidates` / `Disputes::RecoverSweeperJob`）
  + 修改 `PallasTrade::Dispute::ATTENTION_REASONS`（3 新增值）+ 宿主 `backend/config/sidekiq_schedule.rb` 1 条目 + specs。
- **数据**：**零 schema 变更**（`attention_reason` 为 `string` 无 CHECK；`private_metadata` 为既有 jsonb；
  账本/对账表不变）。**无 migration**。
- **调度**：复用既有 sidekiq-cron 初始化器；每日 01:30（错开 01:00 的 deadline sweep）；`limit: 50` 有界。
- **provder 调用**：仅**只读** `fetch_dispute_details`（`fetch: true` 时每条最多 1 次；`journal_gap` 路径零调用）。
- **兼容**：不触碰 P7-1..5 行为；不新增事件类型（发布 `dispute.recovery_*`，`Events` 为开放命名空间）。
- **回滚**：删除调度条目即停（安全：一切动作幂等）；代码 revert 无数据回退需求（账行 append-only、状态单调前进）。
- **风险**：
  ①**误把收敛当决策**（自动退款/重扣）→ AC-P76-11 负向断言 + 铁律代码注释钉死；
  ②**噪音**（每日重复标人工）→ attention 只补不覆盖 + `manual_review_pending` 幂等 + `verify_after_hours` 门槛；
  ③**provider 限流**→ `limit` 上限 + 每日一次 + 只读契约；
  ④**自动收敛覆盖人工判断**→ 仅允许 `stale_local`（provider 权威终局）与 `manual_review → 终态`，冲突一律交人工。

## 8. 测试计划（AC ↔ 测试文件）

| AC | 测试文件（新增） | 类型 |
|---|---|---|
| AC-P76-01..14 | `backend/spec/services/pallastrade/disputes/recover_spec.rb` | 服务（收敛决策/幂等/负向边界/dry-run/审计） |
| AC-P76-15/16 | `backend/spec/services/pallastrade/disputes/scan_recovery_candidates_spec.rb` | 服务（候选选择/排序/截断/零 I/O） |
| AC-P76-17/18 | `backend/spec/jobs/pallastrade/disputes/recover_sweeper_job_spec.rb` | job（摘要/事件/隔离/调度条目） |
| AC-P76-19 | 全量回归（`backend-rspec` verifier） | 回归 |

## 9. 文档同步清单（知识同步门）

- [x] **`ai/skills/pallastrade-payments/SKILL.md`**：新增「Dispute 收敛动作 Recovery（DSP-P7-6）」段（决策枚举 / 铁律 / attention 扩展 / 调度 / P7-3 服务加法式扩展 / 与 P7-7·P7-8 分界）
- [x] **`ai/skills/pallastrade-events-webhooks/SKILL.md`**：事件目录新增「Dispute 收敛事件」（`dispute.recovery_repaired` / `dispute.recovery_manual_review` + 发布边界）
- [x] **`ai/skills/pallastrade-data-model/SKILL.md`**：`attention_reason` 语义更新（6 值 + 两个 writer + 只补不覆盖）
- [x] **`harness/scenarios/scenarios.json`**：新增 **GS-097**（收敛只修事实、绝不动钱）；`eval-ai --scenarios` 98/98、freshness 0 error
- [x] **`docs/prd/README.md`**：已登记本 PRD 索引行
- [x] **`harness/requirements/REQ-20260912-dsp-p7-6-dispute-recovery.md`**：已生成（含 6 层搜索 + Skill 咨询证据表）
- [x] **API 文档**：N/A（无接口变更）→ 以 `generated:check` 无漂移为证
- [x] `ai/skills/pallastrade-prd/SKILL.md`：⏭ 评估后不更新（PRD 流程与门禁未变化）
- [x] `AGENTS.md` / `.github/copilot-instructions.md`：⏭ 评估后不更新（未新增全局规则/门禁/反模式；`ATTENTION_REASONS` 扩展属域内语义，已登记 data-model Skill）
- [x] `ai/skills/pallastrade-deployment/SKILL.md`：⏭ 评估后不更新（调度沿用既有 sidekiq-cron 机制：`backend/config/sidekiq_schedule.rb` + `pallastrade_sidekiq_cron.rb`，P7-5 已有同类登记）
- [x] `ai/skills/pallastrade-testing/SKILL.md`：⏭ 评估后不更新（沿用既有服务/job spec 约定，无新测试机制）

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-12 | 0.1 | 初稿（承接 DSP-P7-5；源计划 §47–§53） | AI |
| 2026-09-12 | 0.2 | 用户确认（approved）：全量实施；sweeper 默认启用（每日 01:30，limit 50）；人工复核置 `manual_review` | AI |
| 2026-09-12 | 0.3 | 实施：`Disputes::Recover` / `ScanRecoveryCandidates` / `RecoverSweeperJob` + `ATTENTION_REASONS` 扩展 + 调度登记；P7-3 三个服务加法式新增 `dispute_fact:`（复用同一份权威快照，避免重复 provider 只读调用且不依赖本地元数据）；新增 3 个 spec（共 27 examples） | AI |
| 2026-09-12 | 0.4 | 实施中发现并修正两处设计缺陷：①`ReconcileDispute` 仅用本地裁决 → 缺元数据时把可证事实降为 AMBIGUOUS 导致**漏补账**（改为传入权威 `dispute_fact`）；②生命周期修复后再判 `manual_review?` 会把「本就在人工态」的行当成新冲突重复标记（改为用**观测态**判定，消除自激振荡） | AI |
| 2026-09-12 | 0.5 | 验证完成 → done：注册 verifier `backend-rspec` 全量绿（EVD-20260912172318-a64e1736b5）；定向 27 examples + 域内 273 examples 0 failures；rubocop 本次触碰 11 文件 0 违规；`generated:check` 无漂移、`doc-impact` 判定知识已同步；GS-097 → 98/98（freshness 0 error）；恢复计划 `REC-55cf62d7907898`；Gate `GATE-2026-09-12T16-20-07` 关闭（review EVD-20260912172349-2ef45012f4 / knowledge EVD-20260912172351-32c7bd8d38 / approval EVD-20260912162055-3466eef15c）；已提交推送 `a455bb13` | AI |
