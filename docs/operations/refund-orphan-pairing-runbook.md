# Refund Orphan Pairing Runbook（REV-P6-8d）

> 目的：发现「provider 侧存在退款、本地却无对应 Refund 行」的孤儿（如 Stripe 后台/其他系统直接退款），
> 以及「本地 succeeded 引用在 provider 缺失」的本地缺失——资金流出不可见问题的只读排查工具。
> 只读/零副作用：不做任何写、不自动退款（同 FIN-P4 reconcile 不变式）。

## 语义
`Refunds::OrphanPairing.call(payment:)` 返回 `OrphanPairingResult`：

| status | 含义 | reasons |
|---|---|---|
| matched | provider 全部退款引用都有本地行，且本地 succeeded 引用都在 provider | — |
| needs_attention | provider-only 退款（孤儿）或本地有引用但 provider 缺失 | `ORPHAN_REFUND` / `LOCAL_REFUND_NOT_ON_PROVIDER` |
| not_applicable | StoreCredit / Check（无 provider refund 概念） | `NO_PROVIDER_REFUND_CONCEPT` |
| unsupported | payment method 无 `fetch_financial_details`（legacy 契约） | `PROVIDER_CONTRACT_UNSUPPORTED` |
| unavailable | 无 provider session 锚点 / provider 异常 | `UNLINKED_LEGACY_PAYMENT` / `PROVIDER_UNAVAILABLE` |

数据面：provider `provider_refund_references`（Stripe charge refunds `re_`）；本地 `refund.transaction_id`
（= apply_success 存的 provider refund id）。

## 使用

```bash
# 单店（省略则默认店）
docker exec pallastrade-web-1 bash -c \
  "cd /rails && bundle exec rails runner 'require \"pallastrade/tasks\"' -- \
   $(echo) rake pallastrade:refunds:orphans[<store_id>]"
# 或标准 rake
cd /rails && bundle exec rake "pallastrade:refunds:orphans[<store_id>]"
```

输出：`store=... payments=...`；每行 = payment / currency / status / reasons / orphan ids(`|`) / local-missing
refs(`|`) / updated_at；末尾 `summary status=count ...`。

## 解读与处置
- `needs_attention` + `ORPHAN_REFUND`：provider 退过款但本地无行。核对 Stripe Dashboard 该 charge 的 refunds；
  若确系业务外退款，评估补记（人工、遵循 backfill 可证明原则，不猜）；不要自动建 refund。
- `needs_attention` + `LOCAL_REFUND_NOT_ON_PROVIDER`：本地 succeeded 引用在 provider 缺失——可能是历史数据/
  provider 数据删除；用 `pallastrade:reconciliations:repair[txn]` 与对账确认。
- `unavailable`：多为无 session 的 legacy 支付或瞬时 provider 异常；重跑即可。
- 处置后重跑确认归零。

## 边界
- 不做自动修复/自动退款；孤儿处理为人工 + 受控 backfill 原则。
- 单笔 provider refund 金额不在本 VO（只给引用）；如需金额，另行 `retrieve_refund`（Stripe 只读）扩展。
- Admin/API 展示配对结果 → 后续独立包（如需 UI）。
