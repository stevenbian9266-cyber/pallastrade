# PRD-20260828-other-p7-逆向链路售后父子单化-flag-灰度

| 元数据 | 值 |
|---|---|
| 状态 | draft |
| 创建日期 | 2026-08-28 |
| 来源 | 需求：P7 逆向链路售后父子单化（flag 灰度） |
| 分类 | other（自动判定） |

> ⚠️ AI：请按 docs/prd/_TEMPLATE.md 完整扩充本文档（背景/FR/AC/跨层搜索/测试计划/文档同步清单），再进入用户确认。

---

# PRD-20260828-checkout-p7-逆向链路售后父子单化-flag-灰度

| 元数据 | 值 |
|---|---|
| 状态 | reviewing |
| 创建日期 | 2026-08-28 |
| 来源 | 需求：P7 逆向链路售后父子单化（flag 灰度） |
| 分类 | checkout（自动判定 other，AI 微调：订单生命周期延续，归 checkout） |
| 关联 Skill | pallastrade-checkout / pallastrade-payments / pallastrade-events-webhooks / pallastrade-admin |
| 关联 REQ | 实施时回填 |
| 关联 PRD | N/A（全新需求，`prd new` 新建，分类 other→checkout 微调） |
| 需求类型 | 新功能 |

> 🔁 **查重回写**：`prd new` 未命中相似 PRD（售后链路为 P1-P6 未覆盖的独立阶段）。

## 1. 背景与目标

- **一句话需求原文**：需求：P7 逆向链路售后父子单化（flag 灰度）
- **背景**：P1-P6 已完成父子单结构、拆单引擎、合并支付、自动拆单、手动拆单 + 父子树。当前**逆向链路（退货/退款）仍假设单订单**：`CustomerReturn#order` 取第一条 return_item、`OriginalPayment.reimburse` 用 `order.payments.completed`（**拆单/组合支付后子订单无本地 payment → 无法退款**）、`Refund#update_order` 用 `payment.order`（组合支付 payment.order 为 nil → 报错）。父订单无批量售后入口。
- **目标**：子订单可通过现有售后链（RA→CR→Reimb→Refund）退款（资金在组合/共享 payment，退款更新 `PaymentSplit.refunded_amount`）；Admin 可对父订单批量发起子订单售后。全程 flag 灰度，默认关闭。
- **成功指标**：
  - 子订单售后退款链路（建 RA → CR → Reimb → Refund）走通且退款正确入 split
  - 父订单批量售后（一次操作 → 每个子订单各建 RA）≤ 3 步
  - flag 关闭时单订单售后流程零行为变化

## 2. 用户故事 / 场景

- 作为运营，我希望对**子订单**发起退货退款（其货款在合并支付的组合 payment 上），以便拆单后仍能正常售后。
- 作为运营，我希望对**父订单**一键为全部子订单创建退货授权，以便批量处理整单退货。
- 场景列表：
  - 正常：子订单（组合支付）→ RA → CR → Reimb(OriginalPayment) → Refund（挂组合 payment，split.refunded_amount 增加）
  - 正常：父订单详情 → 批量创建 RA（每个子订单各一个）
  - 边界：退款金额 > 子订单 split 未退部分 → 校验/截断
  - 异常：无已发货 inventory_units 的子订单 → 不创建 RA（跳过）
  - flag 关闭：售后完全走现有单订单逻辑；父订单无批量入口

## 3. 功能需求（FR）

- FR-001：**子订单退款**——`OriginalPayment.reimburse` 在 `order.payments.completed` 为空（拆单/组合支付子订单）时，从 `order.payment_splits`（P2/P4 已建）定位关联 payment（含组合 payment）退款；`Refund#update_order` 在 `payment.order` 为 nil 时更新对应子订单 `PaymentSplit.refunded_amount`（P4 语义：部分退款只更新对应子订单 split）+ 触发子订单 updater。
- FR-002：`Refund#order`/`currency`/`editable?` 在 `payment.order` 为 nil（组合）时从 reimbursement→customer_return→return_items→inventory_unit.order 推导目标订单。
- FR-003：**父订单批量售后**——服务 `PallasTrade::Returns::ParentOrderReturns`：对父订单展开全部 children（+ 父订单自身有行项目时含父订单），为每个有已发货 inventory_units 的子订单创建 `ReturnAuthorization` + return_items（复用现有 RA 创建逻辑）；flag 关闭时禁止。
- FR-004：**Admin UI**——父订单详情 dropdown「Create Return Authorizations」入口（flag + `can?(:create, ReturnAuthorization)`）+ 批量创建页（展示各子订单可退 shipped units、选择 reason/stock_location、确认）。
- FR-005：**flag 灰度**——`store.preferred_returns_parent_order_handling` / `Config[:returns_parent_order_handling]`，默认关闭；关闭时父订单无入口、子订单售后走现有逻辑（子订单有本地 payment 的普通场景不受影响）。

## 4. 非功能需求（NFR）

- 性能：批量售后（≤ 10 子订单）< 3s。
- 安全：仅 Admin 角色 + `can?(:create, ReturnAuthorization)`；所有查询过 `current_store` scope。
- 兼容：flag 默认关闭；单订单售后零变化；不破坏 P4 组合支付/ P6 手动拆单。
- 可维护：复用现有 RA/CR/Reimb/Refund 底链（不新建售后框架）；`Refund#update_order` 的 split 分支仅在 `payment.order.nil?` 时生效。

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：子订单（有 PaymentSplit 关联组合 payment，无本地 payment）经 RA→CR→Reimb(OriginalPayment)→Refund 后：Refund 创建成功、挂组合 payment、`order.payment_splits.first.refunded_amount` 增加、子订单 `payment_state` 正确刷新。
- AC-002 ← FR-002：`Refund#order` 在 `payment.order` 为 nil 时返回正确的子订单；`editable?` 不炸。
- AC-003 ← FR-002：退款金额 > 子订单 split 未退部分 → 校验错误（不超额退款）。
- AC-004 ← FR-003：父订单批量创建 RA → 每个有 shipped units 的子订单各生成一个 RA（含 return_items）；无 shipped units 的子订单跳过。
- AC-005 ← FR-004：flag 开启 + 权限 → 父订单详情显示批量售后入口并可创建；flag 关闭 → 不显示。
- AC-006 ← FR-005：flag 关闭时单订单售后（RA→CR→Reimb→Refund）流程零变化（回归现有售后 spec）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | return / refund / reimbursement | 无售后业务代码（走 gem）；仅 typelizer 旧生成物（未跟踪） | ❌ 无需在此层实现 |
| Core | `pallastrade_core/app/` | CustomerReturn / Reimbursement / Refund / OriginalPayment / DefaultRefundAmount / all_inventory_units_returned | `customer_return.rb`（`order` 取 first return_item；`return_items_belong_to_same_order` 校验；`process_return!` → `order.return! if all_inventory_units_returned?`）；`reimbursement.rb`（`belongs_to :order` + `validate_return_items_belong_to_same_order`）；`refund.rb`（`delegate :order, :currency, to: :payment`；`update_order` → `payment.order.updater.update`）；`reimbursement_type/original_payment.rb`（`reimbursement.order.payments.completed`）；`reimbursement_helpers.rb#create_refunds`（`payment.can_credit?` + min(amount, credit_allowed)）；`calculator/returns/default_refund_amount.rb`（order.adjustments 分摊——**P2 已按子订单分摊 → 天然子订单级**）；`order.rb#all_inventory_units_returned?`（inventory_units 判定——子订单天然成立） | ❌ 需修复：① OriginalPayment 从 payment_splits 取 payment；② Refund#update_order 更新 split.refunded_amount；③ Refund delegate/editable? fallback |
| API | `pallastrade_api/app/` | refunds / customer_returns | `admin/orders/refunds_controller.rb`（手动退款：payment_id + refund_reason_id + amount，`@parent.payments`）；无 customer_returns/RA/reimbursements API 端点（有 serializer 无 route） | ❌ P7 聚焦售后链 Core + Admin UI，API 无新端点 |
| Admin | `pallastrade_admin/app/` | return_authorizations / customer_returns / reimbursements / refunds | `orders/return_authorizations_controller.rb`（new 用 `order.inventory_units` 建 return_items + reasons + stock_location）；customer_returns/reimbursements/refunds controller+views 全套 | ❌ 需加父订单批量售后入口 + 批量创建页 |
| Storefront | `storefront/src/` | return / refund | 无售后页面（仅 Returns Policy 静态页 + 文案） | ❌ 不涉及 |
| Platform | `platform/packages/` | admin-sdk | 无 admin-sdk 包（仅 cli/sdk/sdk-core） | ❌ 不涉及 |

**结论**：售后底链完整且可复用；父子场景需修复 3 个 Core 单订单假设（OriginalPayment / Refund#update_order / Refund delegate）+ 新增父订单批量售后服务 + Admin 入口。**不新建售后框架**，复用现有 RA/CR/Reimb/Refund 链（防重复判定）。

## 7. 技术影响

- **pallastrade_core**：
  - `reimbursement_type/original_payment.rb`：payments 空时从 `order.payment_splits` 取 payment
  - `refund.rb`：`update_order` 增加组合分支（payment.order nil → 更新 split.refunded_amount）；`delegate :order, :currency` 与 `editable?` fallback
  - 新增 `services/pallastrade/returns/parent_order_returns.rb`（父订单批量 RA）
  - `store.rb`/`configuration.rb`/`initializers/pallastrade.rb`：`returns_parent_order_handling` flag
- **pallastrade_admin**：`orders_controller.rb`（+parent_order_returns / parent_order_returns_create）、`views/.../orders/parent_order_returns.html.erb`、`_header.html.erb`（批量售后入口）、locales
- **数据库**：无新迁移（P1/P2/P4 列已就绪）
- **API 文档**：无新端点（P7 为 Core 修复 + Admin UI）
- **影响面**：`harness affected --base origin/main`（实施时运行）

## 8. 测试计划

- 新增测试文件：
  - `backend/spec/services/pallastrade/returns/parent_order_returns_spec.rb`（AC-004：批量 RA 展开/跳过）
  - `backend/spec/models/pallastrade/reimbursement_type/original_payment_child_spec.rb`（AC-001/002/003：子订单退款 + split.refunded_amount + 超限校验）
  - `backend/spec/requests/admin/parent_order_returns_spec.rb`（AC-005：入口显示 + 批量创建）
- 更新测试文件：无（回归现有售后 spec）。
- 覆盖的 AC 映射：AC-001~003 → `original_payment_child_spec`；AC-004 → `parent_order_returns_spec`（service）；AC-005 → `parent_order_returns_spec`（request）；AC-006 → 现有售后 spec 回归。

## 9. 文档同步清单（知识同步门）

- [ ] Skill 文档：`pallastrade-checkout`（子订单售后 + 父订单批量）、`pallastrade-payments`（split.refunded_amount 退款语义）、`pallastrade-events-webhooks`（售后事件父子）、`pallastrade-admin`（批量售后入口）
- [ ] 升级方案 `docs/research/RESEARCH-20260826-order-lifecycle-upgrade-plan.md` P7 段标记完成
- [ ] 本 PRD 状态更新 + `docs/prd/README.md` 索引（checkout 分类）
- [ ] API 文档：无新端点（预计 reviewed-no-change）
- [ ] 反模式库 / 任务规则 / 场景库：如涉及则更新（预计 reviewed-no-change）

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-28 | 0.1 | 初稿：P7 逆向链路售后父子单化（flag 灰度）；6 层跨层搜索完成 | AI |
