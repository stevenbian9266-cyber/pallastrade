# Financial Reconciliation — Operations Runbook（FIN-P4-8）

> P4（Financial Ledger & PSP Reconciliation）收官运维手册。适用范围：
> Journal repair（缺记补记）、reconciliation retry / visibility、受控 backfill（三类语义）、
> legacy 无法证明数据的处置。命令在宿主 Rails 环境执行（本仓库 docker：
> `docker exec -it pallastrade-web-1 sh -c "cd /rails && ..."`）。

## 1. 关键概念速查

- Journal（`FinancialLedgerEntry`）是不可变账本（FIN-P4-2）：posting 幂等（idempotency key），
  缺记由 `FinancialLedger::RepairTransaction` **幂等补记**（FIN-P4-8）。
- Repair **绝不**：重新 Payment / 重新 Refund / 修改任何 state machine / 自动 charge（§44/§49/INV-08/09）。
  唯一写 = Journal entry（经既有 PostPayment/PostRefund/PostAllocation 幂等原语）。
- Reconciliation（P4-6/7）只读、幂等：`ReconcilePayment`/`ReconcileRefund`（源级）、
  `ReconcileTransaction`（交易级，输出 `TransactionResult` + `TransactionFinancialSummary`）。
- 自动 vs 人工边界（§44/§46）：
  - **自动（安全）**：journal missing（`JOURNAL_POSTING_MISSING`）→ Repair（幂等、只写 Journal）。
  - **人工（绝不自动动资金）**：mismatch / needs_attention / provider 冲突 / settlement 冲突
    —— `ReconcileSweeperJob` 只计数 + warn，人工用下方命令介入。
- Backfill 三类（§50/AC-4025）：PROVABLE（有 payment/provider ref/capture evidence/currency →
  补 journal）／PARTIALLY_PROVABLE（缺 provider settlement → 只补本地、reconcile PENDING/UNSUPPORTED
  如实）／UNPROVABLE（无法证明 → **不写不猜**，保留 legacy）。

## 2. 可见性（reconciliation needs-attention）

```bash
bundle exec rake pallastrade:reconciliations:list_needs_attention
```

输出 `count=` 及 TSV（prefixed_id / state / status / reasons / currency / amount / updated_at）——
对每个 completed/payment_confirmed/finalizing 交易实时跑 `ReconcileTransaction`。

## 3. 手动重跑 reconciliation（manual retry，只读）

```bash
bundle exec rake "pallastrade:reconciliations:reconcile[txn_xxx]"
```

输出 `status=… reasons=…` 与 summary。只读、幂等，可重复执行。

## 4. Journal repair（幂等补记）

```bash
bundle exec rake "pallastrade:reconciliations:repair[txn_xxx]"
```

输出 `repaired=N already_present=N skipped=[…]`。捕获的 payment / 成功的 refund / settled
combination splits 缺 journal entry 时补记；不可证明源 skipped（不猜）。重复执行安全。

代码语义：`PallasTrade::FinancialLedger::RepairTransaction.call(transaction:)`
（service）／`PallasTrade::FinancialLedger::RepairTransactionJob`（job，供 sweeper/manual 驱动）。

## 5. 自动 sweeper（sidekiq-cron）

`Reconciliations::ReconcileSweeperJob` 周期扫描（默认 completed/payment_confirmed/finalizing）：

- journal-missing → 自动 enqueue `RepairTransactionJob`（幂等安全）；
- mismatch / needs_attention / pending → **不自动**，仅结构化 metrics 日志
  （`event=reconciliations.sweeper` + status_counts + needs_human）+ warn 告警。

人工收到告警后用 §3/§4 命令或直接检查（§7）。

## 6. 受控 backfill（三类语义）

```bash
bundle exec rake "pallastrade:reconciliations:backfill[store_id?]"   # 空 = 全店
```

对每个 completed 交易跑 `RepairTransaction` 并按结果分类统计：
`journal_entries_repaired`（PROVABLE 实际补记数）／`txn_provable`／`txn_partially_provable`／
`txn_unprovable`。UNPROVABLE 不写 journal、不猜（AC-4025：历史无法证明不强制 backfill）。

## 7. 检查单个交易的财务面

```ruby
tx = PallasTrade::CommerceTransaction.find_by_prefix_id!('txn_xxx')
result = PallasTrade::Reconciliations::ReconcileTransaction.call(transaction: tx)
result.value.status          # MATCHED/MISMATCH/NEEDS_ATTENTION/PENDING/UNSUPPORTED/NOT_APPLICABLE
result.value.reasons         # 原因码（ALLOCATION_MISMATCH / JOURNAL_POSTING_MISSING / …）
result.value.summary.to_h    # §25 金额摘要（commercial/cash/refund/allocation/provider fee/net…）
```

## 8. 对账差异队列（D13 切片1，2026-09-16）

> PRD-20260916-payments-d13-reconciliation-cases（业务方案 §70.1）：只读对账结论 → **持久化案例队列**。
> 后台工作台：**Orders → 对账队列**（`/admin/reconciliation_cases`，需 `can?(:manage, PallasTrade::ReconciliationCase)`）。

- **自动**（`Reconciliations::SyncCases`，sweeper 每轮调用）：差异态 → upsert 案例（`dedupe_key = txn:<id>:<signature>`）；
  差异消失 → 自动销案（`fixed` + `resolution_source: auto`）；签名被取代 → 旧案自动销案。
- **人工**（页面动作，全部写 `AuditLog`）：指派 / 备注（留痕） / 标记已解释 / 标记已修正 / 忽略（必填原因） / 重开。
- **铁律**：案例只是工作队列 —— 页面动作与自动同步都**不动钱**（不改 Payment/Refund/Transaction/Journal/订单/库存，
  不调 provider）。队列不替代 runbook 命令：repair/backfill 仍只能走 §4/§6 的 rake。
- 命令行查看队列（容器内）：

```ruby
scope = PallasTrade::ReconciliationCase.open_queue.recent_first
scope.count                                            # 队列长度
scope.limit(20).map { |c| [c.dedupe_key, c.difference_type, c.severity] }
```

## 9. 结算台账（D13 切片2，2026-09-16）

> PRD-20260916-payments-d13b-payout-ledger（业务方案 §70.2）：provider 结算报表 → **可核对台账** + 逐行匹配。
> 后台：**Orders → 结算台账**（`/admin/payouts`，需 `can?(:manage, PallasTrade::Payout)`）。

- **导入**（`POST /admin/payouts/import`，页面可粘贴或上传 CSV）：必需列 `payout_reference, kind, provider_reference, gross`；
  可选 `fee`（默认 0）/`net`（默认 gross − fee）/`currency`/`arrived_on`（到账日）/`period_start`/`period_end`；
  导入后**自动**匹配（`Match`）并把差异行送入 §8 队列（`SyncCases`）。
- **幂等**：批次键 `(store, provider, reference)`、行键 `(payout, provider_reference, kind)` —— 同一文件重复导入只计入
  `lines_skipped`；行级错误在页面回显（最多 10 条），缺列/空文件/超 5 MB → 拒绝且不落库。
- **状态**：`difference`（任一行 unmatched/amount_mismatch）→ `settled`（无差异且有到账日）→ `in_transit`；金额容差 1 分。
- **匹配锚点**：`charge` → `Payment#response_code` → `PaymentSession#external_id`；`refund` → `Refund#transaction_id`；
  `fee`/`adjustment` = provider 侧项目直接 matched。
- **重新匹配**（`POST /admin/payouts/:id/match`）：补正本地数据后重跑；行恢复 matched → 对应开放案例**自动销案**。
- **铁律**：导入/匹配/入队**不动钱**（不改 Payment/Refund/Journal/订单/库存，不调 provider）；台账是事实记录，
  修数据仍只能走 §4/§6。
- 命令行查看台账（容器内）：

```ruby
PallasTrade::Payout.with_differences.order(settled_at: :desc).limit(10)
  .map { |p| [p.reference, p.provider, p.gross_total, p.difference_lines.count] }
PallasTrade::Reconciliations::Payouts::Match.call(payout: PallasTrade::Payout.last)
```

## 10. 退款审批（阈值 + 双人复核，D14 切片1，2026-09-16）

> PRD-20260916-payments-d14-refund-approval（业务方案 §71.1）：人工退款加**策略门** ——
> `≤` 阈值自动执行；`>` 阈值**落库待批**，必须**第二人**批准才入队执行。
> 后台：**Orders → 退款审批**（`/admin/refund_approvals`，需 `can?(:manage, PallasTrade::RefundApproval)`）。

- **策略**（店铺级，页内策略卡保存；`PATCH /admin/refund_approvals/policy`）：`enabled` / `auto_approve_limit` / `currency`；
  归一化保守 —— `enabled` 但阈值缺失/非法 → **全部需审批**（宁可多审，绝不静默放行）；策略未启用 → 行为与历史一致。
- **待批语义**：退款已 durable 落库为 `requested` 但**不入队**（provider 尚未被调用）；
  拒绝 → `cancel_request!`（`requested → canceled`）**释放可退额度**，可重新提交。
- **双人复核（SoD）**：批准/拒绝人必须 ≠ 发起人；发起人本人行在页面不渲染动作，服务层同时强制（API/脚本同样被拦）。
  批准 = 唯一入队时机（`Refunds::ExecuteJob`），重复批准**不重复入队**。
- **幂等**：提交可带 `request_key`（Admin API 亦支持）；同键重复提交返回**同一笔**退款，不会出第二笔。
- **铁律**：策略门/批准/拒绝**不动钱** —— 不调 provider、不写资金日志、不改 Payment/订单金额；资金执行仍只由 `ExecuteJob` 承担。
- 命令行复核（容器内）：

```ruby
PallasTrade::RefundApproval.pending.order(created_at: :desc).limit(10)
  .map { |a| [a.id, a.refund_id, a.amount, a.currency, a.requester_id, a.policy_limit] }
PallasTrade::Refunds::Policy.for(PallasTrade::Store.default).snapshot   # 当前生效策略（只读）
```

## 11. 边界提醒

- Repair/Backfill 唯一写 = Journal；绝不新 Payment/Refund、绝不倒退 transaction state。
- UNPROVABLE 历史数据不猜测、不强制 backfill（§50/AC-4025）。
- mismatch / needs_attention 属人工裁决域（§46 严重冲突可能需 manual_review，绝不自动倒退到
  payment_pending）。
- 超阈值退款**不得**用「直接调用 `Refunds::Request` / 手工入队」绕开审批（绕过 §10 的策略门 = 违规）；
  紧急出款一律走「提交 → 第二人批准」。
- 相关 skill：`ai/skills/pallastrade-payments/SKILL.md`（P4 各包语义 + 结算台账 + 退款审批）／`pallastrade-deployment`
  （sidekiq-cron 调度）／`pallastrade-admin`（对账队列 + 结算台账 + 退款审批工作台）。
