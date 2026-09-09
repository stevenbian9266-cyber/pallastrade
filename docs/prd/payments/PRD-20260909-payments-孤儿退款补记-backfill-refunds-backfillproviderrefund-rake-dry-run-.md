# PRD-20260909-payments-孤儿退款补记-backfill-refunds-backfillproviderrefund-rake-dry-run-

| 元数据 | 值 |
|---|---|
| 状态 | draft |
| 创建日期 | 2026-09-09 |
| 来源 | 孤儿退款补记 backfill：Refunds::BackfillProviderRefund + rake dry-run/apply（补记即终态，绝不二次 PSP） |
| 分类 | payments（自动判定） |

> ⚠️ AI：请按 docs/prd/_TEMPLATE.md 完整扩充本文档（背景/FR/AC/跨层搜索/测试计划/文档同步清单），再进入用户确认。

---

# PRD-20260909-payments-孤儿退款补记-backfill-refunds-backfillproviderrefund-rake-dry-run-

| 元数据 | 值 |
|---|---|
| 状态 | draft |
| 创建日期 | 2026-09-09 |
| 来源 | 孤儿退款补记 backfill：Refunds::BackfillProviderRefund + rake dry-run/apply（补记即终态，绝不二次 PSP） |
| 分类 | payments（自动判定） |
| 关联 Skill | pallastrade-payments / pallastrade-security（危险资金操作）/ pallastrade-prd |
| 关联 REQ | REQ-20260909-rev-p6-8m-orphan-refund-backfill.md（实施时建） |
| 关联 PRD | REV-P6-8d/8h（孤儿只读配对/金额边界「孤儿自动补记 → 人工 + backfill」落地）；REV-P6-1/2（durable ApplySuccess 幂等） |
| 需求类型 | 优化迭代（RISK-REV-01 收口：孤儿本地补记，feature gate） |

> 源：`豆包…/P6` RISK-REV-01（Orphan PSP Refund）+ REV-P6-2 ApplySuccess 幂等（§19-20）。**8d/8h 边界
> 「孤儿自动补记/自动退款（人工 + backfill）」落地**：把 provider 已退、本地缺失的孤儿退款**补记为
> durable Refund 行并直接落终态**（复用 `apply_success!` 幂等 + `refund.succeeded → PostRefund` Journal
> 自动闭环），使本地账/对账/审计闭合。**绝不调用 PSP / 绝不二次退款**（补记 = 记录 provider 已发生资金，
> 不是发起退款）；人工 rake 门（dry-run 默认）。

## 1. 背景与目标
8d/8h 后孤儿（provider-only 退款）可**只读配对 + 金额可见**，但本地始终无 durable Refund 行 → Journal/
对账/报表缺半边（RISK-REV-01 资金完整性缺口）。目标：
1. **补记服务** `Refunds::BackfillProviderRefund`：孤儿（payment + provider 金额）→ 本地 Refund 行 +
   `apply_success!(authorization: provider_id)` 直接 succeeded + Journal（复用幂等闭环）；
2. **人工 rake 门** `pallastrade:refunds:backfill_orphans`：默认 dry-run（TSV 计划），`--apply` 才写；
3. **零 PSP mutation**（全程只读 provider 金额能力 + 本地写；绝不发起退款）；幂等（同 payment+transaction_id
   不重复）；孤儿 target_order/split 不可证明不猜（update_order 仅可证明投影）。
成功指标：dry-run 列出计划；apply 后孤儿行 succeeded + REFUND_SUCCEEDED journal；重跑幂等 noop；对账
matched；零 PSP 调用断言；全量绿。

## 2. 用户故事 / 场景
- 作为财务，我希望跑 backfill dry-run 看到「哪些 payment 有孤儿退款、金额、将如何补记」，以便核对后放行。
- 作为财务，我希望 `--apply` 把孤儿补记为 succeeded Refund + Journal，以便本地账/对账闭合（不再缺半边）。
- 边界：amount 无法证明（provider 金额 nil）→ skip（ORPHAN_AMOUNT_UNAVAILABLE）；重复跑 → noop；组合孤儿
  （payment order nil、target 不可证明）→ 仅 fact/journal 落（不猜 target_order）。

## 3. 功能需求（FR）
- FR-R68M-101（补记服务）：`Refunds::BackfillProviderRefund.call(payment:, provider_id:, amount:,
  currency: nil, actor: 'rake')` → Result：
  - 守卫：payment 缺失 / amount 空（不可证明）→ failure(skip: :orphan_amount_unavailable)；
  - 幂等：`Refund.where(payment_id: payment.id, transaction_id: provider_id).exists?` → success(noop:
    :already_backfilled)；
  - 建行：`payment.refunds.create!(amount:, transaction_id: provider_id, state: 'requested', reason:
    RefundReason.orphan_backfill_reason)` + metadata `{ backfilled_orphan: true }`；
  - 终态：`refund.apply_success!(authorization: provider_id)`（succeeded + update_order 可证明投影 +
    after_commit `refund.succeeded` → FinancialLedger PostRefund = REFUND_SUCCEEDED Journal 自动闭合；
    **绝不调 PSP / ExecuteJob**）；
  - 审计：`Audit.record(action: 'refund_orphan_backfill', actor:, resource: refund, after: {payment_id,
    provider_id, amount, currency})`；
  - 单条异常 rescue 不中断批量（rake 层隔离）。
- FR-R68M-102（reason）：`RefundReason::ORPHAN_BACKFILL_REASON = 'Provider Refund Backfill'` +
  `self.orphan_backfill_reason` find_or_create（mutable: false，镜像 order_canceled_reason）。
- FR-R68M-103（rake）：`pallastrade:refunds:backfill_orphans[store_id]`（core tasks `refunds_backfill.rake`）：
  - 默认 **dry-run**：逐店 completed PSP payments（OrphanPairing 候选面）→ orphans → TSV 计划
    （payment/refund ref/amount/currency/将补记状态）+ summary counts；
  - `--apply`：逐 orphan 调 BackfillProviderRefund（幂等/noop/隔离），TSV 结果 + summary
    （backfilled/already_backfilled/skipped/errors）；
  - 只读阶段复用 8h `provider_refund_amount`（amount nil → skip + ORPHAN_AMOUNT_UNAVAILABLE 记录）；
  - 禁止自动调度（人工门）。
- 边界（记录不实施）：孤儿 target_order/payment_split 不可证明 → 不猜（update_order 仅可证明投影；组合孤儿
  仅 fact/journal 落）；自动调度；孤儿对外 API（8l 已提供只读查看）。

## 4. 非功能需求（NFR）
零 PSP mutation（绝不二次退款——REV-INV-04 精神）；幂等可重放（同键 noop）；dry-run 默认 + `--apply` 显式；
Audit 敏感操作记录；rake 逐条 rescue 隔离 + summary；金额以 provider 权威（8h）为准；无 migration。

## 5. 验收标准（AC）
| AC | 条件 | FR |
|---|---|---|
| AC-R68M-01 | BackfillProviderRefund(单订单孤儿) → Refund 行 + succeeded + transaction_id=provider_id + metadata{backfilled_orphan} + REFUND_SUCCEEDED journal；未调 PSP/ExecuteJob | 101 |
| AC-R68M-02 | 重复调用同 payment+provider_id → noop 不重复建行 | 101 |
| AC-R68M-03 | amount 不可证明（nil）→ skip(orphan_amount_unavailable) 不建行 | 101 |
| AC-R68M-04 | RefundReason.orphan_backfill_reason 存在（mutable false）；Audit.record(action=refund_orphan_backfill) | 102/101 |
| AC-R68M-05 | rake dry-run（默认）只读列计划；--apply 落行；TSV+summary；组合孤儿（order nil 无 target）仅 fact/journal 落不猜 | 103 |
| AC-R68M-06 | 回归：8d/8h 配对 spec、8a-8l 相关组绿；全量 backend-rspec ×2 + quick check + doc-impact | — |

## 6. 跨层搜索记录（6 层）
| 层 | 路径 | 找到 | 满足 |
|---|---|---|---|
| App | backend/app | 无 | — |
| Core | core/app | OrphanPairing/OrphanPairingResult（8d/8h 只读+金额）；Refund apply_success!/状态机/succeeded→PostRefund；RefundReason find_or_create 惯例 | 数据面有 |
| API | api/app | 无写入口（孤儿只读 8l 端点）→ backfill 走 rake 不经 API | — |
| Admin | admin/app | 无（孤儿 Ops 只读） | — |
| Storefront | storefront/src | 无 | — |
| Platform | platform/packages | 无 | — |

**结论**：core 数据面齐备；缺口 = 补记服务 + reason + rake（本包）；不涉 API/UI/SDK/migration。

## 7. 技术影响
core：`services/refunds/backfill_provider_refund.rb`（新）、`models/refund_reason.rb`（+常量/class 方法）、
`lib/tasks/refunds_backfill.rake`（新）。specs：service spec + rake 冒烟。无 migration/API/UI。

## 8. 测试计划
新增：`spec/services/pallastrade/refunds/backfill_provider_refund_spec.rb`（succeeded+journal+幂等+amount nil
skip+零 PSP/Execute 断言+Audit）；rake 冒烟（dry-run 只读 / --apply）。回归：orphan_pairing（8d/8h）、
refund lifecycle（REV-P6-1/2）、8a-8l 相关。AC-R68M-01~06 映射。

## 9. 文档同步清单（知识同步门）
- [ ] payments skill（8m 节）；scenarios GS-080。
- [ ] refunds rake runbook（8d runbook 补 backfill 用法）。
- [ ] PRD 状态 + docs/prd/README。
- [ ] 边界记录：target 不可证明不猜、自动调度不做。

## 10. 变更记录
| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-09 | 0.1 | 初稿（RISK-REV-01 收口：8d/8h 边界落地；复用 ApplySuccess 幂等；零 PSP） | AI |
| 2026-09-09 | 1.0 | done：实施完成（需求 commit 1d7d252）——BackfillProviderRefund（补记即终态零 PSP/幂等）+ RefundReason.orphan_backfill_reason + rake dry-run/apply（id 子查询 or）；spec 5 绿+回归 41 绿+全量 ×2 绿+quick 干净；GS-080；payments skill 8m 节 + runbook 补记小节 | AI |
