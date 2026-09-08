# PRD-20260908-payments-rev-p6-8g-combination-visibility-rails-admin

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-08 |
| 来源 | 需求：REV-P6-8g Rails Admin 组合可视化 + 退款聚合展示（G6） |
| 分类 | payments（语义归属；实现层 = pallastrade_admin） |
| 关联 Skill | pallastrade-admin / pallastrade-payments |
| 关联 REQ | REQ-20260908-rev-p6-8g-combination-visibility.md |
| 关联 PRD | REV-P6-8a（Refund Ops 模式，tables/nav/helper/i18n 基建）；8f（组合取消）；REV-P6-3/8f（split/资金语义） |
| 需求类型 | 优化迭代（Ops 可观测性，feature gate） |

> 源：REV-P6-8a 归并规划（G6）+ 组合资金语义（split captured/refunded/credit）。**本包 = Rails Admin
> 只读 PaymentCombination 管理页**（index + show），展示组合状态/金额、逐成员 PaymentSplit
> captured/refunded/credit_allowed、组合 Payment 关联 refunds（复用 8a 状态徽章/字段）、CommerceTransaction
> 摘要与详情互链。零资金副作用（只读）；无 API v3/Storefront 变更。

## 1. 背景与目标
组合支付（PaymentCombination/split）自 P4/P5 起成为资金主干，但 Rails Admin 无任何组合管理面——Ops 无法
回答「组合里哪个成员已退/未退、split 剩多少可退、组合交易状态」。REV-P6-8a 已为 Refund 建了只读 Ops
（RefundsOpsController + tables + nav + helper + i18n），本包以同一基建把 PaymentCombination 加进 Rails Admin。
成功指标：superuser/order_manager 可在 Admin → Orders → Payment Combinations 看组合列表并打开详情，看到
每 split captured/refunded/credit + 组合退款行（真实 state 徽章）+ 关联 transaction；全量绿。

## 2/3. FR
- FR-R68G-101（列表）：`PaymentCombinationsController#index`（ResourceController+TableConcern）——列：
  prefixed_id、status（custom partial 徽章）、amount(money)、成员数（custom：splits.count）、已退合计
  （custom：splits sum refunded_amount）、created_at。`collection_default_sort='created_at desc'`。
- FR-R68G-102（详情）：`show` —— 组合头卡（状态徽章/金额/currency/customer/created/completed/expires）+
  逐成员 split 卡（order number 链接、captured/refunded/credit_allowed、该 split 的 refunds 行[8a 徽章字段]）+
  组合 Payment 卡（state/amount/credit_allowed + 其 refunds）+ CommerceTransaction 卡（状态摘要 →
  admin_transaction_path 互链）。ar_lazy_preload 防 N+1（preload orders/payments/refunds）。
- FR-R68G-103（基建接线）：routes `resources :payment_combinations, only: [:index, :show]`（admin 命名空间）；
  tables `register(:payment_combinations, …)` + 列；nav Orders 子项（position 35，guard can?(:read, PaymentCombination)）；
  helper `payment_combinations_helper.rb`（combo status badge）并在 Admin::BaseController `helper` 注册；
  i18n en.yml + admin_nav.zh-CN.yml（admin.orders.payment_combinations*）。
- FR-R68G-104（权限）：order_management 增加 `can :read, PallasTrade::PaymentCombination` 与
  `can :read, PallasTrade::PaymentSplit`（OrderManager 可看组合页；super_user 天然 manage all）。
- 边界（记录不实施）：写操作（无 new/edit/delete——组合资金不可在 Admin 手改）；Rails Admin 上对组合触发
  取消/退款按钮（已由 8f Admin API 承担）；Admin API v3 组合只读端点与 SDK（另列 8h 评估）。

## 4. NFR
只读零副作用；N+1 经 ar_lazy_preload；无 migration；页面遵循 8a Ops 模式（turbo/see_other 仅未来写动作）；
非超管可见性受 can? guard + 权限集约束。

## 5. AC
| AC | 条件 | FR |
|---|---|---|
| AC-R68G-01 | Admin → Orders → Payment Combinations 列表：succeeded/pending 组合均显示，状态徽章正确、金额/成员数/已退合计列正确 | 101/103 |
| AC-R68G-02 | 详情页：succeeded 组合显示每成员 split（order 链接、captured/refunded/credit_allowed）；组合 Payment refunds 行含 8a state 徽章；CommerceTransaction 摘要 + 互链 | 102 |
| AC-R68G-03 | 组合退款（payment.order nil + payment_split_id）在详情内可见且退款 state 真实（非旧启发式） | 102 |
| AC-R68G-04 | superuser 与 order_manager（含 read PaymentCombination/Split）均可访问；无权限角色 403；写动作不存在 | 104/103 |
| AC-R68G-05 | routes/nav/tables/i18n/helper 全接线；既有 admin nav/table 无回归 | 103 |
| AC-R68G-06 | 全量 backend-rspec ×2 + quick check + doc-impact | — |

## 6. 跨层搜索（节选；每层独立）
- backend/app：无 host override。
- core：PaymentCombination（has_prefix_id pcom/SingleStoreResource/状态机/orders through splits/payments/
  commerce_transaction）；PaymentSplit（credit_allowed=captured−refunded）；Refund.for_store（via_combination
  已含组合退款）；无 admin 展示需求实现。
- api：admin 仅 cancel member（8f）；无组合只读端点（本包不做）。
- admin：**无 PaymentCombination controller/nav/tables/i18n（缺口）**；8a RefundsOps + TransactionsController
  基建齐全（模式模板）。
- storefront/platform：无涉。

## 7. 技术影响
pallastrade_admin：controllers/payment_combinations_controller.rb（新）、views/payment_combinations/
{index,show}.html.erb（新）、config/initializers/pallastrade_admin_{tables,navigation}.rb、config/routes.rb、
helpers/payment_combinations_helper.rb、locales/en.yml。core：permission_sets/order_management.rb（+read×2）。
无 migration/API/UI 前台。

## 8. 测试计划
request/feature spec：admin 登录（superuser/order_manager/受限角色）→ 列表含组合、详情显示 split 汇总与退款
徽章、403 场景（controller spec stub_authorization! 或 request spec 带权限上下文）；tables/nav 冒烟含在
quick check nav-validate + 既有 admin request specs 回归。参考 8a request spec 结构。

## 9. 文档同步清单
- [x] payments skill（REV-P6-8g 节）；scenarios GS-074；PRD/REQ/README；doc-impact。
- [x] 边界：组合写动作、Admin API 组合只读端点 → 8h 评估。

## 10. 变更记录
| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-08 | 0.1 | 初稿（依据 8g 调研：admin 无组合面=G6 缺口；8a Ops 基建可复用） | AI |
| 2026-09-08 | 1.0 | done：实施完成（commit 0a2b4b8）——只读 PaymentCombination 页（index/show）+ nav/table/i18n/helper + read 权限；spec 4/4 + nav spec 更新；全量 ×2 绿 | AI |
