# PRD-20260908-payments-rev-p6-8a-refund-admin-ops-可见性-退款状态列表-详情-rails-admin

| 元数据 | 值 |
|---|---|
| 状态 | implementing |
| 创建日期 | 2026-09-08 |
| 来源 | 需求：REV-P6-8a Refund Admin Ops 可见性 — 退款状态列表/详情（Rails Admin） |
| 分类 | payments（自动判定） |
| 关联 Skill | pallastrade-payments / pallastrade-admin |
| 关联 REQ | REQ-20260908-rev-p6-8a-refund-admin-ops-visibility.md |
| 关联 PRD | REV-P6-1~7（done）；REV-P6-8 为收尾包（本包 8a=纯可见性，8b=Manual Review/Retry，8c=legacy 拆链） |
| 需求类型 | 优化迭代（Admin/Ops 可见性，feature gate） |

> 源：`豆包…/P6` §63（REV-P6-8 — Admin / Ops / Legacy Convergence）。本包 **REV-P6-8a = 纯只读可见性**：
> Rails Admin 退款 Ops 列表/详情 + §63 全字段展示（状态/原支付/事务/归属/金额/Provider 引用与幂等键/时间戳/
> Journal/对账/restock/恢复/Last Error）。**零资金副作用、无状态机/无 provider mutation**（对账仅在线只读
> `ReconcileRefund`，沿用 P4 只读不变式）。边界：Manual Review/Retry 动作 → 8b；legacy reimbursement 同步链
> async 拆链 + 孤儿退款配对 + ambiguous retry_execution 接线 → 8c（各自独立 PRD）。

## 1. 背景与目标
REV-P6-1~7 已把退款持久层字段备齐（state/五时间戳/provider_idempotency_key/last_error_code+message/
attempt_count/ownership 三列/lock_version/log_entries/Journal FK），但 **Ops 无处可看**：Rails Admin 只有 order
内嵌退款表且仍用 `transaction_id` 有无的旧启发式（未显示 REV-P6-1 的 `state`）；无退款列表/详情页；restock
（REV-P6-5 RestockFact 五态）、reconciliation（REV-P6-6/7 SourceResult 只读派生）、recovery（attempt/last_error）
均无展示入口。目标：按 §63 字段清单交付「退款 Ops 可见性」——任一 refund 一行到位、可下钻看全链路事实。
成功指标：退款列表/详情可用；§63 所列字段在详情页全部可达；旧启发式移除；controller/model spec 覆盖 store
隔离与关键字段渲染；全量 backend-rspec 绿。

## 2. 用户故事 / 场景
- 作为运营/资金操作员，我希望在一处看到所有退款（跨取消/退货/单独发起）及其状态与全链路证据，以便排查
  ambiguous/manual_review/失败退款，并判断下一步（人工 review 归 8b）。
- 场景：单订单退款（payment.order 锚定）；组合支付退款（payment_combination.store 锚定，payment.order 为 nil）；
  reimbursement 链退款（detail 关联退货 restock 事实）；成功退款（journal 已补记）；ambiguous/manual（需人工）。
- 边界/异常：另一 store 的退款不可见（store 隔离）；provider 侧对账在 show 页只读在线派生且失败不 500（降级展示）。

## 3. 功能需求（FR）
- FR-R68A-101：`PallasTrade::Refund.for_store(store)` scope —— 单订单退款经 `payment.order.store` + 组合退款经
  `payment.payment_combination.store`（PaymentCombination 直连 store）并集；另加只读展示辅助
  `Refund#journal_entries`（FinancialLedgerEntry.refund_id，REFUND_SUCCEEDED 事实行）。
- FR-R68A-102：新顶级 Rails Admin 退款 Ops 页（Orders → Refunds 子菜单，落地 Orders 模块内叶子）：store 作用域、
  Ransack（state 多选/created_at 范围/id 或订单号/金额），默认 created_at desc；列 = prefixed id(链接)、state 徽章、
  Order(number 链接)、Payment(method+链接)、Amount/Currency、Reason、Provider Reference(transaction_id)、
  requested_at、Last Error code。**index 零 provider I/O**（对账/restock 不进列表列）。
- FR-R68A-103：退款详情页按 §63 渲染：①头部 prefixed id+state 徽章+amount/currency；②生命周期时间戳
  （requested/processing/succeeded/failed/ambiguous_at，manual_review 以 updated_at 注记）；③原支付卡
  （payment 链接+method+state+captured+所属 order 链接）；④Ownership 卡（commerce_transaction/target_order/
  payment_split 链接，可空显示 —）；⑤Provider 卡（transaction_id=provider refund reference、provider_idempotency_key、
  execution_idempotency_key 只读派生）；⑥Journal/Fact 卡（REFUND_SUCCEEDED entry 行：entry_type/amount/currency/
  idempotency_key/effective_at + 跳转 transaction show）；⑦Reconciliation 卡（在线只读 `ReconcileRefund.call`
  → SourceResult status/reasons/observed_at；失败降级不 500）；⑧Restock 卡（reimbursement 关联 return_items 逐条
  `RestockFact.resolve` 五态；无退货关联显示 —）；⑨Recovery 卡（attempt_count、last_error_code/message、
  state 派生恢复建议标签）；⑩log_entries 审计。
- FR-R68A-104（Legacy Convergence #1）：order show 内嵌 `_refunds` 表改用真实 `refund.state` 徽章
  （succeeded/processing/requested/failed/ambiguous/manual_review/canceled），移除 transaction_id 有无的旧启发式。
- FR-R68A-105：i18n 双语（en + zh-CN）nav/page 文案；权限按 `can?(:manage, PallasTrade::Refund)` 门控
  （OrderManagement permission set 已授 manage Refund）+ `accessible_by` 记录级。
- FR-R68A-106：`nav:validate` 过（landing/子菜单/双语/i18n 完整性）。

## 4. 非功能需求（NFR）
- 只读/零副作用：index/show 不触发任何 provider I/O、不写库、不改 state；Reconciliation 仅 show 页在线只读
  一次（同 P4 §44/AC-4023 不变式）；index 列表禁止 provider 调用（性能）。
- store 隔离：任何退款不出 current_store 作用域。
- 兼容：不破坏既有嵌套 RefundsController（new/create/edit/update per payment）与 order cancel 链。
- 可维护：视图逻辑薄，派生逻辑放模型/service 只读方法并单测。

## 5. 验收标准（AC，与测试一一映射）
| AC | 条件 | FR |
|---|---|---|
| AC-R68A-01 | `Refund.for_store`：单订单退款（payment.order）与组合退款（payment.payment_combination）均在列；异 store 退款不在列 | 101 |
| AC-R68A-02 | `Refund#journal_entries` 返回该 refund 的 REFUND_SUCCEEDED ledger 行（无则空） | 101 |
| AC-R68A-03 | GET /admin/refunds：渲染当前 store 退款（含 state 徽章/金额/order 链接），不含异 store；无 provider 调用 | 102 |
| AC-R68A-04 | 列表支持 Ransack state 过滤 + created_at 范围 + 默认 created_at desc | 102 |
| AC-R68A-05 | GET /admin/refunds/:id 渲染 §63 字段：state、五时间戳、原支付、ownership、transaction_id、idempotency key、journal、last_error | 103 |
| AC-R68A-06 | show 页 Reconciliation 卡在线只读调用 ReconcileRefund 展示 status/reasons；provider 异常降级不 500 | 103 |
| AC-R68A-07 | show 页 Restock 卡：reimbursement 关联 refund 列出 return_items RestockFact 五态；无关联显示 — | 103 |
| AC-R68A-08 | order show `_refunds` 表显示真实 state 徽章（旧 transaction_id 启发式移除） | 104 |
| AC-R68A-09 | 无 manage Refund 权限角色访问 /admin/refunds → 拒绝；nav 按权限显隐 | 105 |
| AC-R68A-10 | `harness nav:validate` 通过（Orders → Refunds 子项、双语 i18n）；全量 backend-rspec ×2 + doc-impact 绿 | 106/全部 |

## 6. 跨层搜索记录（6 层，gate 强制）
| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | refund/refunds admin override | 无 override（仅 ai_controller） | 满足（宿主无涉） |
| Core | `pallastrade_gems/pallastrade_core/app/` | Refund 模型/状态机/服务 | `models/pallastrade/refund.rb`（state 机+时间戳+ownership+idempotency）、`refunds/{request,execute,recover}.rb`、`returns/restock_fact.rb`、`reconciliations/{reconcile_refund,source_result}.rb`、`financial_ledger_entry.rb` | 数据源齐备；缺 `for_store` scope 与 `journal_entries` 便捷关联 → 新增 |
| API | `pallastrade_gems/pallastrade_api/app/` | admin refund serializer/controller | `admin/refund_serializer.rb`（已暴露 state/时间戳/last_error_message/split/order）、`admin/orders/refunds_controller.rb`（仅 order 嵌套 index/create） | 8a 不新增 API（serializer 已足）；dashboard 消费留 8b/8c |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | refunds/transactions controller+views+nav+tables | `admin/refunds_controller.rb`（belongs_to payment 仅 create/edit）、`orders/_refunds.html.erb`（旧启发式）、`admin/transactions_controller.rb`（TXN-P2-7 模板：index+show+recover）、`pallastrade_admin_tables.rb` L2457 transactions 注册、`pallastrade_admin_navigation.rb` L82 transactions 子项 | 缺退款 Ops 顶级 index/show + nav + tables → 新增（镜像 transactions） |
| Storefront | `storefront/src/` | refund 展示 | 无 admin 侧相关（storefront 无退款 Ops） | 满足（无涉） |
| Platform | `platform/packages/` | refund/dashboard | dashboard 存在但退款 Ops 目前在 Rails Admin；无既有能力 | 满足（8a 不动；dashboard 迁移留后续） |

**结论**：持久层/只读服务全齐（REV-P6-1/5/6/7 产物），缺口集中在 Admin 展示层——新建顶级退款 Ops 控制器/
视图/nav/table + Refund `for_store` 与 journal 关联 + order 内嵌表状态徽章修复。防重复：不新增 API 端点、
不改 serializer、不改状态机、不新建任何资金/事实模型。模板 = TXN-P2-7 `TransactionsController`（本仓库既有范式）。

## 7. 技术影响
- Core：`models/pallastrade/refund.rb`（+`for_store` scope + `has_many :journal_entries` 关联 + 只读恢复/展示
  辅助方法，PALLAS-CUSTOM 标记）。无 migration（无新列；FinancialLedgerEntry.refund_id 已存在）。
- Admin gem（# PALLAS-CUSTOM: REV-P6-8a）：新增 `admin/refunds_ops_controller.rb`（或等价顶级 ops 控制器，
  继承 ResourceController，镜像 TransactionsController：model_class/scope/object_name/find_object/authorize）、
  `views/pallastrade/admin/refunds_ops/{index,show}.html.erb`、路由 `resources :refunds, only: [:index, :show],
  controller: 'refunds_ops'`、`pallastrade_admin_tables.rb` 注册 refunds 表、`pallastrade_admin_navigation.rb`
  Orders 子项 `refunds`、i18n en + zh-CN（gem en.yml + backend/config/locales/admin_nav.zh-CN.yml）、
  `orders/_refunds.html.erb` 状态徽章修复。
- 无 API/Storefront/Platform 改动。nav:validate 必须过（plugin-nav-validate）。

## 8. 测试计划
- 新增：`spec/models/pallastrade/refund_for_store_spec.rb`（AC-R68A-01/02：单订单+组合+异 store 隔离+journal 关联）；
  `spec/controllers/pallastrade/admin/refunds_ops_controller_spec.rb`（AC-R68A-03~06/09：render_views，index 列与
  store 隔离 + 无 provider 调用断言、show §63 字段渲染、ReconcileRefund 降级、授权拒绝）；`_refunds` 徽章
  （AC-R68A-08）可并入既有 order admin spec 或新增小型渲染断言。
- 更新：相关既有 order/payment admin spec（如断言行内退款表仍可用）。
- AC→测试映射：AC-R68A-01~02→refund_for_store_spec；03~06/09→refunds_ops_controller_spec；08→order show spec；
  10→harness nav:validate + 全量 backend-rspec + doc-impact。
- 运行：docker exec spec（按惯例），提交前/后全量 backend-rspec ×2。

## 9. 文档同步清单（知识同步门）
- [ ] Skill：`ai/skills/pallastrade-payments`（REV-P6-8a 节）+ `ai/skills/pallastrade-admin`（Refund Ops 页导航/
  模板范式节，若涉及新模式）。
- [ ] scenarios：新增 GS-067（Refund Admin Ops 可见性）。
- [ ] 本 PRD 状态更新 + `docs/prd/README.md` 索引 + REQ 关联。
- [ ] 无 API 文档改动（无新端点）；无 AGENTS/CLAUDE 改（如涉及反模式/任务规则另议）。
- [ ] doc-impact --base origin/dev 通过。

## 10. 变更记录
| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-08 | 0.1 | 初稿（依据 §63 + Explore 六层测绘） | AI |
| 2026-09-08 | 0.2 | 实施：Refund.for_store/journal_entries/ransack 白名单 + RefundsOpsController/视图/路由/tables/nav/i18n + _refunds 状态徽章修复；模型 spec 5 例 + 请求 spec 8 例 + 回归 92 例全绿 + quick check（nav-validate OK/无 AP） | AI |
