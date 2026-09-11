# REQ-20260911-dsp-p7-1-dispute-model-and-event-ingestion

| 项 | 值 |
|---|---|
| 需求 | DSP-P7-1 — Dispute durable 模型与 provider 事件入口（P7 线第二个切片，首个落代码切片） |
| 类型 | 新功能（新表 + 新模型 + webhook 事件入口） |
| 关联 PRD | `docs/prd/payments/PRD-20260911-payments-dsp-p7-1-durable-dispute-model-and-provider-event-ingestion.md`（draft → 用户确认后 approved） |
| 前置 PRD | `PRD-20260911-payments-dsp-p7-0-dispute-semantic-audit-and-data-model-freeze.md`（语义与 DB proposal 已冻结） |
| 关联任务 | TASK-20260911114953-68f3cb68 |
| Gate | GATE-2026-09-11T11-50-10（type: feature，risk: critical） |
| 分支 | dev（基线 93812dcd） |

---

## Step 0 — 跨层搜索（6 层，2026-09-11 实测）

| 层 | 搜索路径 | 关键词 | 结果 | 是否已满足需求 |
|---|---|---|---|---|
| App（宿主） | `backend/app`、`backend/config` | `dispute\|chargeback` | **0 命中** | 绿地；表迁移走宿主 `backend/db/migrate/`（repo 惯例，见 promotion_redemptions / order_promotion snapshot） |
| Core | `pallastrade_core/app` | 同上 + `webhook` | 0 dispute；webhook 基建 = `HandleWebhookJob`、`PaymentWebhookEvent`、`Payments::{WebhookEventStore,HandleWebhook,ReplayWebhookEvent,WebhookProcessingError}` | 复用基建；新增 `Dispute` 模型 + `Disputes::HandleProviderEvent` |
| API | `pallastrade_api/app` | 同上 | 0 dispute；入口 = `Api::V3::Webhooks::PaymentsController`（验签 → `parse_webhook_event` → 落库 → `HandleWebhookJob`） | 期望**零改动**（parse 返回非 nil 即自动落库）；实施后回填确认 |
| Admin | `pallastrade_admin/app` | 同上 | 0 命中 | 不涉及（P7-7 才做 Console） |
| Storefront | `storefront/src` | 同上 | 0 命中 | 不涉及 |
| Platform | `platform/packages` | 同上 | 0 命中 | 不涉及 |

**结论**：**不新建并行入口**——沿用 P0 的 webhook inbox（验签/去重/replay/retry）；P7-1 的改动面 =
Gateway（订阅 + 映射 + parse 分流）+ PaymentWebhookEvent（动作白名单）+ HandleWebhookJob（按族分流）+ 新模型/服务 + 迁移。

---

## Step 1 — Skill 咨询证据

| Skill | 读取 | 关键结论（用于本切片） |
|---|---|---|
| `pallastrade-customization` | ✅ | 决策树：能用 **Events/既有基建** 就不要新起机制；结构性新增（新模型/表）走「Generators/model 或直接 gem 文件」；本切片复用既有 webhook 基建 + 在 gem 内直接新增模型/服务，符合优先级（不引入第二套入口） |
| `pallastrade-payments` | ✅ | P0 webhook 链：控制器验签 → `parse_webhook_event` → `PaymentWebhookEvent`（`provider_event_id` 唯一）→ `HandleWebhookJob`（processing/processed/failed + Retry/Replay）；**`HandleWebhook#call` 在 `payment_session.nil?` 时直接 `success(nil)`** → dispute 事件必须分流，不能走旧服务 |
| `harness-prd` | ✅ | R8 流程：PRD（含 AC）→ 用户确认 → gate → 实施 → AC↔测试映射（`prd verify`）→ 知识同步 → evidence → finish；REQ 含跨层搜索 + Skill 表（本文件） |

---

## Step 2 — 实施范围（对齐 PRD §3/§7）

**新增**
1. `backend/db/migrate/2026xxxx_create_pallastrade_disputes.rb`（P7-0 §5.1 列/索引/约束）
2. `pallastrade_core/app/models/pallastrade/dispute.rb`（`dsp_` 前缀、状态机、`upsert_from_event!` 幂等）
3. `pallastrade_core/app/services/pallastrade/disputes/handle_provider_event.rb`（解析 payload → 锚点解析 → upsert；无锚点落行 + `attention_reason`）

**修改**
4. `pallastrade_core/app/models/pallastrade/payment_webhook_event.rb`（dispute 动作白名单 + `dispute_action?`）
5. `pallastrade_core/app/jobs/pallastrade/payments/handle_webhook_job.rb`（dispute 动作 → dispute 服务；其余不变）
6. `pallastrade_stripe/lib/pallastrade_stripe/configuration.rb`（+5 个 dispute 事件）
7. `pallastrade_stripe/app/models/pallastrade_stripe/gateway.rb`（映射 + parse 分流：dispute 不要求 payment_session）

**不改**：Order/Payment/Inventory/FinancialLedger/Reconciliation；Admin 导航；API 契约（无新端点）。

---

## Step 3 — 验证方案（AC → 命令/测试）

| AC | 验证 |
|---|---|
| AC-001 | `spec/models/pallastrade/payment_webhook_event_spec.rb`（扩展） |
| AC-002 | `spec/models/pallastrade/stripe/gateway_spec.rb`（扩展：dispute 事件非 nil、未知事件仍 nil） |
| AC-003 | `spec/jobs/pallastrade/payments/handle_webhook_job_spec.rb`（扩展：分流断言） |
| AC-004/005 | `spec/models/pallastrade/dispute_spec.rb`（新） |
| AC-006/007 | `spec/services/pallastrade/disputes/handle_provider_event_spec.rb`（新；含无锚点 + 无副作用 + 重放幂等） |
| AC-008 | 注册验证器 `p0-payment-rspec`（+ 新增 spec 文件）+ `harness check --profile quick` / `generated:check` / `doc-impact` |

**风险与恢复（critical）**：需 `harness recovery create` 恢复计划 + 用户显式批准（R7）；
恢复要点 = 迁移可回滚（`drop_table :pallastrade_disputes`）+ 订阅清单回退（移除 dispute 事件）+ 代码 revert。
