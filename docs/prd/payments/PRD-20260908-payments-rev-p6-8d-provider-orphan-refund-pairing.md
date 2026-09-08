# PRD-20260908-payments-rev-p6-8d-provider-orphan-refund-pairing

| 元数据 | 值 |
|---|---|
| 状态 | implementing |
| 创建日期 | 2026-09-08 |
| 来源 | 需求：REV-P6-8d Provider 孤儿退款配对（只读 OrphanPairing + rake + runbook） |
| 分类 | payments（语义归属） |
| 关联 Skill | pallastrade-payments |
| 关联 REQ | REQ-20260908-rev-p6-8d-provider-orphan-refund-pairing.md |
| 关联 PRD | REV-P6-1~7 + 8a/8b/8c（done）；REV-P6-7 G3 边界（孤儿配对）落地 |
| 需求类型 | 优化迭代（只读 ops 配对，feature gate） |

> 源：`豆包…/P6` §62 REV-P6-7 边界「provider 孤儿退款配对」+ FIN-P4-5 `fetch_financial_details` 已取回
> `provider_refund_references`（re_[]）未消费。本包 = **只读孤儿退款配对工具**：provider（Stripe charge）
> 上存在退款引用而无对应本地 Refund 行 → ORPHAN；本地 succeeded 引用在 provider 缺失 → LOCAL_UNMATCHED；
> 两两匹配 → matched。纯只读、零 provider mutation、不新建任何行（同 reconcile 约束）。无 UI/API（rake +
> runbook + service 供未来 Ops/Admin 消费）。

## 1. 背景与目标
REV-P6-7 已能对「本地已存在的 refund」逐单核对（ReconcileRefund）；但「provider 侧有退款、本地完全没有行」的
孤儿（Stripe 后台/其他系统直接退）没有任何检测——资金流出不可见。目标：利用已取回的 `provider_refund_references`
提供按 payment 的只读配对，输出 matched/orphans/local_unmatched 与原因，供运营排查（rake TSV + runbook）。
成功指标：Stripe/Bogus 支付可配对；孤儿/本地缺失可机器区分；rake 可扫描 store；全量绿。

## 2/3. FR
- FR-R68D-101：`Refunds::OrphanPairingResult`（transient VO，freeze）：status（matched/needs_attention/
  not_applicable/unsupported/unavailable）+ reasons[] + provider_refund_references[] + matched[]（provider_id,
  refund_id）+ orphans[]（provider_id）+ local_unmatched[]（transaction_id, refund_id）+ observed_at。
- FR-R68D-102：`Refunds::OrphanPairing.call(payment:)`（只读，镜像 ReconcilePayment 语义）：
  - StoreCredit/Check → not_applicable；无 `fetch_financial_details` 实现 → unsupported。
  - session 锚点缺失（payment_session 或组合 session fallback）→ unavailable（UNLINKED_LEGACY_PAYMENT）。
  - `fetch_financial_details`（只读）异常 → unavailable（PROVIDER_UNAVAILABLE，捕获不 raise）。
  - 取 `provider[:provider_refund_references]`（数组）；本地 `payment.refunds.where.not(transaction_id: nil)`。
  - 配对：provider_id ∈ 本地 transaction_id 集合 → matched；provider-only → orphans（ORPHAN_REFUND）；本地有
    transaction_id 但不在 provider 集合 → local_unmatched（LOCAL_REFUND_NOT_ON_PROVIDER）。有任一 orphan/
    local_unmatched → needs_attention，否则 matched。
- FR-R68D-103：rake `pallastrade:refunds:orphans[store_id]`：扫 store completed PSP 支付（有 session）→ 逐个
  OrphanPairing → TSV 输出（payment/状态/orphan ids/local_unmatched）+ 汇总；异常单行打印不中断。
- FR-R68D-104：runbook `docs/operations/refund-orphan-pairing-runbook.md`（语义/使用/解读/边界）。

## 4. NFR
只读/幂等（同 reconcile 不变式：零写/provider mutation/不自动退款）；provider 异常降级不 500；无 migration/API/UI。

## 5. AC
| AC | 条件 | FR |
|---|---|---|
| AC-R68D-01 | Stripe 形态 provider ids 与本地 succeeded 全部匹配 → matched，无孤儿 | 102 |
| AC-R68D-02 | provider 含本地无记录 id → orphans + needs_attention（ORPHAN_REFUND） | 102 |
| AC-R68D-03 | 本地 succeeded 引用不在 provider → local_unmatched + needs_attention | 102 |
| AC-R68D-04 | StoreCredit/Check → not_applicable；无契约 → unsupported；无 session/provider 异常 → unavailable（不 raise） | 102 |
| AC-R68D-05 | rake `pallastrade:refunds:orphans[store_id]` 可跑并输出 TSV/汇总（单店） | 103 |
| AC-R68D-06 | runbook 存在；payments skill/scenarios 更新；全量 backend-rspec ×2 + quick check + doc-impact | 104 |

## 6. 跨层搜索（节选）
Core：FIN-P4-5 `ProviderFinancialDetails.provider_refund_references`（Stripe gateway 已填充 re_[]；
Bogus 由本地 refunds 派生 `re_bogus_<id>`）；ReconcilePayment（capability/session fallback/provider 异常降级
范式）；`payment.refunds` + `transaction_id`（=provider refund id，apply_success authorization）。无既有孤儿
检测（ReconcileRefund 只处理本地已存在行）。API/Admin/Storefront/Platform 无涉。Skill: payments（REV-P6-7
边界/FIN-P4-5/6）、reconcile 语义、testing、prd、api-v3、customization（已读）。

## 7. 技术影响
Core：新增 `services/pallastrade/refunds/orphan_pairing.rb` + `orphan_pairing_result.rb`；
`lib/tasks/refunds.rake`（或并入 reconciliations.rake）加 `refunds:orphans`；docs runbook。无 migration/API/UI。
specs：`spec/services/pallastrade/refunds/orphan_pairing_spec.rb`（AC-R68D-01~04，Bogus 真实 + stub
fetch_financial_details 注入 provider ids）+ rake 冒烟（AC-R68D-05）。

## 8. 测试计划
orphan_pairing_spec：matched（Bogus 真跑）、orphan/local_unmatched（stub pm.fetch_financial_details 返回
Stripe 形态 hash）、not_applicable（store_credit/check）、unsupported（无实现方法）、unavailable（无 session/
异常 stub）。rake 冒烟可选。回归 refund/reconcile/8a/8b/8c 相关集 + quick check + 全量 ×2 + doc-impact。

## 9. 文档同步清单
- [ ] payments skill（REV-P6-8d 节）；scenarios GS-071；PRD/REQ/README + runbook；doc-impact。
- [ ] 边界记录：Admin/API 消费配对结果 → 后续（如需 UI 再开包）。

## 10. 变更记录
| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-08 | 0.1 | 初稿（依据 REV-P6-7 边界 + FIN-P4-5/6 数据面测绘） | AI |
