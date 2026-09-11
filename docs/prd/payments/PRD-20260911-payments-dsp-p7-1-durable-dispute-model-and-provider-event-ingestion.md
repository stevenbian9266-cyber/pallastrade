# PRD-20260911-payments-dsp-p7-1-durable-dispute-model-and-provider-event-ingestion

| 元数据 | 值 |
|---|---|
| 状态 | done（2026-09-11 实施、验证、知识同步完成；待提交） |
| 创建日期 | 2026-09-11 |
| 来源 | 用户指令「实施剩余任务」→ 承接 `PRD-20260911-payments-dsp-p7-0-*`（P7 语义与模型已冻结）→ 实施 DSP-P7-1 |
| 分类 | payments（`harness prd new` 自动判定为 other，按 AGENTS §0.3 语义微调：属 payments 域） |
| 关联 Skill | `pallastrade-payments`、`pallastrade-events-webhooks`、`pallastrade-data-model`、`pallastrade-customization` |
| 关联 REQ | `REQ-20260911-dsp-p7-1-dispute-model-and-event-ingestion.md` |
| 关联 PRD | `PRD-20260911-payments-dsp-p7-0-dispute-semantic-audit-and-data-model-freeze.md`（前置冻结；查重相似度 <0.3 视为新切片） |
| 需求类型 | 新功能（新表 + 新模型 + provider 事件入口） |

> 本切片只做 **durable 模型 + 事件入口**（P7-0 §6 的方案）；**不做** Fact 解析（P7-2）、Journal/对账（P7-3）、
> Evidence（P7-4）、Sweeper（P7-5）、Recovery（P7-6）、Admin Console（P7-7）。

---

## 1. 背景与目标

- **一句话需求原文**：「实施剩余任务」（承接 P7-0 冻结结果，从 DSP-P7-1 开始实施 P7 线）。
- **背景**：P7-0 已确认 dispute 全绿地，且现有入口会**静默丢弃** dispute 事件（未订阅 + 未映射 + `result.nil? → head :ok`），
  本地无任何 dispute 事实。P7 线的其他切片（Fact/Journal/对账/证据/告警）都依赖"事件能落库、有 durable 事实"这一前置。
- **目标**：
  1. dispute 事件**不再被丢弃**：订阅 `charge.dispute.*` → 验签 → 落 `PaymentWebhookEvent`（复用 dedupe/replay）→ 分流处理；
  2. 建立 `PallasTrade::Dispute` durable aggregate（P7-0 §5.1 提案原样落地）；
  3. **无本地锚点也不丢事件**：解析不到 Payment 时落行并标记 `attention_reason = 'unlinked_payment'`（P7-6 兜底）；
  4. 全程**零业务副作用**：不改 order/inventory/付款状态（P7-0 边界 B2/B3/B4）。
- **成功指标**：
  - dispute 四种事件（created/updated/closed/funds_withdrawn|funds_reinstated）均能落库并映射本地状态；
  - 同一 `provider_event_id` 重投 → 不重复处理、不重复建行（dedupe 复用现有机制）；
  - 同一 `(provider, provider_dispute_reference)` 多次事件 → **一行** Dispute 幂等更新；
  - 无锚点事件 → 落行 + `attention_reason`，且 job 不失败重试风暴；
  - 回归：`p0-payment-rspec` 全绿（webhook 既有链路不受影响）。

---

## 2. 用户故事 / 场景

- 作为**平台运维**，当客户发起 chargeback 时，我希望系统**自动记录** dispute 事实（金额/原因/截止日），
  以便在证据窗口内响应（当前是完全没有记录）。
- 作为**开发**，当 provider 重复投递同一事件时，我希望处理是幂等的，避免重复建行或状态错乱。
- 作为**财务**，当 dispute 事件先于本地订单关联到达时，我希望事件**不丢**，稍后能被补齐关联。
- 场景（正常 / 边界 / 异常）：
  1. `charge.dispute.created` → 建 Dispute(`opened`)；有 `payment_intent` 锚点 → 关联 payment/order/store；
  2. `charge.dispute.updated`（evidence 截止时间/状态变化）→ 幂等更新 `evidence_due_at`/`state`；
  3. `charge.dispute.closed` → `won`/`lost`（依据 payload `status`）；
  4. `charge.dispute.funds_withdrawn` / `funds_reinstated` → **本切片只记账事件**（先记时间戳）；
  5. 边界：解析不到 Payment（历史/外部账号）→ 落行 + `unlinked_payment`；
  6. 异常：payload 缺 `id` → `WebhookEventStore` 返回 `[nil,false]`（既有行为），控制器 ACK 200 不炸；
  7. 异常：事件重放（Replay）→ 与首次处理等价（幂等）。

---

## 3. 功能需求（FR）

- FR-001：`PaymentWebhookEvent` 支持 dispute 动作（`dispute_created` / `dispute_updated` / `dispute_closed` /
  `dispute_funds_withdrawn` / `dispute_funds_reinstated`），`action` 校验扩展；提供 `dispute_action?`。
- FR-002：Stripe 网关订阅上述 5 个事件（`Config[:supported_webhook_events]`）并映射为上述动作（`WEBHOOK_EVENT_ACTIONS`）。
- FR-003：`Gateway#parse_webhook_event` 对 dispute 家族**不要求 payment_session**（返回 `{action:, payment_session: nil, metadata:}`），
  支付/结算家族行为不变。
- FR-004：控制器对 dispute 事件同样走 `WebhookEventStore.record` + `HandleWebhookJob`（复用 dedupe/replay/retry）。
- FR-005：`HandleWebhookJob` 按事件族分流：dispute 动作 → `PallasTrade::Disputes::HandleProviderEvent`；
  其余 → 既有 `Payments::HandleWebhook`（行为零变化）。
- FR-006：新增 `PallasTrade::Dispute`（表 `pallastrade_disputes`，prefix `dsp_`），字段与不变量遵循 P7-0 §5.1；
  提供幂等 `upsert_from_event!`。
- FR-007：`Disputes::HandleProviderEvent` 服务：解析 payload → 解析本地锚点（`Payment#response_code == payment_intent`）
  → upsert Dispute → 映射状态/时间戳；**不触碰** order/inventory/payment 状态；无锚点 → `attention_reason`。
- FR-008：状态机（P7-0 §7）：`opened/needs_response/accepted/submitted/under_review/won/lost/expired/closed/manual_review`，
  仅允许单向收敛，非法迁移抛错（P7-2 才做 provider↔本地裁决；本切片只做 payload 直映射 + 终态保护）。

---

## 4. 非功能需求（NFR）

- **幂等**：`(provider, provider_dispute_reference)` UNIQUE（DB）+ `PaymentWebhookEvent` 的 `provider_event_id` 去重（DB）；
  服务可重放（Replay）等价。
- **可观**：`attention_reason` 可查询；`(state, evidence_due_at)` 索引留给 P7-5。
- **无副作用**：本切片**不写** order/payment/inventory/ledger（边界 B2/B3/B4/B5）；测试需显式断言"无副作用"。
- **安全**：复用既有 webhook 验签（无新凭证）；无后台写入面（Admin Console 属 P7-7）。
- **兼容**：非 Stripe provider 不会触发（订阅清单是 Stripe 专属配置）；`HandleWebhookJob` 旧路径行为不变。

---

## 5. 验收标准（AC，与测试一一映射）

| AC | 对应 | 判定条件 |
|---|---|---|
| AC-001 | FR-001 | `PaymentWebhookEvent` 接受 5 个 dispute 动作；`dispute_action?` 为 true；旧动作集合行为不变 |
| AC-002 | FR-002/003 | Stripe 配置含 5 个 dispute 事件；`parse_webhook_event` 对 dispute 返回非 nil 且 `payment_session` 为 nil；对未知事件仍返回 nil |
| AC-003 | FR-004/005 | dispute webhook 落 `PaymentWebhookEvent`（`action=dispute_created`）并入队；`HandleWebhookJob` 分流到 dispute 服务（支付动作仍走旧服务） |
| AC-004 | FR-006 | 迁移建表成功；`Dispute` 校验（provider/reference/非负 amount/state·kind·attention_reason 白名单）+ `(provider, reference)` 唯一；`dsp_` 前缀 ID |
| AC-005 | FR-006/007 | 同一 reference 的 created→updated→closed 序列只产生**一行**，状态单向收敛，`evidence_due_at` 被更新 |
| AC-006 | FR-007 | 无锚点（payment_intent 不匹配任何 Payment）→ 仍落行且 `attention_reason='unlinked_payment'`；有锚点时 `payment/order/store` 正确关联 |
| AC-007 | NFR | 处理 dispute 事件**不改变** order/inventory/payment/ledger（快照对比断言）；重放同一事件不产生第二行 |
| AC-008 | 全 | `p0-payment-rspec` 回归全绿 + 新增 spec 全绿 + `permissions/nav/generated/doc-impact` 校验通过 |

---

## 6. 跨层搜索记录（6 层，2026-09-11 实测）

| 层 | 路径 | 关键词 | 找到 | 是否满足需求 |
|---|---|---|---|---|
| App（宿主） | `backend/app`、`backend/config` | `dispute\|chargeback` | 0 命中 | 绿地；迁移需落宿主 `backend/db/migrate/`（与 promotion_redemptions 等一致） |
| Core | `pallastrade_gems/pallastrade_core/app` | 同上 + `webhook` | 0 dispute；webhook 基建齐备：`HandleWebhookJob`、`PaymentWebhookEvent`、`Payments::{WebhookEventStore,HandleWebhook,ReplayWebhookEvent}` | 复用基建 + 新增 dispute 服务/模型 |
| API | `pallastrade_gems/pallastrade_api/app` | 同上 | 0 dispute；入口 `Api::V3::Webhooks::PaymentsController`（验签→parse→store→job） | 无需改控制器（parse 结果非 nil 即自动落库）→ **零改动**（待验证） |
| Admin | `pallastrade_gems/pallastrade_admin/app` | 同上 | 0 命中 | 不涉及（P7-7） |
| Storefront | `storefront/src` | 同上 | 0 命中 | 不涉及 |
| Platform | `platform/packages` | 同上 | 0 命中 | 不涉及 |

**结论**：无需新起入口——**复用 P0 webhook inbox**；控制器可能零改动（分流在 Gateway + Job 两层），
若验证发现控制器需要改动则在本 PRD 补记。

---

## 7. 技术影响

- **新增**：`backend/db/migrate/2026xxxx_create_pallastrade_disputes.rb`、
  `pallastrade_core/app/models/pallastrade/dispute.rb`、
  `pallastrade_core/app/services/pallastrade/disputes/handle_provider_event.rb`。
- **修改**：`pallastrade_core/app/models/pallastrade/payment_webhook_event.rb`（动作白名单 + `dispute_action?`）、
  `pallastrade_core/app/jobs/pallastrade/payments/handle_webhook_job.rb`（按族分流）、
  `pallastrade_stripe/lib/pallastrade_stripe/configuration.rb`（订阅清单）、
  `pallastrade_stripe/app/models/pallastrade_stripe/gateway.rb`（映射 + parse 分流）。
- **不改**：Order/Payment/Inventory/FinancialLedger/Reconciliation 语义；Admin 导航；API 契约（无新端点）。
- **部署注意**：新增订阅事件后需**重新注册 Stripe webhook endpoint**（`PallasTradeStripe::CreateGatewayWebhooks` 用该配置下发）；
  否则线上仍收不到 dispute 事件（本切片在 PRD 中记录，dev 环境随 gateway 保存/重建触发）。

---

## 8. 测试计划

| 文件 | 类型 | 覆盖 AC |
|---|---|---|
| `spec/models/pallastrade/dispute_spec.rb`（新） | model | AC-004 / AC-005 |
| `spec/services/pallastrade/disputes/handle_provider_event_spec.rb`（新） | service | AC-005 / AC-006 / AC-007 |
| `spec/models/pallastrade/payment_webhook_event_spec.rb`（扩展，若存在）或新增 | model | AC-001 |
| `spec/models/pallastrade/stripe/gateway_spec.rb`（扩展） | gateway | AC-002 |
| `spec/jobs/pallastrade/payments/handle_webhook_job_spec.rb`（扩展） | job | AC-003 |
| `p0-payment-rspec` 验证器（注册） | 回归 | AC-008 |

---

## 9. 知识同步清单（知识同步门）

### 9.1 本切片直接更新（updated）

- [x] `ai/skills/pallastrade-payments/SKILL.md`：新增「Dispute ingestion（DSP-P7-1）」章节（Dispute 模型 + 事件入口 + 边界 + 部署需重新注册 webhook endpoint）；changelog 置顶
- [x] `ai/skills/pallastrade-events-webhooks/SKILL.md`：新增 inbound dispute 事件族表（5 动作 → 分流规则）
- [x] `ai/skills/pallastrade-data-model/SKILL.md`：新增 `## Disputes (DSP-P7-1)` 表结构说明
- [x] `harness/scenarios/scenarios.json`：GS-091（dispute 事件入口场景，JSON 校验通过）
- [x] `docs/prd/README.md` 索引 + 本 PRD 状态

### 9.2 `sync-check` 其余类目评估结论（reviewed-no-change）

| 类目 | sync-check 触发变更 | 结论 |
|---|---|---|
| Model / DB | `20260911000002_create_pallastrade_disputes.rb` | ✅ 已更新 data-model Skill；本切片无第二个模型 |
| API 端点 | 批次 6 的 promotion 控制器/routes（非本切片改动） | 已评估：本切片不动 API 契约；`harness generated:check` → no drift；`harness doc-impact --base origin/dev` → all required docs synced |
| 事件 / 订阅者 | 批次 6 的 `promotions/redemption_subscriber.rb`（非本切片） | 已评估：本切片的事件面是 **inbound provider webhook**（已更新 events-webhooks Skill 的 inbound 段），非新 Subscriber |
| UI 组件 | `storefront/src/components/checkout/__tests__/UnifiedCheckout.test.tsx`（非本切片） | 已评估，无需更新（店面不涉及 dispute） |
| 包 / SDK | `platform/packages/sdk/src/types/generated/*`（批次 6 生成物） | 已评估，本切片无 SDK 面 → 以 `generated:check` 结果为准 |
| 安全策略 | `ai/skills/pallastrade-security/SKILL.md`（非本切片） | 已评估，无需更新；本切片复用既有 webhook 验签，未引入新凭证/新权限面 |
| Skill / PRD 机制 | 各 Skill 与 PRD 文档改动 | ✅ 已按要求更新领域 Skill×3 + scenarios.json；`AGENTS.md`/`copilot-instructions.md` 与本切片无关（无 R 级规则变更） |

> 结论：全部类目已逐项评估；本切片相关资产已更新，其余为历史批次变更引起的重列，维持 no-change。

---

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-11 | 0.1 | 初稿：DSP-P7-1 范围（模型 + 事件入口 + 无锚点不丢事件 + 幂等），AC-001..008 与测试映射 | AI |
| 2026-09-11 | 1.0 | 实施完成：迁移 `20260911000002` + `PallasTrade::Dispute`（阶段序状态机）+ `Disputes::{ProviderPayload,HandleProviderEvent}` + Stripe 订阅/映射/parse 分流 + Job 分流 + DI 注册；新增/扩展 spec 40 例全绿；Skill×3 + GS-091 同步 |
| 2026-09-11 | 1.1 | 收尾：`p0-payment-rspec` + `backend-rspec` 全量 **1460 examples / 0 failures**（6 pending 为既有 monorepo-root 用例）；Rubocop 触碰文件 0 offense；`generated:check` 无漂移、`doc-impact` 全同步；§9 知识同步门结论落表 | AI |
| 2026-09-11 | 1.2 | 文档冻结：PRD 置 `done` + README 索引同步；随后复跑 `p0-payment-rspec`/`backend-rspec` 生成绑定最终文件哈希的测试证据（旧证据因 PRD 文档改动而失效，重跑后 fresh）；review/knowledge 证据经营收记录，gate `GATE-2026-09-11T11-50-10` 与 task `TASK-20260911114953-68f3cb68` 关闭；用户已显式批准 critical 收尾 | AI | AI |
