# REQ-20260908-rev-p6-8h-orphan-amounts-payment-ops.md

> 关联 PRD：`docs/prd/payments/PRD-20260908-payments-rev-p6-8h-orphan-amounts-payment-ops.md`
> Task：TASK-20260908183210-67aa46f1；Gate：GATE-2026-09-08T18-32-19（**risk critical**）
> 源需求：孤儿退款配对金额扩展（retrieve_refund）+ Payment Ops 展示（用户三包授权 #2）

## 背景（缺口）
8d runbook 边界：孤儿只给 provider 引用无金额；无 Payment 中心展示面。Stripe `retrieve_refund`/`fetch_refund_details`
金额能力现成（缺按 provider id 直查入口）；Bogus 无真实孤儿语义。

## FR/AC
见 PRD §2-5（FR-R68H-101..104；AC-R68H-01..07）。

## 6 层跨层搜索
| 层 | 结果 |
|---|---|
| backend/app | 无 override |
| core | OrphanPairing/Result + rake（8d）；PaymentMethod base owner 判定模式；**缺按 provider id 金额能力（缺口）** |
| api | 无涉（本包不做 v3 端点） |
| admin | 8g PaymentCombinations Ops 基建模板；**缺 Payment 中心页（缺口）** |
| storefront/platform | 无涉 |

## Skill 咨询结论表
| Skill | 结论 |
|---|---|
| pallastrade-payments | 8d 配对语义 + FIN-P4-5/6 provider 只读契约（retrieve_refund/fetch_refund_details/owner 判定）为金额取数依据；ReconcileRefund 异常降级模式。 |
| pallastrade-admin | Rails Admin 只读资源页模板（8g/8a）：ResourceController+TableConcern/tables/nav/routes/i18n；show 在线一次对账降级 nil 不 500。 |
| pallastrade-prd | R8 流程；critical risk → 需 manual-only recovery plan + evidence（test/review/knowledge/approval）。 |

## 反模式/约束
只读零副作用（无本地写/provider mutation，金额不落库）；逐条 rescue 不整体失败；matched/local_unmatched
结构向后兼容；owner 判定同 CaptureEvidencePolicy（勿破坏 unsupported 降级）；不手改生成文件（无生成变更）。

## 边界
Admin API v3 只读端点 + SDK（yaml 级联，另列）；自动 reconciliation 变化；Adyen/PayPal 契约（需沙箱）。
