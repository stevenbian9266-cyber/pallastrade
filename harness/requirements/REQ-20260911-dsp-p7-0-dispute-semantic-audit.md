# REQ-20260911-dsp-p7-0-dispute-semantic-audit

| 项 | 值 |
|---|---|
| 需求 | DSP-P7-0 — Dispute 语义审计与数据模型冻结（P7 线首个切片，仅审计不落代码） |
| 类型 | 文档（审计冻结） |
| 关联 PRD | `docs/prd/payments/PRD-20260911-payments-dsp-p7-0-dispute-semantic-audit-and-data-model-freeze.md`（done） |
| 关联任务 | TASK-20260911113716-42b82c76 |
| Gate | GATE-2026-09-11T11-37-33（type: audit） |
| 分支 | dev（基线 a5cb74f9） |
| 用户指令 | 「继续后续批次」→ 选定 P7 线 + 切片「DSP-P7-0 仅审计冻结（PRD/REQ + 数据模型提案）」 |

---

## Step 0 — 跨层搜索（6 层，2026-09-11 实测）

| 层 | 搜索路径 | 关键词 | 结果 | 是否已满足需求 |
|---|---|---|---|---|
| App（宿主） | `backend/`（app/gems/config/db/schema） | `dispute|chargeback` | **0 命中** | 绿地，需新建 |
| Core | `backend/pallastrade_gems/pallastrade_core/{app,lib}/` | 同上 + `representment|evidence_due` | **0 命中 dispute**；集成面已定位：`FinancialFact`、`FinancialLedgerEntry`、`FinancialFacts::{ProviderFinancialDetails,ResolvePayment,ResolveRefund,CaptureEvidencePolicy}`、`FinancialLedger::{Post,Reverse,PostPayment,PostRefund}`、`Reconciliations::{ReconcilePayment,ReconcileRefund,ReconcileTransaction}`、`Payments::{WebhookEventStore,HandleWebhook,ReplayWebhookEvent}` | 需新建（P7-1..8） |
| API | `backend/pallastrade_gems/pallastrade_api/app/` | 同上 | 0 命中 dispute；入口 = `PallasTrade::Api::V3::Webhooks::PaymentsController`（验签→parse→落库→HandleWebhookJob） | 需扩展入口（P7-1） |
| Admin | `backend/pallastrade_gems/pallastrade_admin/{app,lib}/` | 同上 | 0 命中 dispute；运维面 = `PaymentsOpsController`、`TransactionsController`（Orders 导航组子项） | P7-7 挂载点已定位 |
| Storefront | `storefront/src/` | 同上 | 0 命中 | 不涉及 |
| Platform | `platform/packages/` | 同上 | 0 命中 | 不涉及 |

**结论**：P7 **全绿地**；不新起并行体系——复用 P0 webhook inbox、P4 Fact/Journal/Reconciliation、
P6 durable + manual_review 模式。触发 `AP-SEARCH-1/2/3` 的三类误判在本轮均不适用（六层各自独立验证过 0 命中）。

---

## Step 1 — Skill 咨询证据

| Skill | 读取 | 关键结论（用于本切片） |
|---|---|---|
| `pallastrade-payments`（91KB，重点章节） | ✅ | FIN-P4-1 `FinancialFact`（transient VO，`FACT_TYPES` 无 dispute）；FIN-P4-2 不可变 Journal（`Post`/`Reverse` + `idempotency_key`，`PSP_FEE/PSP_NET_SETTLEMENT` RESERVED）；FIN-P4-3 Posting 订阅者（`payment.paid`/`refund.succeeded`）；FIN-P4-5 Stripe provider financial details（`fetch_financial_details`：`cs_/pi_` → PI → latest_charge → BT → refunds，fee/net 是 **Reconciliation Fact 不进 Journal**）；FIN-P4-6/7 只读对账（`SourceResult`/`TransactionResult` transient，零写零 mutation）；REV-P6-x durable refund 模式（requested→processing→succeeded/failed/ambiguous→manual_review） |
| `pallastrade-data-model` | ✅ | 新表必须走新迁移（不改历史迁移/不手改 schema.rb）；多店维度用 `store_id`；前缀 ID 约定（`has_prefix_id`） |
| `pallastrade-security` | ✅ | 资金类后台写动作需 capability 单源（PermissionRegistry）+ 审计；危险操作（自动 charge/refund）一律禁止 |

---

## Step 2 — 审计执行记录（对应 PRD §3 的 Q1–Q9）

| # | 审计动作 | 结论落点 |
|---|---|---|
| Q1 | 读 `Webhooks::PaymentsController#create`（第 29-35 行 `result.nil? → head :ok`） | 未保存：解析失败即丢弃，落库在其后 |
| Q2 | 读 `PallasTradeStripe::Config[:supported_webhook_events]` + `Gateway::WEBHOOK_EVENT_ACTIONS` | 双阻断：未订阅 + 未映射 |
| Q3 | 读 `create_payment.rb:36-38`（`response_code` = `pi_`）+ `gateway/payment_sessions.rb:224-271`（ch_ 现取） | 可解析但未持久化 |
| Q4 | 读 `db/schema.rb` `pallastrade_payments` 列（无 charge 列） | 无稳定本地键；提案以 `pi_` 为锚 + durable 引用列 |
| Q5/Q6 | 读 `provider_financial_details.rb`（9 值 settlement enum、无 dispute）+ `payment_sessions.rb:265-271`（仅 charge BT 的 fee/net） | 本地无 dispute BT 采集；dispute fee 需 P7-3 扩展 |
| Q7/Q8 | 六层 0 命中（无表无字段无约束）+ 源规格 §26/§6 | 模型必须支持 partial 与 1:N |
| Q9 | 六层 0 命中 + 源规格 §16 | 本地无 deadline，需 `due_at` 一等列 |
| 附加 | 读 `financial_fact.rb:24-25`、`financial_ledger_entry.rb:23-27,88-93`、`WebhookEventStore#call`、`shipments` 表结构、admin 导航 | F1–F6 附加发现（PRD §3 末） |

---

## Step 3 — 交付物

| 产物 | 路径 |
|---|---|
| PRD（审计冻结 + DB proposal + 切片计划） | `docs/prd/payments/PRD-20260911-payments-dsp-p7-0-dispute-semantic-audit-and-data-model-freeze.md` |
| REQ（本文件） | `harness/requirements/REQ-20260911-dsp-p7-0-dispute-semantic-audit.md` |
| PRD 索引 | `docs/prd/README.md` |
| 清理 | 删除 `harness prd new` 生成的错分类骨架 `docs/prd/harness/PRD-20260911-harness-p7-0-*.md`（语义微调至 payments，AGENTS §0.3） |

**明确不做（本切片）**：迁移、模型、事件入口代码、Skill 更新、契约变更。

---

## Step 4 — 验证方式（docs-only 切片）

- 本切片无代码 → 不跑测试套件；按 gate 文案（"no-test-needed only for docs"）以 **review evidence** 收口：
  审计结论逐条可回溯到"文件:行"证据，且六层搜索结果可复现（`rg 'dispute|chargeback'`）。
- 知识同步：`sync-check`（本批仅 `docs/prd/**` + `harness/requirements/**` 变更）→ 按矩阵评估后再决定 ack。
- `prd verify` 的 AC↔测试映射在 **P7-1** 建立测试时补齐（PRD §12 已记录）。
