# REQ-20260826-order-lifecycle-p1

> 关联 PRD：`docs/prd/payments/PRD-20260826-payments-实施-p1-数据模型与语义方法-父子单-parent_id-paymentcombination-paymentspli.md`
> 上游方案：`docs/research/RESEARCH-20260826-order-lifecycle-upgrade-plan.md`（§P1）

---

## Step 0：跨层搜索（6 层 + gem 细分）

| 层 | 搜索路径 | 搜索关键词 | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models | `backend/app/models/` | parent_id / combination / split | 无（仅 user/admin_user） | ⛔ 需新建（core） |
| App — controllers | `backend/app/controllers/` | parent / split / combination | 无（仅 ai_controller） | ⛔ 需新建 |
| Core — models | `pallastrade_core/app/models/` | parent_id / split_from / combination / children | `order.rb` 无相关实现 | ⛔ 需新建 |
| Core — services | `pallastrade_core/app/services/` | split / combination | 无（上次实现已回滚删除） | ⛔ 需新建（P2 起） |
| API — controllers | `pallastrade_api/app/controllers/` | payment_combination / children_ids | `parent_id` 仅 categories（分类用） | ⛔ 需新建 |
| API — serializers | `pallastrade_api/app/serializers/` | parent_id / is_parent / children | `order_serializer.rb` 无父子字段 | ⛔ 需新建（P1 加字段） |
| Admin — controllers | `pallastrade_admin/app/controllers/` | combination / split / parent | 无 | ⛔ 需新建 |
| Admin — views | `pallastrade_admin/app/views/` | split / parent tree | 无 | ⛔ P1 不涉及 |
| Storefront | `storefront/src/` | paymentCombination / childrenIds / isParent | 无 | ⛔ P1 不涉及（P5 起） |
| Platform | `platform/packages/` | paymentCombination / paymentSplits | 无 | ⛔ P1 不涉及 |

### 搜索结论

全仓库无任何订单父子/支付组合/支付分摊实现（上次失败实现已随 2026-08-23/25 回滚删除，schema 已完全还原）。P1 全部为**新建**，无重复风险。`parent_id` 仅存在于 `pallastrade_taxons`（分类 nested set，与订单无关）。

---

## Step 1：Skill 文件咨询

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树：新增内部模型（无 API 面）用 `pallastrade:model`；给既有模型加关联/方法用 decorator；本任务属"给 `Order` 加关联 + 新增内部模型"，走 core 直接建模（PallasTrade 团队产品，直接改 gem 文件）。 |
| `ai/skills/pallastrade-data-model/SKILL.md` | ✅ 已读 | `Order` 是"购物车+已完成交易"同一记录（state 区分）；`Payment` 有独立状态机（checkout→processing→pending→completed + failed/void/invalid）；`PaymentSession` 与 `Payment` 的 1:1 契约。P1 保持这些语义。 |
| `ai/skills/pallastrade-resource/SKILL.md` | ✅ 已读 | 模型须 `PallasTrade.base_class` + `has_prefix_id` + `SingleStoreResource`（store 级）+ 关联 `class_name`/`dependent` 明确；factory 用 `backend/spec/factories/`。 |

**按需 Skill：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-testing` | ✅ | ✅ 已读 | 测试用 RSpec + Factory Bot（非 fixtures）；`pallastrade_dev_tools` 提供核心 factories（`create(:order)` 等）；测试头部标注 `# PRD-xxx AC-x`。 |
| `pallastrade-payments` | ✅ | ✅ 已读 | 支付模型规范（前缀 `py_`）；`Payment` 硬绑定 order；合并支付需解耦（本 P1 只建模型不接流程）。 |
| `pallastrade-decorators` | ⬜ | ⬜ | 本 P1 直接在 core 模型上改（PallasTrade 团队产品，非 Host App 装饰），不涉及。 |
| `pallastrade-api-v3` | ⬜ | ⬜ | P1 无新端点（仅序列化器字段），P5 起涉及。 |

---

## 需求标题

订单生命周期升级 P1：父子单数据模型与语义方法（`orders.parent_id` / `split_from_id` / `payment_combination_id` + `PaymentCombination` / `PaymentSplit` 新表 + Order 语义方法 + 序列化器父子字段）。

## 任务类型

新功能（数据层地基，纯增量，零行为变化）

## 需求描述

为后续"父子单结构 / 自动拆单 / 手动拆单 / 合并支付"建立数据模型。P1 只建表、建模型、加关联与语义方法、暴露序列化字段，**不接入任何业务流程**。未拆单订单（`parent_id = NULL`）完全不受影响。

## 影响范围（harness affected）

仅 `backend/pallastrade_gems/pallastrade_core`（order/payment/payment_session 模型 + 新模型）+ `pallastrade_api`（order 序列化器字段）+ `backend/db/migrate/`（4 个迁移）。无 storefront / platform 改动。

## 技术方案（初步）

1. 迁移（全部可 down）：
   - `add_parent_and_split_to_orders`：`parent_id` / `split_from_id` / `payment_combination_id`（均可空 + index）
   - `create_pallastrade_payment_combinations`：store/customer/currency/amount/status/expires_at/completed_at/metadata
   - `create_pallastrade_payment_splits`：combination/order/payment 关联 + authorized/captured/refunded_amount + 唯一索引 `[combination_id, order_id]`
   - `add_payment_combination_to_payments` / `add_payment_combination_to_payment_sessions`（可空 + index）
2. `Order` 关联 + 语义方法（§PRD FR-007）
3. `PaymentCombination`（`pcom_` 前缀，状态机非法迁移 rescue 转业务错误）+ `PaymentSplit`（`psplit_`）模型
4. Store/Admin `OrderSerializer` 增加 `parent_id` / `children_ids` / `is_parent` / `is_child` / `is_single`

## 风险点

| 风险 | 缓解 |
|---|---|
| 迁移与现有数据冲突 | 全部可空列 + 新表，`down` 安全；执行前跑 `scripts/ops/rollback_prepare` |
| 状态机裸异常（上次 PaymentGroup 教训） | 模型层 `rescue` 非法迁移 → 业务错误（`code + message`），有 spec 覆盖 |
| 序列化字段影响前端 | P1 仅新增字段（缺省 `nil`/空数组），前端未消费不感知 |
| 本地环境不可用 | Docker 已就绪（`pallastrade-web-1` + `postgres-1` healthy），可在容器内执行迁移与 rspec |
