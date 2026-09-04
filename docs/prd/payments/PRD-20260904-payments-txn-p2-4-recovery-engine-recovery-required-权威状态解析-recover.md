# PRD-20260904-payments-txn-p2-4-recovery-engine-recovery-required-权威状态解析-recover

| 元数据 | 值 |
|---|---|
| 状态 | approved |
| 创建日期 | 2026-09-04 |
| 来源 | P2 源文档 §26-§31/§55（TXN-P2-4 Recovery Engine）+ §59 AC-2011..2014 + INV-01..08 |
| 分类 | payments（AI 语义微调自 other；恢复是资金/交易编排域） |
| 关联 Skill | pallastrade-payments / pallastrade-checkout / pallastrade-events-webhooks / pallastrade-data-model |
| 关联 REQ | REQ-20260904-txn-p2-4.md（实施时回填） |
| 关联 PRD | N/A（全新工作包） |
| 需求类型 | 新功能（P2 内部服务 + Job；无 API 面） |

## 1. 背景与目标

- **一句话需求原文**：继续 P2 → TXN-P2-4 Recovery Engine（recovery_required 权威状态解析 + Transactions::Recover + Recovery Job + 审计）。
- **背景**：TXN-P2-1/2/3 已交付 durable CommerceTransaction、Start/Resume、Payment Fact Resolver。P2 核心不变量：PSP authoritative success 是不可逆资金事实（INV-02）；PSP success + local incomplete = recovery_required（INV-03）；Recovery 不得默认创建新 Payment（INV-04）；卡拒绝 ≠ 交易失败（INV-05）；order finalization 必须幂等（INV-08）。Recovery 是 P2 第一等能力（§26）：**不能 rescue→blindly retry Carts::Complete，必须先确认资金事实**（§26），再由 PaymentFactResolver 判定分支（§27）：UNPAID→payment_pending；PAID+Order incomplete→retry finalization；PAID+Order complete→repair completed；AMBIGUOUS→manual_review。重复 recover 幂等（§29：lock + state guard + attempt count + last_error + audit）。首版触发器（§30）：immediate failure mark → recovery_required → Recovery Job + Manual Recover（stuck sweeper 延后）。
- **目标**：
  1. CommerceTransaction 状态机补 recovery 出口事件：`retry_payment`（recovery_required→payment_pending）、`retry_finalizing`（recovery_required→finalizing）、`repair_completed`（recovery_required→completed）；保持 payment_confirmed→payment_pending **禁止**（INV-02）。
  2. `Transactions::Recover#call(transaction:)`：锁内守卫（recovery_required/finalizing）→ attempt++ → PaymentFactResolver 权威判定 → 分支执行（unpaid/paid+finalize/repair/ambiguous）；最终一次授权资金结果 + 每参与者一次 order completion（§29 幂等）。
  3. `Transactions::RecoverJob`（Sidekiq）：驱动恢复；失败记录在 transaction（last_error/recovery_attempts），幂等重试。
  4. 零 API 面；无迁移（recovery 元数据/时间戳列已由 TXN-P2-1 建）；finalization 委托现有幂等原语（standard→Carts::Complete / legacy→Checkout::Complete，复用 `CombinationMemberComplete` 分流），**不**实现 Unified Finalize（TXN-P2-5）。
- **成功指标**：resolver 三分支 + 幂等/守卫 matrix spec 全绿；AC-2011..2014 语义可测；p0-payment-rspec 回归绿；新增文件 rubocop 0。

## 2. 用户故事 / 场景

- 场景 A（UNPAID 恢复）：transaction 处 recovery_required（本地曾疑已收），resolver 判定 unpaid → recover 将状态复位 payment_pending，可安全重启支付（不重复扣款——无资金入账）。
- 场景 B（PAID + 订单未完成）：PSP 成功但 finalize 崩/未完成 → recover 判定 paid → 委托幂等 finalize 各参与者 → transaction completed（INV-03/08）。
- 场景 C（PAID + 订单已完成）：组合/其他路径已把订单完成但 transaction 状态滞留 → recover 判定 paid + all completed → repair_completed（不重复完成）。
- 场景 D（AMBIGUOUS）：provider 不可达/需捕获 → recover → manual_review（不猜，AC-2014）。
- 场景 E（幂等）：recover×3 → 1 transaction / 1 授权资金结果 / 每参与者 1 次 order completion（§29，AC-2013）。
- 场景 F（卡拒绝）：只使 PaymentSession failed，transaction 停留 payment_pending（INV-05/AC-2008，本包回归保护）。
- 场景 G（守卫）：非 recovery_required 交易调用 Recover → 业务失败码，不改状态。

## 3. 功能需求（FR）与验收标准（AC）

### FR-401：状态机 recovery 出口（CommerceTransaction）
新增事件（含 bang 版本 + after_transition 时间戳/事件）：
- `retry_payment!`：recovery_required → payment_pending（UNPAID 复位，重新进入可支付态）。
- `retry_finalizing!`：recovery_required → finalizing（PAID+incomplete 开始重试 finalize）。
- `repair_completed!`：recovery_required → completed（PAID + 全部参与者已完成 → 修复状态）。
- 保持 `mark_recovery_required!`（payment_confirmed/finalizing → recovery_required，P2-1 已有）。
- **禁止** payment_confirmed → payment_pending（INV-02，既有状态机保证）。
- AC-401（FR-401）：retry_payment! 仅 recovery_required 可用（created/payment_pending 拒绝 InvalidTransitionError）。
- AC-402（FR-401）：repair_completed!/retry_finalizing! 仅 recovery_required 可用。
- AC-403（FR-401）：payment_confirmed 无法 retry_payment（INV-02 物理守卫）。

### FR-402：Transactions::Recover（权威状态解析 + 分支执行）
`call(transaction:)`：
1. 守卫：transaction 非 nil；`with_lock` 内 reload；仅 `recovery_required`/`finalizing` 可恢复（其余 → failure `commerce_transaction_not_recoverable`）。
2. attempt：`recovery_attempts += 1`（update_columns，§29 attempt count）。
3. 解析：`Transactions::PaymentFactResolver#call(transaction:, provider_query: true)`；resolver 失败/异常 → `record_recovery_failure` + failure。
4. 分支（§27）：
   - `unpaid`：仅 recovery_required → `retry_payment!` → success `{action: :retry_payment}`（finalizing+unpaid 为矛盾态 → failure）。
   - `ambiguous`：recovery_required → `manual_review!`；finalizing → `mark_recovery_required!` 后 `manual_review!`；success `{action: :manual_review}`。
   - `paid`：参与者 = transaction.transaction_orders.includes(:order)：
     - 全部 order completed → `repair_completed!` → success `{action: :repair_completed}`。
     - 存在 incomplete → 锁外 finalize 各 incomplete 参与者（复用 `Payments::CombinationMemberComplete`：standard→Carts::Complete / legacy→Checkout::Complete，幂等 INV-08）；全部成功 → 锁内 `retry_finalizing!` + `complete!`，TransactionOrder.completion_status 更新 completed；任一失败 → `record_recovery_failure` + failure `{action: :finalize_failed}`（保持 recovery_required，Job 可重试；资金不回滚，INV-04）。
- AC-411（FR-402）：UNPAID recover → 状态 payment_pending，返回 action retry_payment。
- AC-412（FR-402）：PAID + 订单未完成 → recover 完成订单并 transaction completed（返回 action finalized；每参与者 1 次 completion）。
- AC-413（FR-402）：PAID + 订单已完成 → repair_completed（不重复 finalize）。
- AC-414（FR-402）：AMBIGUOUS → manual_review。
- AC-415（FR-402/§29）：连续 recover 幂等——第 2 次开始即已完成/已复位 → 不重复 finalize/不建新支付；attempt 计数递增。
- AC-416（FR-402）：非 recovery_required/finalizing 状态 → failure，不改状态。
- AC-417（FR-402）：finalize 失败 → recovery_required 保留 + last_error/recovery_attempts 记录（failure finalize_failed）。

### FR-403：Transactions::RecoverJob（Sidekiq）
`perform(transaction_prefixed_id)` → load（find_by_prefix_id!）→ `Recover.call`；BaseJob 重试策略；unexpected 异常上抛（幂等 recover 可重试）。
- AC-421（FR-403）：Job 对 recovery_required 交易执行 recover（bogus 上下文 perform 后状态按分支推进）。
- AC-422（FR-403）：RecordNotFound discard（BaseJob 语义）。

### FR-404：范围边界与不变量
- 本包**不**：实现 Unified Finalize（TXN-P2-5）；不改 completion 入口（P2-5 接线）；不做 stuck sweeper（§30 后续）；无迁移、无 API/routes/serializer/SDK；不引入 PaymentAttempt/CheckoutSession/Router（AC-2020）。
- INV-04/06/07 保护：Recover 从不 create payment/session；从不改 quote/价格；decline 语义不变（AC-2008 回归）。
- 审计：生命周期事件（commerce_transaction.*）已由状态机发布；recovery 尝试/失败写入 recovery_attempts/last_error_*。

## 4. 跨层搜索记录（Step 0，6 层独立搜索）

| 层 | 搜索路径 | 关键词命中结论 |
|---|---|---|
| App | `backend/app/` | 无（仅 devise recoverable 无关） |
| Core | `pallastrade_core/app/` | CommerceTransaction 已有 recovery_required/manual_review 状态 + mark_recovery_required!/manual_review! + record_recovery_failure + recovery_attempts/last_error_*（TXN-P2-1）；PaymentFactResolver（TXN-P2-3）；CombinationMemberComplete（RISK-01 分流原语）可复用为 finalize 委托；PaymentSessions::Start 有 Payment Start Policy（payment_confirmed/finalizing/recovery_required/completed/manual_review 禁新 session）——**无 Transactions::Recover/RecoverJob** |
| API | `pallastrade_api/app/` | 无 recovery 端点（TXN-P2-4 内部） |
| Admin | `pallastrade_admin/app/` | 无 |
| Storefront | `storefront/src/` | 无（无 UI 面） |
| Platform | `platform/packages/` | 无（仅 scaffold 文案无关） |

## 5. 技术影响与设计要点

- Core model：`commerce_transaction.rb` 状态机 + 3 事件（retry_payment/retry_finalizing/repair_completed，bang + after_transition 时间戳/事件）；时间戳列与 recovery 元数据列已存在（TXN-P2-1 migration）。
- Core services：新建 `services/pallastrade/transactions/recover.rb`（ServiceModule::Base；with_lock；resolver；两段式 finalize：锁内解析 + 锁外 finalize + 锁内收口）。
- Core jobs：新建 `jobs/pallastrade/transactions/recover_job.rb`（< BaseJob）。
- Finalize 委托：复用 `Payments::CombinationMemberComplete.call(order:)`（standard→Carts::Complete / legacy→Checkout::Complete；幂等）——不复制分流逻辑；TXN-P2-5 将其收敛为 Transactions::Finalize。
- 不变量落地检查：无新 Payment/session 创建路径；resolver 只读；attempt 计数与 last_error 记录；事件审计。
- 反模式：无裸 fetch、无回调副作用（finalize 委托服务）、无跨 store（transaction 已 scope）、PaymentMethod/Gateway 不加（本包不加 contract）。

## 6. 测试计划

- 模型状态机：`spec/models/pallastrade/commerce_transaction_recovery_spec.rb`（AC-401/402/403 + 既有 mark_recovery_required 迁移路径）。
- Recover 服务：`spec/services/pallastrade/transactions/recover_spec.rb`（AC-411..417：UNPAID 复位 / PAID+finalize 完成 / PAID+repair / AMBIGUOUS→manual_review / 幂等 / 守卫 / finalize 失败保留）。
- Job：`spec/jobs/pallastrade/transactions/recover_job_spec.rb`（AC-421/422）。
- 回归：`p0-payment-rspec` 注册 verifier（PaymentSession Start Policy / Payment 幂等 / webhook 全套不变）。
- 每条 spec 头标注 `# PRD-20260904-payments-txn-p2-4 AC-xxx`。

## 7. 文档同步清单（知识同步门）

- [ ] `ai/skills/pallastrade-payments/SKILL.md` changelog（Recovery Engine）
- [ ] `ai/skills/pallastrade-checkout/SKILL.md` changelog（transactions 域，视需要）
- [ ] `docs/prd/README.md` 索引 + 本 PRD 状态
- [ ] store.yaml / SDK / api-v3：N/A（无 API 面）
- [ ] RESEARCH-20260904-txn-p2-0 审计附录（P2-4 交付记录，可选）

## 8. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-04 | 0.1 | 初稿（draft） | AI |
| 2026-09-04 | 0.2 | approved（用户"实施"）；实施完成：CommerceTransaction 状态机 3 出口事件 + Transactions::Recover（resolver 分支 + 锁外幂等 finalize 委托）+ Transactions::RecoverJob；specs 15 examples 0 failures；新增文件 rubocop 0 | AI |
