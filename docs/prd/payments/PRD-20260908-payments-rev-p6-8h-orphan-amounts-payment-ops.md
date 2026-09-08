# PRD-20260908-payments-rev-p6-8h-orphan-amounts-payment-ops

| 元数据 | 值 |
|---|---|
| 状态 | draft |
| 创建日期 | 2026-09-08 |
| 来源 | 需求：REV-P6-8h 孤儿退款配对金额扩展（retrieve_refund）+ Payment Ops 展示（用户三包授权 #2） |
| 分类 | payments |
| 关联 Skill | pallastrade-payments / pallastrade-admin / pallastrade-api-v3 |
| 关联 REQ | REQ-20260908-rev-p6-8h-orphan-amounts-payment-ops.md |
| 关联 PRD | 8d（孤儿配对，runbook 边界明言金额 retrieve_refund 扩展）；8g（Rails Admin Ops 基建） |
| 需求类型 | 优化迭代（只读取数 + Ops 可观测性，feature gate，**risk critical**） |

> 源：REV-P6 §62 + FIN-P4-5。**8d 边界落地**：OrphanPairing 只给 provider 引用不给金额——本包为
> orphan（provider-only 退款）按 provider id **只读**取金额/币种（Stripe `retrieve_refund`），扩展 rake TSV，
> 并新增 Rails Admin **Payments Ops** 只读页展示逐 payment 配对结果（含孤儿金额）。零写/provider mutation。

## 1. 背景与目标
8d 配对回答「provider 有退款而本地无行（ORPHAN）」，但无金额——Ops 无法评估资金缺口大小。目标：
1. **金额取数**：provider-only 退款 → 只读金额（Stripe 用既有 `retrieve_refund`；Bogus 无真实孤儿语义不实现，
   能力缺失自然降级）；逐条失败降级不整体失败（不猜）。
2. **rake**：`pallastrade:refunds:orphans` TSV 加 orphan 金额/币种列。
3. **展示**：Rails Admin **Payments Ops** 只读页——列表 = store completed PSP payments（含组合 payment）；
   详情 = `OrphanPairingResult` 全字段（matched/orphans[含金额]/local_unmatched + reasons/status）。

成功指标：Stripe（stub）orphan 条目含 amount/currency；无金额能力/异常 → amount=nil + reason
ORPHAN_AMOUNT_UNAVAILABLE 且整体仍 needs_attention；rake/页面可读；全量绿。零资金副作用。

## 2/3. FR
- FR-R68H-101（只读金额契约）：`PaymentMethod#provider_refund_amount(provider_reference)`（base = nil，
  NotImplementedError 语义改 nil 需谨慎——用 owner 判定同 CaptureEvidencePolicy 模式）→ Stripe 实现：
  `retrieve_refund(ref)` → `{ amount:, currency: }`（major units；provider 异常按 gateway 既有方式抛）。
- FR-R68H-102（OrphanPairing 金额扩展）：orphan 条目 `{ provider_id:, amount:, currency: }`（不可得 nil）；
  per-orphan rescue；能力缺失/全部不可得 → reasons 追加 `ORPHAN_AMOUNT_UNAVAILABLE`；外层 provider 异常
  降级 unavailable 不变；matched/local_unmatched 结构不变。
- FR-R68H-103（rake）：orphans TSV 加 orphan 金额列（`amount|amount` 与 provider_id 对齐；currency 列）。
- FR-R68H-104（Rails Admin Payments Ops）：`PaymentsOpsController`（read-only index/show）——index：store
  completed PSP payments（含组合 payment；列 id/状态/方法/金额/credit/order或combo/pairing 徽章）；show：
  OrphanPairingResult 全字段（re-run 在线一次，异常降级 nil 不 500——8a ReconcileRefund 模式）；nav
  Orders 子项 + tables + routes only index/show + i18n；权限 `can :read, Payment` 已覆盖（order_management
  `can :manage Payment`）。
- 边界（记录不实施）：Admin API v3 只读端点/SDK（yaml+SDK 级联重，另列）；自动 reconciliation 变化。

## 4. NFR
全程只读零副作用（同 8d/Reconcile）；逐条降级不 guess；金额不落库；无 migration。

## 5. AC
| AC | 条件 | FR |
|---|---|---|
| AC-R68H-01 | Stripe（stub retrieve_refund）孤儿条目含 amount/currency（major units） | 101/102 |
| AC-R68H-02 | 无金额能力（owner=base）/provider 异常 → 该孤儿 amount=nil + reason ORPHAN_AMOUNT_UNAVAILABLE；整体仍 needs_attention 不 500 | 102 |
| AC-R68H-03 | 单条孤儿金额失败不影响其他孤儿（逐条隔离） | 102 |
| AC-R68H-04 | rake TSV orphan 列含金额/币种 | 103 |
| AC-R68H-05 | Payments Ops index：completed PSP payments（含组合）列表 + 状态徽章；show：配对结果含孤儿金额；跨店隔离；无权限不可见 | 104 |
| AC-R68H-06 | matched/local_unmatched 结构向后兼容（8d specs 仍绿）；零写/provider mutation | 102 |
| AC-R68H-07 | 全量 backend-rspec ×2 + quick check + doc-impact | — |

## 6. 跨层搜索（节选）
core：OrphanPairing/Result（8d）、PaymentMethod base fetch_financial_details/owner 判定、Refunds rake；
stripe：gateway#retrieve_refund/fetch_refund_details（金额取数现成）；bogus 无真实孤儿语义（不实现）；
admin：8g PaymentCombinations 基建模板可复用；api/storefront/platform 无涉。

## 7. 技术影响
core：payment_method.rb（+base provider_refund_amount）、services/refunds/orphan_pairing.rb、lib/tasks/
refunds.rake；stripe gateway.rb（+provider_refund_amount）。admin：payments_ops_controller + views +
table/nav/routes/i18n（Rails Admin）。spec：orphan_pairing_spec 扩展 + payments_ops request spec。
无 migration/无 v3 端点。

## 8. 测试计划
orphan_pairing_spec 扩展（金额成功/能力缺失/逐条异常/reason）；stripe provider_refund_amount spec（stub
Stripe::Refund.retrieve）；rake 冒烟（TSV 列）；payments_ops request spec；回归 8d/8g/admin nav。
critical：手动 only recovery plan（只读取数无本地写——恢复=无动作，验证幂等）。

## 9. 文档同步清单
- [ ] payments skill（8h 节：金额+Payment Ops）；runbook refund-orphan-pairing 更新；scenarios GS-075；
  PRD/REQ/README；doc-impact。
- [ ] 边界：Admin API v3 端点/SDK → 后续。

## 10. 变更记录
| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-08 | 0.1 | 初稿（8d runbook 边界落地：金额 retrieve_refund + Payment Ops 展示） | AI |
