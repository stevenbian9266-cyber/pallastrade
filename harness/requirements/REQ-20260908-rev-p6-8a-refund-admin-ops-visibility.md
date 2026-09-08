# REQ-20260908-rev-p6-8a-refund-admin-ops-visibility

> PRD: docs/prd/payments/PRD-20260908-payments-rev-p6-8a-refund-admin-ops-可见性-退款状态列表-详情-rails-admin.md
> Task: TASK-20260908070608-19ae8b61; Gate: GATE-2026-09-08T07-06-33（feature，非 critical）
> 源: 豆包…/P6 §63（REV-P6-8 Admin/Ops/Legacy Convergence）。本包 8a = **纯只读可见性**（零资金副作用/
> 零 provider mutation/不改状态机/不新增 API 端点）。边界: Manual Review/Retry → 8b；legacy reimbursement
> 同步链 async 拆链 + 孤儿退款配对 + retry_execution 接线 → 8c。

## 跨层搜索（节选）
- App: 无 host override（仅 ai_controller）→ 无涉。
- Core: `Refund` 状态机/时间戳/idempotency key/ownership/last_error/attempt_count 齐备（REV-P6-1/3/4/6）；
  `FinancialLedgerEntry(refund_id, REFUND_SUCCEEDED)` 事实行齐备；`Returns::RestockFact.resolve`（REV-P6-5）
  五态只读；`ReconcileRefund`/`SourceResult`（REV-P6-7/P4-6）只读在线。**缺口**: `Refund.for_store` scope 与
  `journal_entries` 便捷关联 → 新增（无 migration）。
- Admin: 顶级退款 Ops 页不存在（仅 payment 嵌套 create/edit + order 内嵌旧启发式表）；模板 =
  `TransactionsController`（TXN-P2-7：index/show + nav/tables/i18n 范式）。
- API/Storefront/Platform: 无涉（8a 不加 API/serializer/dashboard）。
- Skill: pallastrade-payments（REV-P6-1~7 节）、pallastrade-admin（导航/tables）、pallastrade-api-v3、
  pallastrade-customization、harness-prd、pallastrade-testing（已读）。

## Skill 咨询证据表
| Skill | 结论（真实） |
|---|---|
| pallastrade-payments | 退款持久层/状态机/时间戳/ownership/journal/restock/reconcile 数据源齐备（§339-475 已读）；本包只加可见性，不改状态机/资金 |
| pallastrade-admin | Rails Admin 扩展范式：ResourceController+TableConcern、nav sidebar（Orders 子项/landing/position/active/if）、tables 注册、i18n 双语、`# PALLAS-CUSTOM` gem 直接改、对象页加 crumb（导航自动推导）；TransactionsController 为顶级 ops 模板 |
| pallastrade-api-v3 | Admin API 约定：scope 由订单嵌套；serializer 已暴露 state/时间戳/last_error/split/order；8a 不新增端点（避免不必要 API 面） |
| pallastrade-customization | 决策树确认：可见性属 Admin 层自定义（改 gem 而非宿主）；不涉 decorator/event/DI |
| harness-prd | 流程：prd new（已自动分类 payments，无查重命中）→ 模板扩充（本 REQ 配套 PRD）→ 用户确认 → gate+实施 → prd verify |
| pallastrade-testing | Admin controller spec（render_views+stub_authorization!）+ API/模型 spec 范式；本包 controller/model spec 依此写 |

## 需求
1. `PallasTrade::Refund.for_store(store)` scope：单订单退款（payment.order.store）∪ 组合退款
   （payment.payment_combination.store，PaymentCombination 直连 store）并集；+ `has_many :journal_entries`
   （FinancialLedgerEntry，refund_id）+ 展示辅助（recovery/restock 只读派生方法，供视图薄调用）。PALLAS-CUSTOM 标记。
2. 顶级 Rails Admin 退款 Ops 页（Orders → Refunds 子菜单，叶子项）：store 作用域 + Ransack（state 多选/
   created_at 范围/id-订单号搜索）+ 默认 created_at desc；index 列 = prefixed id/state 徽章/order/payment/
   amount+currency/reason/provider reference(transaction_id)/requested_at/last_error_code——**index 零 provider I/O**。
3. 退款详情页 §63 全字段：头部(id+state+金额) · 五时间戳 · 原支付卡 · ownership 卡(commerce_transaction/
   target_order/payment_split，— 可空) · Provider 卡(transaction_id/provider_idempotency_key/execution key 派生) ·
   Journal 卡(REFUND_SUCCEEDED 行) · Reconciliation 卡(在线只读 ReconcileRefund→status/reasons，失败降级不 500) ·
   Restock 卡(reimbursement 关联 return_items 逐条 RestockFact 五态) · Recovery 卡(attempt_count/last_error_code+
   message/state 派生标签) · log_entries。
4. Legacy #1：order show `orders/_refunds.html.erb` 改真实 `refund.state` 徽章（移除 transaction_id 有无启发式）。
5. i18n 双语 + 权限 `can?(:manage, Refund)` + accessible_by；nav:validate 过。
无 migration；无 API/Storefront/Platform 改动。

## 验证
- refund_for_store_spec（AC-R68A-01/02）+ refunds_ops_controller_spec（AC-R68A-03~06/09：render_views，store 隔离、
  §63 字段、ReconcileRefund 降级、授权）+ order show `_refunds` 徽章断言（AC-R68A-08）→ 全量 backend-rspec ×2 +
  nav:validate + doc-impact。对应 PRD AC-R68A-01~10。
