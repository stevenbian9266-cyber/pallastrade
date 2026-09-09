# Refund Orphan Pairing Runbook（REV-P6-8d）

> 目的：发现「provider 侧存在退款、本地却无对应 Refund 行」的孤儿（如 Stripe 后台/其他系统直接退款），
> 以及「本地 succeeded 引用在 provider 缺失」的本地缺失——资金流出不可见问题的只读排查工具。
> 只读/零副作用：不做任何写、不自动退款（同 FIN-P4 reconcile 不变式）。

## 语义
`Refunds::OrphanPairing.call(payment:)` 返回 `OrphanPairingResult`：

| status | 含义 | reasons |
|---|---|---|
| matched | provider 全部退款引用都有本地行，且本地 succeeded 引用都在 provider | — |
| needs_attention | provider-only 退款（孤儿）或本地有引用但 provider 缺失 | `ORPHAN_REFUND` / `LOCAL_REFUND_NOT_ON_PROVIDER` / `ORPHAN_AMOUNT_UNAVAILABLE`（8h：孤儿金额不可得时追加） |
| not_applicable | StoreCredit / Check（无 provider refund 概念） | `NO_PROVIDER_REFUND_CONCEPT` |
| unsupported | payment method 无 `fetch_financial_details`（legacy 契约） | `PROVIDER_CONTRACT_UNSUPPORTED` |
| unavailable | 无 provider session 锚点 / provider 异常 | `UNLINKED_LEGACY_PAYMENT` / `PROVIDER_UNAVAILABLE` |

数据面：provider `provider_refund_references`（Stripe charge refunds `re_`）；本地 `refund.transaction_id`
（= apply_success 存的 provider refund id）。

## 孤儿金额（REV-P6-8h，只读）
孤儿（provider-only）退款条目含 `amount/currency`（major units）——Stripe 经只读 `retrieve_refund`
（`PaymentMethod#provider_refund_amount` 能力门：owner 判定同 CaptureEvidencePolicy；Bogus 本地派生引用、
无真实孤儿语义 → 继承 base → amount nil）。能力缺失或单条 provider 异常 → 该孤儿 amount nil（不猜、不中断
其他孤儿）+ reason `ORPHAN_AMOUNT_UNAVAILABLE`。金额只读展示、不落库。

## 使用

```bash
# 单店（省略则默认店）
docker exec pallastrade-web-1 bash -c \
  "cd /rails && bundle exec rails runner 'require \"pallastrade/tasks\"' -- \
   $(echo) rake pallastrade:refunds:orphans[<store_id>]"
# 或标准 rake
cd /rails && bundle exec rake "pallastrade:refunds:orphans[<store_id>]"
```

输出：`store=... payments=...`；每行 = payment / currency / status / reasons / orphan ids(`|`) / **orphan
amounts(`|`) / orphan currencies(`|`)（8h）** / local-missing refs(`|`) / updated_at；末尾
`summary status=count ...`。

## 解读与处置
- `needs_attention` + `ORPHAN_REFUND`：provider 退过款但本地无行。核对 Stripe Dashboard 该 charge 的 refunds
  （8h 起行内含孤儿金额，可直接评估资金缺口大小）；若确系业务外退款，评估补记（人工、遵循 backfill
  可证明原则，不猜）；不要自动建 refund。
- `needs_attention` + `LOCAL_REFUND_NOT_ON_PROVIDER`：本地 succeeded 引用在 provider 缺失——可能是历史数据/
  provider 数据删除；用 `pallastrade:reconciliations:repair[txn]` 与对账确认。
- `unavailable`：多为无 session 的 legacy 支付或瞬时 provider 异常；重跑即可。
- 处置后重跑确认归零。

## Admin 可视化（REV-P6-8h）
Rails Admin → Orders → **Payments**（只读）：completed PSP payments（含组合 payment）列表；打开任一支付即
在线运行 OrphanPairing —— matched / orphans（含只读金额）/ 本地缺失 provider 的退款。页面降级（provider
异常）显示 degraded 不 500。同 rake，全程零写。

## 边界
- 不做自动修复/自动退款；孤儿处理为人工 + 受控 backfill 原则。
- 金额为只读展示不落库；非 Stripe provider 无金额能力时显示「—」。
- Admin API v3 只读端点/SDK 暴露 → 后续独立包（如需外部系统消费）。

## 孤儿补记（REV-P6-8m；人工门）

> 孤儿 = provider 已退款、本地无 durable 行。补记把该**已发生资金**记录为本地 Refund（succeeded +
> Journal），**绝不二次 PSP**。全程人工：

```bash
# 1) dry-run（只读，列计划）
rake pallastrade:refunds:backfill_orphans[<store_id>]
# 2) 核对 TSV 计划（payment / provider_ref / amount / planned）后执行
APPLY=1 rake pallastrade:refunds:backfill_orphans[<store_id>]
```

- 输出：TSV + summary（backfilled / already_backfilled / skipped / planned / error）；skip 原因
  `orphan_amount_unavailable`（provider 金额无法证明——不猜）。
- 语义：`Refunds::BackfillProviderRefund`——幂等（同 payment+transaction_id noop）；补记行 metadata
  `backfilled_orphan`；`AuditLog(action=refund_orphan_backfill)` 全量留痕（误补可据此定位）。
- 组合孤儿（payment `order_id=nil`、target 不可证明）→ 仅 fact/Journal 落（不猜 target_order）。
- 禁止自动调度；`--apply` 前必须 dry-run 核对。
