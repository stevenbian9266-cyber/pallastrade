# REQ-20260908-rev-p6-7-financial-convergence

> PRD: docs/prd/payments/PRD-20260908-payments-rev-p6-7-financial-convergence-refund-posting.md
> 源: 豆包…/P6 §62。Task/Gate: 见 PRD（本文件配套）。
> G1 refund posting 缺失→JOURNAL_POSTING_MISSING（sweeper→Repair 闭环）；G2 ReconcileRefund 本地状态显式分类；G3 provider missing=PROVIDER_REFUND_MISSING。
> 无 migration；reconcile 只读不变式延续。specs: reconcile_rev_p6_7_spec.rb（6 例）+ 回归 43 全绿（49）。边界 ambiguous 落地/孤儿配对/Adyen 契约 → REV-P6-8。
