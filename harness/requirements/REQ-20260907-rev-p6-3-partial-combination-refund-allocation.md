# REQ-20260907-rev-p6-3 — Partial/Combination Refund Allocation

> 关联 PRD：`docs/prd/payments/PRD-20260907-payments-rev-p6-3-partial-combination-refund-allocation-组合退款-ownershi.md`（approved）
> 源规格：`豆包梳理业务需求/P6 — Refund, Cancellation & Dispute Orchestration.md`（REV-P6 §58/§26-29）
> Task：`TASK-20260907042613-b8fb4910`；Gate：`GATE-2026-09-07T04-26-25`（feature，risk=critical）
> 分支：dev @ 3faa588（REV-P6-1/2 done 已合入）

---

## Step 0：跨层搜索（六层，gate 强制）

| 层 | 路径 | 关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | refund / split | 无宿主 override | 否——改框架层 |
| Core | `pallastrade_gems/pallastrade_core/app/` | Refund/PaymentSplit/DefaultRefundAmount/ReimbursementTaxCalculator | `models/.../refund.rb`（update_order 组合分支）、`payment_split.rb`、`calculator/returns/default_refund_amount.rb`、`reimbursement_tax_calculator.rb` | 部分——冻结接入/上限校验需补；分摊 calculator 审计冻结（REUSE） |
| API | `pallastrade_gems/pallastrade_api/app/` | refunds | `admin/orders/refunds_controller.rb`（async，REV-P6-2）、serializer | 部分——组合参数/字段 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | refunds | legacy | 本包不动 |
| Storefront | `storefront/src/` | refund | 无 | 否 |
| Platform | `platform/packages/` | refund | admin-sdk 类型 | admin.yaml 更新后同步 |

### 搜索结论

REV-P6-1 已交付 ownership 列/capacity/写点；REV-P6-2 已交付 Request/ExecuteJob。本包增量：Admin/Request 组合创建冻结 `payment_split_id/target_order_id`、`update_order` 优先命中冻结 split、冻结 split 上限并入门禁、分摊 authority 4 项审计冻结（REUSE）、组合并发回归。无新 Calculator、无 migration。

## Step 1：Skill 文件咨询

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `pallastrade-customization` | ✅ 已读（REV-P6-1/2 会话） | 行为用服务/事件；自持 gem 内改 |
| `pallastrade-payments` | ✅ 已读（含 REV-P6-1/2 章节） | update_order/组合 split 语义；REV-P6-3 将追加 |
| `pallastrade-pricing` | 待实施时读 | 税/shipping/promo 分摊（REV-P6-3 冻结写入） |
| `harness-prd` | ✅ 已读 | PRD 流程 |

---

## 需求标题

REV-P6-3：组合退款创建即冻结 ownership（payment_split/target_order），`update_order` 优先命中冻结 split；4 项分摊 authority 审计冻结（REUSE）。

## 任务类型

优化迭代（feature gate，risk=critical）

## 需求描述

1. Admin `refunds#create` 支持可选 `payment_split_id`/`target_order_id`（prefixed 解析）→ 创建时冻结到 Refund（REV-P6-1 列）；不可证明不猜。
2. `Refund#update_order` 组合分支优先使用冻结 split/order；legacy 缺冻结才走 reimbursement 链 fallback（行为不变）。
3. 冻结 split 时 amount ≤ `split.captured−refunded`（并入 capacity 门禁）；超限拒绝且不 enqueue。
4. 分摊 authority 审计冻结（只读结论 + REUSE）：REFUND_AMOUNT_AUTHORITY（DefaultRefundAmount）/ REFUND_TAX_ALLOCATION_POLICY（ReimbursementTaxCalculator）/ REFUND_SHIPPING/PROMOTION_ALLOCATION_POLICY（订单级 non-tax 按占比）；无新 Calculator。
5. 组合并发/多笔 partial/退满拒绝回归测试（AC-6008/6010/6011/6012）；serializer 暴露冻结字段。

## 影响范围

- Core：`refund.rb`、`payment.rb`（读侧）、`services/refunds/request.rb`（Admin 接线）、legacy 分摊代码（仅审计）。
- API：`admin/orders/refunds_controller.rb`、`admin/refund_serializer.rb`、admin.yaml ×2。
- 测试：组合 allocation/并发 spec；serializer spec。
- 文档：payments skill（REV-P6-3）、pricing skill（分摊冻结）、scenarios GS-061。

## 技术方案（初步）

- Controller：解析可选 payment_split_id/target_order_id（find_by_param 于 parent order/combination 作用域）→ 传给 `Refunds::Request.call(payment_split:, target_order:)`。
- `Refund`：update_order 组合分支改为 `split = self.payment_split || fallback`；新增组合上限校验 helper（在 create 校验：冻结 split 时 amount ≤ split.credit_allowed 且 ≤ payment 全局）。
- 只读审计已产出结论（见 PRD §1.2/§3.2），写 skill。

## 风险点

- 新增可选参数向后兼容；update_order 仅对新冻结退款生效（legacy fallback 不变）。
- 组合上限取严格者；无资金语义回退。
- 回滚：git revert；无 migration/数据迁移。

## 决策节点（用户已确认 2026-09-07「实施」）

1. Admin 可选参数 + 冻结；2. 冻结优先投影（legacy fallback）；3. 分摊 authority 冻结 REUSE（无新 Calculator）。

---

## 阶段③：实施后验证（不可跳过）

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| Core | `refund.rb`/`payment.rb`/`request.rb` | 组合 allocation/并发 spec | | ⬜ |
| API | controller/serializer | request/serializer spec | | ⬜ |
| 全量 | — | `backend-rspec` verifier + P0-P5 + doc-impact | | ⬜ |

### 验证结论

（实施后回填）
