# REQ-20260827-order-lifecycle-p3

> 关联 PRD：`docs/prd/payments/PRD-20260827-payments-实施-p3-父子单金额与支付状态派生-combined_total-payment-shipment_state-聚合.md`
> 上游方案：`docs/research/RESEARCH-20260826-order-lifecycle-upgrade-plan.md`（§P3）
> 风险：**critical**（金额/支付派生）——需人工恢复计划

---

## Step 0：跨层搜索（6 层）

| 层 | 搜索路径 | 搜索关键词 | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App | `backend/app/` | combined / parent total | 无 | ⛔ 需新建（core） |
| Core — models | `order.rb` | total / payment_total / shipment_state | 现有单订单逻辑 | ⛔ 需新增聚合方法 |
| Core — updater | `order_updater.rb` | update_shipment_state / update_payment_state | 派生规则（复用） | ✅ 参照 |
| API | `order_serializer.rb` | total / payment_status | 现有字段（P1 父子字段） | ⛔ 加聚合分支 |
| Admin | `pallastrade_admin/` | combined | 无 | ⛔ 继承 Store 序列化器 |
| Storefront | `storefront/src/` | combinedTotal | 无 | ⛔ P3 不涉及 |
| Platform | `platform/packages/` | combinedTotal | 无 | ⛔ P3 不涉及 |

### 搜索结论

无聚合派生实现；`combined_*`/`effective_*` 全新方法，序列化器父订单分支。**不覆写核心方法**（保护金额语义）。

---

## Step 1：Skill 文件咨询

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `pallastrade-customization` | ✅ 已读（P1/P2） | 业务逻辑放模型/服务方法，避免过度耦合 |
| `pallastrade-data-model` | ✅ 已读（P1/P2） | Order 父子模型（P1）；金额派生聚合 |
| `pallastrade-payments` | ✅ 已读（P1） | PaymentSplit 分摊（P1/P2）；payment_state 派生 |
| `pallastrade-checkout` | ✅ 已读（P2） | 订单状态机；shipment_state/payment_state 语义 |
| `pallastrade-testing` | ✅ 已读（P1） | RSpec + FactoryBot；order factory |

---

## 需求标题

订单生命周期升级 P3：父子单金额与支付状态派生（`combined_*` 聚合方法 + 序列化器父订单分支）。

## 任务类型

新功能（金额/支付派生，Risk critical）

## 需求描述

为拆单后的父订单（容器）提供金额/支付/发货状态的**聚合派生方法**（`combined_total`/`combined_payment_total`/`combined_outstanding_balance`/`combined_amount_due`/`combined_shipment_state`/`combined_payment_state`/`effective_payment_total`），并在 Store/Admin 序列化器对父订单输出聚合值。**不覆写核心方法**，无 children 时零行为变化。

## 影响范围（harness affected）

仅 `pallastrade_core`（order.rb 方法）+ `pallastrade_api`（order 序列化器）+ 测试。无迁移、无 API 变更。

## 技术方案（初步）

1. `Order` 聚合方法（有 children 时聚合，无 children 回退原值）：
   - `combined_total` = own_total + Σ children.combined_total（递归）
   - `combined_payment_total` = own payment_total + Σ children
   - `combined_outstanding_balance` = combined_total - (combined_payment_total + reimbursement_paid_total)
   - `combined_amount_due` = max(combined_outstanding_balance - store_credit, 0)
   - `combined_shipment_state` / `combined_payment_state`：套用 `OrderUpdater` 规则
   - `effective_payment_total`：有 `PaymentSplit` 用 split(captured - refunded)，否则 payment_total
2. 序列化器：`parent_order?` 时 `total`/`display_total`/`amount_due`/`payment_status`/`fulfillment_status` 用聚合。

## 风险点

| 风险 | 缓解 |
|---|---|
| 覆写核心方法破坏金额语义 | 仅新增 `combined_*`，不覆写 `total`/`payment_total`/`outstanding_balance` |
| 递归环 | 依赖 `root_order` 防环（P1）；测试深层 |
| 序列化器父订单聚合影响前端 | 仅 `parent_order?` 分支，无 children 不变；前端未消费不感知 |
| 金额不一致（critical） | spec 断言聚合守恒；恢复计划：删除方法+序列化器分支即可回退（无迁移） |

---

## 恢复计划（Risk critical 要求，`harness recovery create`）

**触发**：聚合方法或序列化器导致金额/支付状态错乱（父订单展示错误、子订单受影响）。

**恢复步骤**：
1. **代码回滚**：`git revert <P3 commit>`（或 checkout 上一提交），移除 `combined_*`/`effective_*` 方法 + 序列化器父订单分支。
2. **无迁移**：P3 无数据变更，回滚零 DB 影响。
3. **验证**：`harness check --profile quick` + 相关 rspec 全绿（聚合用例移除后原有 P1/P2 用例应仍全绿）。
4. **数据检查**：确认父订单/子订单金额列未被修改（P3 只读派生，不写列）。
5. **人工确认**：回滚后父订单展示回到 P2 行为（父容器金额为自身值），不影响子订单交易。
