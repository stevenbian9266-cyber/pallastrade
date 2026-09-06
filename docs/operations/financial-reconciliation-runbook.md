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

## 8. 边界提醒

- Repair/Backfill 唯一写 = Journal；绝不新 Payment/Refund、绝不倒退 transaction state。
- UNPROVABLE 历史数据不猜测、不强制 backfill（§50/AC-4025）。
- mismatch / needs_attention 属人工裁决域（§46 严重冲突可能需 manual_review，绝不自动倒退到
  payment_pending）。
- 相关 skill：`ai/skills/pallastrade-payments/SKILL.md`（P4 各包语义）／`pallastrade-deployment`
  （sidekiq-cron 调度）。
