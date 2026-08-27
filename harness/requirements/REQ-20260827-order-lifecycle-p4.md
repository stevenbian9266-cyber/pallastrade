# REQ-20260827-order-lifecycle-p4 — 合并支付载体（PaymentCombination 服务层 + Webhook 幂等完成）

> 关联 PRD：`docs/prd/payments/PRD-20260827-payments-实施-p4-合并支付载体-paymentcombination-服务层-webhook-幂等完成.md`
> 关联 Task：`TASK-20260827140217-17bf9fb9`｜Gate：`GATE-2026-08-27T14-02-37`（Risk critical）
> 任务类型：新功能（能力层服务，默认关闭，P5 接线）

---

## Step 0：跨层搜索（6 层强制）

| 层 | 搜索路径 | 搜索关键词 | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App | `backend/app/` | payment_combination, PaymentSplit, 合并支付 | 无 | 否——P4 工作在 Core 服务层，App 无重复能力 |
| Core — models | `pallastrade_gems/pallastrade_core/app/models/` | PaymentCombination, PaymentSplit, PaymentSession | `payment_combination.rb`（P1 状态机+契约）、`payment_split.rb`、`payment_session.rb`（P1 加 `payment_combination_id`） | 数据层已满足（P1）；服务层需新建 |
| Core — services/jobs | `pallastrade_core/app/services/` `.../jobs/` | HandleWebhook, Carts::Complete, checkout_complete_service | `services/pallastrade/payments/handle_webhook.rb`（成功走单订单完成）、`services/pallastrade/carts/complete.rb`、`jobs/.../handle_webhook_job.rb` | Webhook 骨架存在，**需加组合分支 + Create/Complete 服务 + 补偿 Job** |
| API | `pallastrade_gems/pallastrade_api/app/` | payment_session, combination | `store/carts/payment_sessions_controller.rb`（单订单 session 端点） | 否——P4 不暴露端点（P5） |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | payment_combination | 无 | 否——P4 不动 Admin |
| Storefront | `storefront/src/` | 合并支付, combined-payment | 无 | 否——P4 不动 Storefront（P5 收银台） |
| Platform | `platform/packages/` | payment_combination | 无 | 否——P4 不动 SDK |

### 搜索结论

- 数据层（P1：PaymentCombination/PaymentSplit/可空列）与聚合派生（P3：`effective_payment_total`）已就绪。
- **需新建**：`PaymentCombinations::Create` / `PaymentCombinations::Complete` 服务、`CombinationSettleJob`、`HandleWebhook` 组合分支、Stripe 组合完成接线。
- API/Admin/Storefront/Platform 均不涉及（P5/P6 接线），无跨层重复能力。

---

## Step 1：Skill 文件咨询（新功能 — 强制执行）

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树：P4 是 Core 能力层服务（合并支付载体），沿用现有服务模式（`ServiceModule::Base`），不属装饰器/事件/依赖注入场景；"Replace how a core service computes" 走 `PallasTrade.dependencies` |
| `ai/skills/pallastrade-payments/SKILL.md`（domain） | ✅ 已读 | Payment 状态机 `checkout → processing → pending → completed`（completed=资金已动）；PaymentSession 通过 `response_code`/`external_id` 关联 Payment 且保持 1:1；"一个 session 对应多个 payment" 不受支持 → P4 组合支付必须维持 1 session + 1 payment |
| `ai/skills/pallastrade-prd/SKILL.md` | ✅ 已读 | 工作流 §3：PRD 需用户明确确认（"确认"/"认可"/"实施"）后进入实施；§4：gate 前生成 REQ，user-confirmed 由用户确认清除 |

---

## 需求标题

P4 合并支付载体：`PaymentCombinations::Create`（发起）+ `PaymentCombinations::Complete`（幂等完成、先入账后完成、部分失败补偿）+ Webhook 接线 + `CombinationSettleJob` 补偿队列。

## 任务类型

新功能（能力层服务，默认关闭）

## 需求描述

P1 已建好 `PaymentCombination`/`PaymentSplit` 数据层，P2 拆单引擎会用 split 记账（组合为空），P3 聚合派生就绪。P4 补齐**服务层闭环**：

1. **Create**：校验同 store/同用户/同币种、仅未支付订单计入、金额服务端计算（= Σ `amount_due`）；创建组合（`pending`）+ 每成员订单 `PaymentSplit` + primary 订单 `PaymentSession`（挂组合）→ `processing`。
2. **Complete**：幂等完成——组合 `succeeded`；**先入账**（1 个 `Payment` 挂组合 `order_id=nil` + splits `captured` + 各订单 `payment_state`）→ **再逐个订单完成**（`checkout_complete_service`）。
3. **一致性兜底**：某订单完成失败 → 不回滚已入账支付，订单 `balance_due` + 入 `CombinationSettleJob` 重试（资金 >= 订单状态）。
4. **Webhook 接线**：session 挂组合时支付成功走 `PaymentCombinations::Complete`（`HandleWebhook` + Stripe `CompleteOrderFromSessionJob` 双路径收敛）。
5. **幂等**：组合 succeeded / session completed / 订单已完成 → 跳过；双路径不重复入账。

## 恢复计划（Risk critical）

- **失败判据**：组合完成导致资金重复入账 / 订单状态错乱 / 既有单订单支付链路回归。
- **停止条件**：发现上述任一即停，不回滚已入账资金，人工介入核对。
- **代码恢复**：`git revert` P4 commit（移除 services/jobs/webhook 分支；无迁移零 DB 影响）。
- **数据恢复**：P4 无迁移；组合/支付/订单状态为业务数据，回滚后以 DB 备份（`scripts/ops/db_backup.sh`）为准核对。
- **验证**：`harness check --profile quick` + 相关 rspec 全绿 + 既有支付 spec 零回归；人工确认单订单支付链路未变。

## 验收映射

AC-001~003 → `payment_combinations_create_spec.rb`；AC-004~006/008 → `payment_combinations_complete_spec.rb` + `combination_settle_job_spec.rb`；AC-007 → `handle_webhook_combination_spec.rb`。
