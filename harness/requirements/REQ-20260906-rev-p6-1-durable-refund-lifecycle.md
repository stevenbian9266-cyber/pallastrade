# REQ-20260906-rev-p6-1 — Durable Refund Lifecycle Foundation

> 关联 PRD：`docs/prd/payments/PRD-20260906-payments-rev-p6-1-durable-refund-lifecycle-foundation-退款-durable-生命周期.md`（approved）
> 源规格：`豆包梳理业务需求/P6 — Refund, Cancellation & Dispute Orchestration.md`（REV-P6 §54-56）
> Task：`TASK-20260906171149-ab0ec22c`；Gate：`GATE-2026-09-06T17-12-13`（feature，risk=critical）
> 分支：dev（gate 绑定当前分支）

---

## Step 0：跨层搜索（六层，gate 强制）

| 层 | 搜索路径 | 关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | refund / reimbursement / return | 无宿主 override（宿主零 PSP/Refund 直连） | 否——本包改框架层 |
| Core models | `pallastrade_gems/pallastrade_core/app/models/` | Refund / Payment / PaymentSplit / CommerceTransaction | `pallastrade/refund.rb`（after_create perform!）、`payment.rb`（credit_allowed=amount−offsets−refunds.sum）、`payment_split.rb`、`reimbursement_type/{original_payment,reimbursement_helpers}.rb` | 部分——升级；`Refunds::Execute` 需新建 |
| Core services/subscribers | `pallastrade_core/app/{services,subscribers}/` | ResolveRefund / PostRefund / refund.created | `financial_facts/resolve_refund.rb`（transaction_id→REFUND_SUCCEEDED）、`financial_ledger/post_refund.rb`、`subscribers/financial_ledger/refund_created_subscriber.rb`（create==success 假设） | 部分——需 state 守卫/新 subscriber |
| API Gem | `pallastrade_gems/pallastrade_api/app/` | refunds | `admin/orders/refunds_controller.rb`（index/create，with_order_lock + save）、`serializers/.../refund_serializer.rb` | 部分——create 入口需显式 Execute + state 字段 |
| Admin Gem | `pallastrade_gems/pallastrade_admin/app/` | refunds / reimbursements | legacy controllers（手动 fire） | 本包不动（Ops UI=REV-P6-8） |
| Storefront | `storefront/src/` | refund / return | 无售后/退款 UI | 否——无影响 |
| Platform | `platform/packages/` | refund | admin-sdk 类型（经 OpenAPI 生成） | admin.yaml 更新后同步 |

### 搜索结论

- 已存在：Refund 模型/资金链（P4 ResolveRefund/PostRefund/Reconcile）、PaymentSplit 组合分摊、Payment.with_lock 并发防护。
- 需新建：`PallasTrade::Refunds::Execute`（claim/三态 apply）、state 迁移/scope、`refund.succeeded` subscriber、2 个 migration（schema + backfill）。
- 防重复：全仓无 durable refund lifecycle / capacity reservation / 显式执行器；`FinancialLedger::Reverse` 未接线且本包明确不使用（冻结 F-4）。
- **不做**：ReverseTransaction、CommerceTransaction 倒退、Dispute、Cancellation Orchestrator、Restock 重构、async Job/Sweeper（后续 REV-P6-2~8）。

---

## Step 1：Skill 文件咨询

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树：行为/副作用用 Events+Subscriber，结构改动才 Decorator；本包在自持框架 gem 内直接修改模型/服务（团队产品，git 追踪，升级=merge）——符合最高优先级排序；不新建聚合 |
| `ai/skills/pallastrade-payments/SKILL.md`（领域） | ✅ 已读 | §Refunds：`create!` 现经 after_create 自动调网关、失败 raise（"create 即副作用"现状正是 P6 要消灭的模式）；`PaymentSplit.credit_allowed = captured − refunded` 为组合退款上限；FIN-P4-3 PostRefund 走 ResolveRefund→REFUND_SUCCEEDED |
| `ai/skills/harness-prd/SKILL.md` | ✅ 已读 | PRD 工作流：gate → REQ → 实施 → 测试（AC↔测试映射）→ 知识同步门；本任务走完整版 REQ |

**按需 Skill：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-events-webhooks` | ✅ 涉及（refund.succeeded 事件接线） | 待实施时读 | subscriber 注册/事件发布机制 |
| `pallastrade-data-model` | ✅ 涉及（refunds 表新增列） | 待实施时读 | 表结构/迁移约定 |
| `pallastrade-api-v3` | ✅ 涉及（serializer/admin.yaml） | 待实施时读 | 序列化/OpenAPI 约定 |
| `pallastrade-testing` | ✅ 涉及（spec 计划） | 待实施时读 | 测试位置约定 |
| `pallastrade-security` | ✅ 涉及（退款敏感操作） | 待实施时读 | 权限/审计约定 |

---

## 需求标题

REV-P6-1 Durable Refund Lifecycle Foundation：把 `PallasTrade::Refund` 从 successful-refund-only row 升级为 durable、幂等、带 capacity 的生命周期聚合，闭合 orphan PSP refund。

## 任务类型

新功能（资金安全重构，feature gate）

## 需求描述

现有 `Refund` 通过 `after_create :perform!` 在 DB 创建事务内同步调 PSP；失败/本地更新失败会回滚导致 **PSP 已退钱、本地无记录**（orphan PSP refund）。本包：
1. Refund 增 `state` 状态机（requested/processing/succeeded/failed/ambiguous/manual_review/canceled）+ ownership（commerce_transaction_id/target_order_id/payment_split_id）+ provider_idempotency_key + 生命周期时间戳 + last_error + attempt_count/lock_version；
2. `Payment#refundable_capacity` 语义升级（succeeded + active 占用，failed/canceled 释放），并发防双退；
3. 删除 `after_create :perform!`，新增 `PallasTrade::Refunds::Execute`（claim 与 provider I/O 分离、三态结果持久化、ApplySuccess 幂等），迁移 Admin API / gateway cancel 自动退款 / reimbursement 三个入口；
4. 资金守卫：仅 `refund.succeeded` → PostRefund（REFUND_SUCCEEDED）；非 succeeded 不误入账；
5. 历史 backfill（transaction_id 存在→succeeded）+ ownership 只填可证明；
6. Admin API `POST /orders/:id/refunds` 响应携带 state 等生命周期字段。

## 影响范围

- Core：`refund.rb`、`payment.rb`、`payment_combination.rb`/`payment_split.rb`（读语义）、`reimbursement_type/*`（limit 语义）、新增 `services/pallastrade/refunds/execute.rb`、subscriber 调整、`financial_facts/resolve_refund.rb`、`financial_ledger/post_refund.rb`（复核）。
- Provider：stripe/adyen/paypal gateway cancel 自动退款分支（改显式 Execute）、Bogus。
- API：admin refunds_controller + refund serializers（v3/admin）。
- 数据：2 个 migration + schema.rb。
- 文档：admin.yaml + platform docs + admin-sdk 类型。
- 测试：core/refund 相关 + provider gateway + api request + P4 ledger/reconcile + reimbursement spec（大量既有 spec 依赖 after_create 行为，需批量适配）。
- 知识同步：pallastrade-payments/data-model skill、anti-patterns.json（新增反模式）、scenarios.json、PRD 索引。

## 技术方案（初步）

- 直接修改自持框架 gem 内文件（PALLAS-CUSTOM 注释沿用于新迁移/新服务命名注记）。
- Refund 状态机：state_machine 显式迁移 + scope；删除 after_create perform!。
- `Refunds::Execute`：claim(requested→processing, with payment lock, commit) → provider I/O（idempotency key, DB lock 外）→ outcome apply（succeeded/failed/ambiguous，各自独立 tx）。
- ApplySuccess 幂等（state 守卫 + split/order/journal 幂等）。
- Subscriber：新增 `refund.succeeded` → PostRefund；`refund.created` 不再触发 posting。
- API create：save(requested) → Execute → 响应携带终态。
- 完整 async Job/Sweeper/Recover 属 REV-P6-2/6，不在本包。

## 风险点

- RISK-REV-01 orphan PSP refund（本包首要闭合对象）；RISK-REV-02/03 并发/ambiguous 双退（capacity + 状态机底座，完整闭环 P6-2）。
- 行为变更：Admin refunds create 契约（增加 state、失败返回明确态）；现有依赖 after_create 行为的 spec 大量需适配——回归面大，需 P0-P5 baseline 全绿 + refund 相关 spec 全绿。
- 回滚：migration 可回滚（drop 新列/索引/状态默认值）；backfill 幂等；功能回滚=git revert + 保留旧 after_create 分支（代码评审时确认无数据残留风险）。

## 决策节点（用户已确认 2026-09-07「实施」）

1. 范围=REV-P6-1（Foundation + v1 同步显式执行器），不含 async Job/Sweeper。
2. 执行兼容：reimbursement 退货链保留链内同步执行（AC-6003 对该链 deferred → REV-P6-4/5）。
3. `manual_review` 不占用 capacity（待 P6-6 复核）。
4. Admin API create 契约变更（state 字段 + 失败明确态返回）。

---

## 阶段③：实施后验证（不可跳过）

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| Ruby 模型/服务 | `refund.rb`/`payment.rb`/`refunds/execute.rb` 等 | refund_lifecycle / payment_refund_capacity / refunds/execute spec（docker rspec） | 21 examples 0 failures | ✅ |
| Provider gateway | stripe/adyen/paypal cancel 分支 + Stripe credit key | 受影响核心 spec 批次1（refund_spec/original_payment_child/subscriber/bogus_financial_details/resolve_refund/post_refund/reconcile_refund） | 35 examples 0 failures | ✅ |
| API 契约 | admin refunds_controller/serializer + admin.yaml（backend+platform） | 批次2（ownership/repair/reconcile_transaction/payment_split） | 33 examples 0 failures | ✅ |
| Migration | 2 migration + schema.rb（db:migrate 已跑 + test:prepare） | P0-payment-rspec 基线 | 81 examples 0 failures | ✅ |
| 全部 | — | `harness doc-impact` / `generated:check` / backend-rspec 全量（收尾时跑） | 见 evidence | ⬜ |

### 验证结论

新增 REV-P6-1 spec 21 例 + 受影响回归 101 例 + P0 基线 81 例全绿（本地容器 docker rspec）；
后续以 harness evidence / verifier 采集正式证据（verify-test）。
