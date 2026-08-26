# PRD-20260826-payments-实施-p1-数据模型与语义方法-父子单-parent_id-paymentcombination-paymentspli

| 元数据 | 值 |
|---|---|
| 状态 | verifying |
| 创建日期 | 2026-08-26 |
| 来源 | 需求：实施 P1 数据模型与语义方法（父子单 parent_id / PaymentCombination / PaymentSplit） |
| 分类 | payments（自动判定） |
| 关联 Skill | pallastrade-data-model、pallastrade-payments、pallastrade-decorators、pallastrade-resource、pallastrade-testing |
| 关联 REQ | REQ-20260826-order-lifecycle-p1.md（实施时回填） |
| 关联 PRD | N/A（全新；上游方案 `docs/research/RESEARCH-20260826-order-lifecycle-upgrade-plan.md` §P1） |
| 需求类型 | 新功能（数据层地基，纯增量） |

---

## 1. 背景与目标

- **一句话需求原文**：需求：实施 P1 数据模型与语义方法（父子单 parent_id / PaymentCombination / PaymentSplit）
- **背景**：订单生命周期升级方案（P0-P8，`docs/research/RESEARCH-20260826-order-lifecycle-upgrade-plan.md`）的 **P1 阶段**。为后续父子单结构、自动/手动拆单、合并支付铺**数据地基**。P1 仅建数据模型 + 语义方法，**不接入任何业务流程**（零行为变化）。
- **目标**：
  1. `orders.parent_id`（自引用 FK）+ `split_from_id` + `payment_combination_id`（均可空）；
  2. 新表 `pallastrade_payment_combinations`、`pallastrade_payment_splits`；
  3. `payments.payment_combination_id`、`payment_sessions.payment_combination_id`（可空）；
  4. `Order` 父子语义方法 + `PaymentCombination`/`PaymentSplit` 模型 + 状态机（非法迁移转业务错误）；
  5. Store/Admin `OrderSerializer` 输出父子字段。
- **成功指标**：迁移全部可 down、可重复；线上行为零变化（无 parent_id 数据 = 无影响）；现有 CI 测试不回归。

## 2. 用户故事 / 场景

> P1 是数据层地基，无直接用户故事；以下为技术场景（供测试与验收映射）。

- **S1（正常）**：现有订单迁移后 `parent_id = NULL`，`single_order? == true`（未拆单订单不受影响）。
- **S2（正常）**：新建 `PaymentCombination` 默认 `pending`；`pending→processing→succeeded` 正常流转。
- **S3（边界）**：对 `succeeded` 的组合再调用 `complete` → 返回**业务错误**（`code + message`），不抛 `StateMachine::InvalidTransition`。
- **S4（边界）**：`Order#root_order` 在深层父子链上不无限递归（防环）。
- **S5（异常）**：`payment_splits` 对同一 `[combination_id, order_id]` 重复插入 → 唯一索引拒绝（幂等基础）。

## 3. 功能需求（FR）

- **FR-001**：迁移 `orders.parent_id`（可空自引用 FK，index）；`Order` 增加 `parent`/`children` 关联（`dependent: :nullify`）。
- **FR-002**：迁移 `orders.split_from_id`（可空 FK，index）；`Order` 增加 `split_from`/`split_orders` 关联（`dependent: :nullify`）。
- **FR-003**：新表 `pallastrade_payment_combinations`（store_id/customer_id/currency/amount/status/expires_at/completed_at/metadata），模型 + `has_prefix_id` + 状态机。
- **FR-004**：新表 `pallastrade_payment_splits`（combination_id/order_id/payment_id/authorized_amount/captured_amount/refunded_amount/currency，唯一索引 `[combination_id, order_id]`），模型。
- **FR-005**：迁移 `payments.payment_combination_id`（可空，index）——合并支付时 payment 挂组合（`order_id` 可空），单笔支付不变。
- **FR-006**：迁移 `payment_sessions.payment_combination_id`（可空，index）——保持 `session ↔ payment` 1:1 契约。
- **FR-007**：`Order` 语义方法：`parent_order?` / `child_order?` / `single_order?` / `sibling_orders` / `root_order`（防环）。
- **FR-008**：`PaymentCombination` 状态机：`pending → processing → succeeded | failed | canceled | expired`；**非法迁移在模型层 `rescue` 转业务错误**（`code + message`），不抛框架异常。
- **FR-009**：`PaymentSplit` 模型（belongs_to combination/order/payment）。
- **FR-010**：Store + Admin `OrderSerializer` 增加 `parent_id` / `children_ids` / `is_parent` / `is_child` / `is_single`。

## 4. 非功能需求（NFR）

- **可回滚**：全部迁移可 `down`（drop 列/表），可重复执行。
- **零行为变化**：不接入任何流程/端点/前端，P1 上线对现有订单/支付/发货/售后无影响。
- **状态机健壮性**：非法迁移一律返回业务错误，绝不裸抛状态机异常（吸取上次 PaymentGroup 裸 422 教训）。
- **兼容**：新列全部 nullable；`has_prefix_id` 遵循核心惯例（`pcom_` / `psplit_`）。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001 ← FR-001**：`orders.parent_id` 列存在且可空 + index；`parent`/`children` 关联工作（model spec + schema）。
- **AC-002 ← FR-002**：`split_from_id` 列存在；`split_from`/`split_orders` 关联工作。
- **AC-003 ← FR-003**：`payment_combinations` 表结构匹配模型；默认 `pending`。
- **AC-004 ← FR-004**：`payment_splits` 表 + 唯一索引 `[combination_id, order_id]`。
- **AC-005 ← FR-005/006**：`payments` / `payment_sessions` 的 `payment_combination_id` 可空 + index。
- **AC-006 ← FR-007**：语义方法正确（parent/child/single/sibling/root 防环）。
- **AC-007 ← FR-008**：非法迁移返回业务错误（不抛 `StateMachine::InvalidTransition`）。
- **AC-008 ← FR-010**：Store/Admin serializer 输出 `parent_id`/`children_ids`/`is_parent`/`is_child`/`is_single`。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | parent_id / combination / split | 无（Host App 无订单自定义模型） | ⛔ 需新建（core 层） |
| Core | `pallastrade_gems/pallastrade_core/app/` | parent_id / split_from / combination / children | `order.rb` 无任何相关实现 | ⛔ 需新建 |
| API | `pallastrade_gems/pallastrade_api/app/` | payment_combination / children_ids / is_parent | `parent_id` 仅存在于 categories（分类 nested set，与订单无关） | ⛔ 需新建（序列化器字段） |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | payment_combination / children_ids / is_parent | 无 | ⛔ 需新建（序列化器字段，P1 仅 API 层） |
| Storefront | `storefront/src/` | paymentCombination / childrenIds / isParent | 无 | ⛔ P1 不涉及（P5 起） |
| Platform | `platform/packages/` | paymentCombination / childrenIds / paymentSplits | 无 | ⛔ P1 不涉及 |

**结论**：全仓库无任何订单父子/支付组合/支付分摊实现（上次失败实现已随回滚删除，schema 已还原）。P1 全部为**新建**，无重复风险。

## 7. 技术影响

- **迁移**（`backend/db/migrate/`，append-only，可 down）：
  - `add_parent_and_split_to_orders`（parent_id/split_from_id/payment_combination_id）
  - `create_pallastrade_payment_combinations`
  - `create_pallastrade_payment_splits`
  - `add_payment_combination_to_payments` / `add_payment_combination_to_payment_sessions`
- **模型**（`pallastrade_core/app/models/pallastrade/`）：`order.rb`（关联+语义方法）、`payment_combination.rb`（新）、`payment_split.rb`（新）、`payment.rb` / `payment_session.rb`（关联声明）
- **序列化器**（`pallastrade_api/app/serializers/.../v3/`）：`order_serializer.rb`、`admin/order_serializer.rb`
- **测试**（`backend/spec/`，新增）：model specs + serializer specs
- **影响面**：仅 backend core + api；**无 storefront / platform 改动**（P1 不暴露任何新端点，仅序列化器字段）。

## 8. 测试计划

- **新增**（`backend/spec/models/pallastrade/`）：
  - `order_parent_child_spec.rb`（AC-001/002/006：parent/children/split_from/语义方法/root 防环）
  - `payment_combination_spec.rb`（AC-003/007：模型字段 + 状态机 + 非法迁移转业务错误）
  - `payment_split_spec.rb`（AC-004：唯一索引 + 关联）
- **新增**（`backend/spec/requests/api/v3/` 或 serializer spec）：`order_serializer_parent_child_spec.rb`（AC-008）
- **更新**：无（P1 不改既有行为）
- 运行：`harness check --profile quick` + 相关 rspec

## 9. 文档同步清单（知识同步门）

- [x] 本 PRD 已创建（骨架 + 完整扩充）
- [x] `docs/prd/README.md` 索引（已新增本条）
- [x] `ai/skills/pallastrade-data-model/SKILL.md`（已添加 Order 父子模型 + split_from 说明）
- [x] `ai/skills/pallastrade-payments/SKILL.md`（已添加 PaymentCombination/PaymentSplit 说明）
- [x] 场景库 `harness/scenarios/scenarios.json`（评估：P1 纯数据层无用户可见行为；父子关系场景建议在 P5 拆单/合并支付落地时随场景补充——本次暂不新增）
- [x] API 文档：P1 无新端点；序列化器新增字段已通过 request spec 验证（store/admin.yaml 的 Order 字段在 P5 接口正式化时同步）

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-26 | 0.1 | 初稿：P1 数据模型与语义方法（父子单 parent_id / PaymentCombination / PaymentSplit） | AI |
| 2026-08-26 | 0.2 | 实施完成：4 迁移 + Order 关联/语义方法 + PaymentCombination/PaymentSplit 模型 + 序列化器字段；21 spec 全绿 + 回归 5 spec 全绿 + harness quick 通过 + 迁移回滚演练通过；知识同步（data-model/payments SKILL） | AI |
