# PRD-20260916-payments-d14-refund-approval

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-16 |
| 来源 | 需求：D14 切片1 退款治理 —— 审批阈值 + 双人复核 + 幂等请求键（业务方案 §78-D14 / §71.1） |
| 分类 | payments |
| 关联 Skill | `pallastrade-payments`、`pallastrade-admin`、`pallastrade-security`、`pallastrade-data-model`、`pallastrade-api-v3`、`pallastrade-testing` |
| 关联 PRD | `PRD-20260906-payments-rev-p6-1-durable-refund-lifecycle-foundation`（durable refund 生命周期）、`PRD-20260906-payments-rev-p6-2-refund-execution-orchestration`（执行编排）、`PRD-20260913-payments-dsp-p7-8`（危险操作三件套：权限 + 确认 + 审计） |
| 需求类型 | 新功能 |

## 1. 背景与目标

- **一句话需求原文**：D14 退款策略 —— 自动阈值（≤X 自动退款）；超阈值需第二人批准；原因码必填；幂等键 + 重复请求拦截（防重复退款）。
- **背景（代码事实）**：
  - **已有**：`Refunds::Request`（唯一「发起退款」入口：durable `requested` 落库 → `Refunds::ExecuteJob` 异步执行）、`Refunds::Execute`（claim → provider I/O → 终态，`provider_idempotency_key` 唯一索引）、`Refunds::Recover` / `ManualRetry` / `MarkManualReview`（失败/歧义恢复）、`Refund#amount_is_less_than_or_equal_to_allowed_amount`（累计不超可退额）、`RefundReason` 必填校验、Admin API `POST /api/v3/admin/orders/:id/refunds`（人工创建路径）、后台 `/admin/refunds_ops`（只读运维 + retry/mark_review）。
  - **缺口（6 层搜索）**：**审批策略零命中** —— 无阈值配置、无「第二人批准」模型/服务/页面、无请求级幂等键（只有 provider 幂等键）；`Refunds::Request` 文档标注为「唯一入口」，但**不区分人工/系统来源**，因此任何走 Admin API 的运营都可直接退款（无金额上限约束）。
  - **语义边界（必须保持）**：`Refunds::Request` 仍被网关（stripe/adyen/paypal）与 `Orders::Cancel` 编排调用 —— 那些是**系统/编排来源**，不应被人工审批门拦截（订单取消不能因为「金额超阈值」而挂起）。
- **目标**：把「超阈值退款需第二人批准」变成**物理强制**：策略在**人工提交入口**（Admin API + 新的审批工作台）生效；阈值以内自动执行、以上挂起待批；批准后执行、拒绝则释放额度；全程审计 + 请求级幂等防重复。
- **成功指标**：① 阈值内退款行为与今天一致（零回归）；② 超阈值退款**不会**在无第二人批准时执行（服务层 + 页面双强制，含「不能自批」）；③ 同一 `request_key` 重复提交**只产生一笔**退款；④ 批准/拒绝/自动通过均落审计；⑤ 编排/网关来源（订单取消、provider 发起）零影响。

## 2. 用户故事 / 场景

- 作为**财务运营**，我一笔 ≤ 阈值的退款能像今天一样直接执行（不增加等待）。
- 作为**财务运营**，我提交一笔 > 阈值的退款后看到它进入「退款审批」队列（待第二人批准），而不是直接出款。
- 作为**财务主管**，我在「退款审批」页看到待批退款（金额/币种/发起人/原因/策略快照/时间），**批准**后它才执行，**拒绝**时必填原因并释放额度。
- 作为**审计/合规**，我要求：同一人不能既发起又批准；每次决策都有审计行；策略变更可追溯。
- 场景：① 策略未启用 → 行为与今天一致；② 策略启用 + 金额 ≤ 阈值 → 自动执行 + 审计 `refund_auto_approved`；③ 金额 > 阈值 → 待批 + 审计 `refund_approval_requested`；④ 第二人批准 → 执行 + 审计；⑤ 同人自批 → 被服务层拒绝；⑥ 拒绝（填原因）→ `cancel_request` 释放额度 + 审计；⑦ 同 `request_key` 重复提交 → 返回既有退款（`idempotent: true`）。

## 3. 功能需求（FR）

- **FR-001　退款策略（店铺级配置，唯一口径）** —— 策略存 `Store#private_metadata['refund_policy']`，读入口 `PallasTrade::Refunds::Policy.for(store)`：
  - 字段：`enabled`（默认 **false** = 不启用审批，行为与今天一致）、`auto_approve_limit`（金额上界，≤ 自动；严格大于才需审批）、`currency`（策略币种；空/缺失 = 适用于全部币种）。
  - 归一化：非法值（负数/非数值/未知键）→ **不启用** + `reason`（不猜、不静默放行）；`enabled: true` 但 `auto_approve_limit` 缺失 → 视作 0（**全部**需审批，保守方向）。
  - 只读、零副作用：读策略绝不写库。
- **FR-002　人工提交入口 `Refunds::Submit`（策略门的唯一位置）** —— 入参：`payment`、`amount`、`reason`、`refunder_id`、`request_key:`（可选）、`reimbursement`/`commerce_transaction`/`target_order`/`payment_split`（透传）。
  - 幂等：`request_key` 已存在 → 返回既有 `refund`（`idempotent: true`），**不建第二笔**；不存在 → 写入 `refund.request_key`（唯一索引兜底）。
  - 策略判定：`≤ limit` → `Refunds::Request.call(..., enqueue: true)` + 审计 `refund_auto_approved`；`> limit` → `Refunds::Request.call(..., enqueue: false)` + 建 `RefundApproval(pending)` + 审计 `refund_approval_requested`。
  - 策略未启用 → 等价于 `Refunds::Request.call(..., enqueue: true)`（今天的行为），不建审批行。
  - **零资金副作用**：本服务不调 provider、不写金额；执行仍只由 `Refunds::ExecuteJob` 承担（REV-INV-03）。
- **FR-003　双人复核（第二人批准）** ——
  - `Refunds::Approvals::Approve.call(approval:, approver_id:, note: nil)`：`approver_id` 必填、必须 ≠ `requester_id`（否则 failure `approver_must_differ`）；仅 `pending` 可批（已批/已拒 → 幂等返回现状）；批准成功后入队 `Refunds::ExecuteJob` + 审计 `refund_approval_approved`。
  - `Refunds::Approvals::Reject.call(approval:, approver_id:, note:)`：同样不允许自拒；`note` 必填；`pending` → `rejected` + `refund.cancel_request!`（释放可退额度）+ 审计 `refund_approval_rejected`。
  - 审计失败（provider/执行失败）不由本服务处理，沿用既有 `Refunds::Recover` 链路。
- **FR-004　请求级幂等（防重复退款）** —— `pallastrade_refunds.request_key`（string，可空）+ **唯一索引**（partial，`WHERE request_key IS NOT NULL`）；`Refunds::Request` 透传 `request_key:`；重复键 → 幂等返回既有行（`find_or_initialize` + `RecordNotUnique` 兜底重读）。
- **FR-005　后台审批工作台 `/admin/refund_approvals`** ——
  - index：**待审批**列表（金额/币种/发起人/原因/策略快照/发起时间/关联订单）+ 状态筛选（pending/approved/rejected）+ 分页 + **策略卡**（`enabled` / `auto_approve_limit` / `currency` 编辑，`PATCH /admin/refund_approvals/policy`）。
  - 动作：`POST /admin/refund_approvals/:id/approve`、`POST /admin/refund_approvals/:id/reject`（拒绝原因必填）；**发起人本人行不提供动作**（页面隐藏 + 服务层强制）。
  - 权限：`can :manage, PallasTrade::RefundApproval`（`configuration_management`）；批准/拒绝额外 `can?(:update, PallasTrade::Refund)`；策略保存需 `can?(:update, PallasTrade::Store)`。
  - 导航：Orders → 退款审批（position **58**）+ 导航一致性 spec 同步。
- **FR-006　Admin API 契约** —— `POST /api/v3/admin/orders/:id/refunds` 改走 `Refunds::Submit`（策略门生效）；支持可选 `request_key`（重复提交 → 返回既有退款）；`Admin::RefundSerializer` 增 `approval_status`（`pending`/`approved`/`rejected`，无审批 → null）+ 生成物（typelizer SDK 类型 + OpenAPI schemas + platform 副本）。
- **FR-007　审计与零资金副作用** —— 五类审计：`refund_auto_approved` / `refund_approval_requested` / `refund_approval_approved` / `refund_approval_rejected` / `refund_policy_updated`；spec 断言：提交/审批/拒绝路径**只**产生 durable refund 行（不产生第二笔、不触发 provider I/O、不改 Payment/Journal/订单金额）。

## 4. 非功能需求（NFR）

- **安全**：审批动作 = 敏感动作（权限 + 不能自批 + 审计）；策略卡保存需 store 权限；页面不显示他人草稿数据（仅退款事实）。
- **性能**：审批列表按 `(store_id, status)` 索引查询；策略读取为内存解析（无额外查询，store 已在内存）。
- **兼容**：`Refunds::Request` 签名**向后兼容**（新增可选 `request_key:`）；编排/网关来源行为**零变化**；Admin API 响应**只增字段**（`approval_status`），既有字段不变。
- **范围纪律（本切片不做）**：§71.2 争议期限 T-3/T-1 分档提醒与超期处理（切片2）、§71.3 拒付率看板（切片3）；审批人角色矩阵（本切片只要求「第二人且非发起人」）；审批超时自动过期。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001** ← FR-001：策略读取/归一化正确（未配置=不启用；非法值=不启用 + reason；`enabled` 且缺阈值=全量需审批；币种不匹配=不启用）；读取零写。
- **AC-002** ← FR-002：策略启用且金额 ≤ 阈值 → 退款直接入队执行（`state: requested` + 审计 `refund_auto_approved`）；**不**建审批行。
- **AC-003** ← FR-002：金额 > 阈值 → 退款落库但**不入队**（无 ExecuteJob）+ 建 `RefundApproval(pending)` + 审计；策略未启用 → 行为与今天一致（入队、无审批行）。
- **AC-004** ← FR-003：批准（第二人）→ approval `approved` + 退款入队执行；**同人自批被拒**（`approver_must_differ`）；重复批准幂等；拒绝（必填原因）→ approval `rejected` + `cancel_request`（额度释放）。
- **AC-005** ← FR-004：同 `request_key` 二次提交 → 返回既有退款且**只有一笔** refund 行/一条审批行（含并发 `RecordNotUnique` 兜底）。
- **AC-006** ← FR-005：后台列表/筛选/策略卡/动作接线正确（含「本人行无动作」与权限拒绝）；导航子项与一致性 spec 同步。
- **AC-007** ← FR-006：Admin API 走策略门（超阈值 → 201 + `approval_status: pending` 且无执行）；`approval_status` 契约字段存在；`generated:check` 无漂移。
- **AC-008** ← FR-007：全链路零资金副作用（Payment/Journal/Order 金额与行数不变；无第二笔退款）；编排/网关路径回归（`orders cancel` + refunds 既有 spec）全绿。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | `refund_policy` / `approval` | 无命中 | ❌ 未满足 |
| Core | `pallastrade_core/app/` | `refund` / `approval` / `threshold` | `Refunds::{Request,Execute,Recover,ManualRetry,MarkManualReview}`、`Refund` 模型（状态机 + 累计额度校验）、`Orders::Cancel`（系统退款编排） | ⚠️ 部分（生命周期与幂等底座已有；**审批策略缺**） |
| API | `pallastrade_api/app/` | `refunds` | `api/v3/admin/orders/refunds_controller.rb`（人工创建入口：直接 `Refunds::ExecuteJob.perform_later`）、`refund_serializer.rb` / `admin/refund_serializer.rb` | ⚠️ 部分（需接入策略门 + 增 `approval_status`） |
| Admin | `pallastrade_admin/app/` | `refund` | `refunds_controller`、`refunds_ops_controller`（只读 + retry/mark_review）、`refund_reasons_controller`、tables 列 | ⚠️ 部分（需新增审批工作台 + 策略卡） |
| Storefront | `storefront/src/` | — | 不涉及前台 | ✅ 无需变更 |
| Platform | `platform/packages/` | `refund` | `sdk/src/types/generated/Refund.ts`（typelizer 生成物） | ⚠️ 部分（生成物随契约再生成，无手写改动） |

**结论**：承载点 = **Core**（1 表 `pallastrade_refund_approvals` + `refunds.request_key` 列 + 策略读取 + 3 服务 + `Request` 透传）+ **Admin**（审批工作台 + 策略卡 + 权限/导航/i18n）+ **API**（refunds 控制器接入 + serializer 契约字段）；Storefront/平台手写代码零改动（仅生成物）。
**不复用/不改内核的决策**：策略门**不放进** `Refunds::Request`（编排与网关退款必须保持无人值守）；也不新建第二个退款入口 —— `Submit` 只是「策略门 + 幂等键」的组合，最终仍调用 `Request`。

## 7. 技术影响

- **Core**：迁移（新表 `pallastrade_refund_approvals` + `pallastrade_refunds.request_key` + 唯一索引）；模型 `RefundApproval`（状态/校验/作用域）+ `Refund` 关联与 `request_key` 处理；`Refunds::Policy`（策略值对象）、`Refunds::Submit`、`Refunds::Approvals::{Approve,Reject}`；`Refunds::Request` 增可选 `request_key:`。
- **Admin**：`RefundApprovalsController`（index/policy/approve/reject）+ 视图 + 路由 + 导航（position 58）+ 权限 + i18n（en + zh-CN）。
- **API**：`admin/orders/refunds_controller#create` 改调 `Refunds::Submit`；`Admin::RefundSerializer` 增 `approval_status`；生成物（typelizer + OpenAPI + platform 副本）。
- **数据库**：只新增表/列/索引，不回填、不改既有列。
- **测试**：模型（状态/唯一/作用域）、策略（归一化矩阵）、提交（自动/待批/幂等/审计/零副作用）、决策（批准执行/拒绝取消/自批拒绝/终态幂等）、后台（筛选/策略保存/动作/权限）、API（策略门 + 契约字段）、回归（`orders cancel` + refunds 既有 spec + 导航一致性）。

## 8. 测试计划

| 层 | 文件 | 覆盖 |
|---|---|---|
| 模型 | `backend/spec/models/pallastrade/d14_refund_approval_spec.rb` | AC-001/005（唯一/终态） |
| 服务 | `backend/spec/services/pallastrade/refunds/d14_policy_spec.rb` | AC-001 |
| 服务 | `backend/spec/services/pallastrade/refunds/d14_submit_spec.rb` | AC-002/003/005/008 |
| 服务 | `backend/spec/services/pallastrade/refunds/d14_approval_decision_spec.rb` | AC-004/008 |
| 请求 | `backend/spec/requests/pallastrade/admin/d14_refund_approvals_spec.rb` | AC-006 |
| 请求 | `backend/spec/requests/api/v3/admin/orders/refunds_approval_spec.rb` | AC-007 |
| 回归 | `orders cancel` + `refunds` 既有 spec + `navigation_consistency_spec.rb` | AC-008 |

## 9. 收口清单

- [x] 本 PRD（approved → done）
- [x] REQ：`harness/requirements/REQ-20260916-d14-refund-approval.md`
- [x] gate + prep 清理（critical：恢复计划 `REC-f459fcb73079f4`）
- [x] 用户确认：用户 2026-09-16「继续」（承接 §78 D14 批次）
- [x] 知识同步：`pallastrade-payments` / `pallastrade-admin` Skill + runbook §10 + AGENTS §6 verifier 行 + 场景库 GS-147 + 业务方案 §71.1 回写
- [x] 契约：`harness generated:check`（typelizer + OpenAPI + platform 副本）

### 9.1 实施记录（2026-09-16）

| 项 | 内容 |
|---|---|
| 交付物 | 迁移 `20260916190000`（`pallastrade_refund_approvals` 表 + `pallastrade_refunds.request_key` 列 + partial unique index）；模型 `RefundApproval` + `Refund#approval`；服务 `Refunds::Policy` / `Refunds::Submit` / `Refunds::Approvals::{Approve,Reject}`；`Refunds::Request` 增可选 `request_key:`；后台 `RefundApprovalsController`（index/policy/approve/reject）+ 视图 + 路由 + 导航（position 58）+ 权限 + i18n（en + zh-CN）；Admin API 接策略门 + `approval_status` 契约字段 + 生成物同步 |
| 验证器 | `npx harness verify d14-refund-approval-rspec` → **64 examples, 0 failures**（模型 / 策略 / 提交 / 决策 / 后台 / API + 导航一致性 + refunds 既有回归） |
| 契约 | `bash scripts/ci/contracts.sh` → `generated:check` ✅ no drift（`admin-sdk Refund.ts` + `api-docs/admin.yaml` + `platform/docs/api-reference/admin.yaml`，仅新增 `approval_status`） |
| 决策偏差 | ① 策略门只加在人工入口（`Submit`），**不进** `Refunds::Request`（编排/网关必须无人值守）；② 策略存 `Store#private_metadata`（无新策略表）；③ `Approve` 直接入队（离散人工动作，无外层事务），若未来被编排包装需改为 commit-aware |
| 修复 | 移除 `Refund` 上重复声明的 `has_one :approval`；拒绝路径校验顺序按「原因必填优先」确定（与 spec 一致） |
| 零资金副作用 | spec 断言：提交/批准/拒绝前后 Payment / FinancialLedgerEntry / 订单金额与行数不变，且**不产生第二笔退款** |

## 10. 变更记录

| 版本 | 日期 | 变更 |
|---|---|---|
| 0.1 | 2026-09-16 | 初版（切片1：策略阈值 + 双人复核 + 幂等请求键 + 工作台 + API 契约字段） |
| 1.0 | 2026-09-16 | 实施完成：64 examples 全绿；契约再生成无漂移；PRD → done；知识同步（Skill ×2 + runbook §10 + AGENTS §6 + GS-147） |

## 10. 变更记录

| 版本 | 日期 | 变更 |
|---|---|---|
| 0.1 | 2026-09-16 | 初版（切片1：策略阈值 + 双人复核 + 幂等请求键；期限提醒与拒付率看板留切片2/3） |
