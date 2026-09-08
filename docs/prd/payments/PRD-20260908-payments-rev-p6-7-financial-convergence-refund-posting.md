# PRD-20260908-payments-rev-p6-7-financial-convergence-refund-posting

| 元数据 | 值 |
|---|---|
| 状态 | approved |
| 创建日期 | 2026-09-08 |
| 来源 | 需求：REV-P6-7 Financial Convergence（refund posting 缺失闭环 + ReconcileRefund 本地状态分类 + provider mismatch 语义） |
| 分类 | payments（语义归属；prd new 误判 catalog 已弃用该骨架） |
| 关联 Skill | pallastrade-payments |
| 关联 REQ | REQ-20260908-rev-p6-7-financial-convergence.md |
| 关联 PRD | REV-P6-1~6（done）；P4 FIN-P4-6/7/8（底座） |
| 需求类型 | 优化迭代（资金对账，feature gate） |

> 源：`豆包…/P6` §62。P4 已闭环不重做（Journal/Post/Resolve/RepairTransaction/Reconcile×/sweeper cron）。本包 = §62 最小缺口增量（G1-G5，2026-09-08 测绘）。边界：ambiguous 确定性落地（retry_execution/REV-P6-8）；provider 孤儿退款配对（偏大，并入 REV-P6-8）；Adyen/PayPal 契约适配（后续）。

## 1. 背景与目标
纯 refund posting 缺失无检测（subscriber 丢/吞异常后永不补记）；ReconcileRefund 不读 refund.state（ambiguous/manual 语义错置为 UNLINKED_LEGACY_PAYMENT、failed/canceled 永久噪音）；provider「无此退款」与宕机混报。目标：最小闭环 + 显式分类。
成功指标：succeeded+tx 无 entry → JOURNAL_POSTING_MISSING（sweeper→Repair 幂等补记）；ReconcileRefund 本地状态显式分类；provider missing 可机器区分；P0-P5 + 全量绿。

## 2/3. FR
- FR-R67-101（G1/G4）：`ReconcileTransaction#build_reasons` 增加 refund 侧 journal-missing（succeeded+transaction_id 且无 REFUND_SUCCEEDED entry）→ 并入 JOURNAL_POSTING_MISSING（sweeper 已按此 enqueue RepairTransactionJob）。
- FR-R67-102（G2）：`ReconcileRefund` 显式分类：failed/canceled → NOT_APPLICABLE+NO_PROVIDER_REFUND；ambiguous/manual_review 无引用 → NEEDS_ATTENTION+LOCAL_REFUND_AMBIGUOUS；有引用且 provider MATCHED → MATCHED+LOCAL_AMBIGUOUS_RESOLVED_BY_PROVIDER。
- FR-R67-103（G3）：provider 资源缺失（Stripe InvalidRequestError / 'no such refund'）→ PROVIDER_REFUND_MISSING；其余 → PROVIDER_UNAVAILABLE。

## 4. NFR
只读/幂等（延续 reconcile 约束）；无 migration；不自动动资金/state。

## 5. AC
| AC | 条件 | FR |
|---|---|---|
| AC-R67-01 | succeeded refund 缺 entry → txn reasons 含 JOURNAL_POSTING_MISSING；补记后收敛 | 101 |
| AC-R67-02 | failed/canceled → NOT_APPLICABLE+NO_PROVIDER_REFUND | 102 |
| AC-R67-03 | ambiguous/manual 无引用 → LOCAL_REFUND_AMBIGUOUS（非 legacy 错置） | 102 |
| AC-R67-04 | ambiguous 有引用 + provider MATCHED → MATCHED + LOCAL_AMBIGUOUS_RESOLVED_BY_PROVIDER | 102 |
| AC-R67-05 | provider missing → PROVIDER_REFUND_MISSING；其他异常 → PROVIDER_UNAVAILABLE | 103 |
| AC-R67-06 | 全量 backend-rspec ×2 + P0-P5 绿 | 全部 |

## 6. 跨层搜索（节选）
Core reconcile 服务；API/Admin/Storefront/Platform 无涉及。Skill 已读。

## 7. 技术影响
Core：`services/pallastrade/reconciliations/{reconcile_refund,reconcile_transaction}.rb`；specs：`spec/services/pallastrade/reconciliations/reconcile_rev_p6_7_spec.rb`（新增 6 例）+ 回归 43 全绿。

## 8. 测试计划
新增 reconcile_rev_p6_7_spec.rb（AC-R67-01~05）；回归 spec/services/pallastrade/reconciliations（49 绿）。

## 9. 文档同步
- [x] PRD/REQ/README/skill（REV-P6-7）/scenarios GS-066
- [ ] 全量验证 + doc-impact

## 10. 变更记录
| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-08 | 0.1 | 初稿（依据 §62 + 测绘 G1-G5） | AI |
| 2026-09-08 | 0.2 | 实施 G1/G2/G3 + spec 6 例（49 全绿） | AI |
