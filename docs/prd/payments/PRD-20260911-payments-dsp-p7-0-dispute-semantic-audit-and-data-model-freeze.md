# PRD-20260911-payments-dsp-p7-0-dispute-semantic-audit-and-data-model-freeze

| 元数据 | 值 |
|---|---|
| 状态 | done（审计冻结已交付；实施从 DSP-P7-1 开始；§9 开放项 **O1–O5 已全部实测取证关闭**，仅 O2 partial 因测试环境限制标注未实测） |
| 创建日期 | 2026-09-11 |
| 来源 | 用户指令「继续后续批次」→ 选定 **P7 — Dispute & Chargeback Orchestration** → 切片 **DSP-P7-0 仅审计冻结**；源规格 `豆包梳理业务需求/P7 — Dispute & Chargeback Orchestration.md` |
| 分类 | payments（`harness prd new` 自动判定为 harness，按 AGENTS §0.3 做语义微调：本线属 payments 域，与 FIN-P4 / REV-P6 同域） |
| 关联 Skill | `pallastrade-payments`、`pallastrade-data-model`、`pallastrade-security` |
| 关联 REQ | `REQ-20260911-dsp-p7-0-dispute-semantic-audit.md` |
| 关联 PRD | N/A（查重 0 命中：既有 payments PRD 覆盖 P0–P6 / FIN-P4，无 dispute 主题） |
| 需求类型 | 文档（语义审计 + DB proposal；**本切片不写代码、不做迁移**） |

> 本 PRD 是 **P7 线的语义基线**：冻结 Refund≠Dispute 边界、给出 `PallasTrade::Dispute` aggregate 的 DB proposal、
> provider 事件入口方案、Journal/Reconciliation 集成面与 DSP-P7-1..8 切片计划。P7-1 起以此为准实施。

---

## 1. 背景与目标

- **一句话需求原文**：「继续后续批次」（用户选定 P7 线 + DSP-P7-0 审计冻结切片）。
- **背景**：P0–P6 已交付 payment execution、commercial facts、CommerceTransaction/Recovery、inventory facts、
  immutable Financial Journal + Reconciliation、canonical Commerce Core、durable Refund/Reverse Recovery。
  但**「非商户发起的资金逆转」零覆盖**：代码全仓检索 `dispute|chargeback` = **0 命中**（六层搜索见 §10），
  既没有 durable aggregate，也没有 provider 事件入口，更没有财务/对账语义。
- **目标**：在写任何迁移之前，把 P7 的语义、数据模型与集成面**一次冻结**，使 DSP-P7-1 可以直接开迁移；
  并逐条回答源规格 §19 提出的 9 个前置审计问题（结果见 §3）。
- **成功指标**：
  1. §3 的 Q1–Q9 **全部有代码级证据**（文件:行），无"待确认"；
  2. §5 的 DB proposal 可直接转成 P7-1 的迁移（列/索引/约束/状态机齐备）；
  3. §6 的事件入口与 §7 的财务/对账集成面明确到"改哪个类、加哪个常量、扩展哪个 key"；
  4. §9 的开放项（需 provider 侧实测确认）单列，不阻塞 P7-1 的模型/入口切片。

---

## 2. 边界冻结（P7 不可协商的语义）

| # | 边界 | 冻结结论 | 反面（禁止） |
|---|---|---|---|
| B1 | **Refund ≠ Dispute** | Dispute 有独立生命周期与独立 fact 类型；不复用 `REFUND_SUCCEEDED` / `refund.succeeded` | 用 refund 成功表示 chargeback lost |
| B2 | **不改 CommerceTransaction 状态机** | 原 txn 保持 `completed`；dispute 有自己的 lifecycle | `completed → disputed → chargeback` |
| B3 | **Webhook = evidence, not authority** | provider 事件只写 Dispute 域 + 财务事实 + 对账 | `charge.dispute.created → order.cancel!` |
| B4 | **Inventory 默认不变** | Chargeback ≠ Return ≠ Restock；只有真实退货/入库才动库存 | dispute 触发 `StockMovement(+)` |
| B5 | **Journal append-only** | 新增 `DISPUTE_DEBIT` / `DISPUTE_CREDIT`（或 reverse）条目，**不改**原 `CASH_CAPTURED` | 原地修改原 payment entry |
| B6 | **Reconciliation 零写、零 provider mutation** | 延续 FIN-P4-6/7 的 transient verdict 模式 | 对账自动补记/自动 charge |
| B7 | **第一版不做自动 representment** | 只做 evidence 包（snapshot）与人工确认提交 | 自动提交不完整证据 |

---

## 3. 审计发现（Q1–Q9，代码级证据）

> 方法论：六层跨层搜索（§10）+ 关键路径逐文件核对；行号取自 2026-09-11 工作树（HEAD `a5cb74f9`）。

| # | 问题（源规格 §19） | 结论 | 证据 |
|---|---|---|---|
| Q1 | 当前 Stripe webhook payload 是否已经保存 dispute events？ | **否**。验签后先 `parse_webhook_event`，返回 `nil` 时直接 `head :ok` **ACK 丢弃**；落库（`WebhookEventStore`）发生在其后 | `pallastrade_api/app/controllers/pallastrade/api/v3/webhooks/payments_controller.rb:29-35` |
| Q2 | `charge.dispute.*` 是否已被 webhook filter 接收？ | **否，双重阻断**：①订阅清单 `Config[:supported_webhook_events]` 仅 8 个 payment/checkout 事件（无 dispute）→ Stripe 不会投递；②即使投递，`WEBHOOK_EVENT_ACTIONS`（7 项映射）无 dispute → `parse_webhook_event` 返回 nil → 丢弃 | `pallastrade_stripe/lib/pallastrade_stripe/configuration.rb:3-13`；`pallastrade_stripe/app/models/pallastrade_stripe/gateway.rb:11-21,49-69` |
| Q3 | Stripe Charge ref 是否所有主路径可解析？ | **可解析，但不持久化**。`Payment#response_code` 存的是 `pi_`（创建路径显式要求）；`ch_` 由财务明细路径 `PI → latest_charge` **现取现用**，只落在 transient VO | `pallastrade_stripe/app/services/pallastrade_stripe/create_payment.rb:36-38`；`gateway/payment_sessions.rb:224-271`；`financial_facts/provider_financial_details.rb:24-30` |
| Q4 | Payment → Charge → Dispute 如何稳定关联？ | **今天无稳定本地键**。建议以 `payment_intent`（=`Payment#response_code`）为锚做 1:N 关联，并把 `ch_`/`dp_` 作为**durable 引用列**落库（P7-1） | 同上 + `db/schema.rb` `pallastrade_payments` 无 charge 列（仅 `response_code`） |
| Q5 | PSP dispute debit/credit 在 BalanceTransaction 中如何表现？ | **本地无采集**。`fetch_financial_details` 只归一 PI/Charge/BT/Refund 的 gross/fee/net；`ProviderFinancialDetails.settlement_status` 是 9 值 closed enum，**无 dispute 语义** | `gateway/payment_sessions.rb:224-287`；`provider_financial_details.rb:20-30` |
| Q6 | dispute fee 是否存在？ | **本地无采集**。BT 的 `fee` 已能取（charge 的 BT），但 dispute fee 在 Stripe 侧是**独立 BalanceTransaction**；当前快照不遍历 dispute 相关 BT | `gateway/payment_sessions.rb:265-271` |
| Q7 | partial dispute 是否支持？ | **本地零约束**（无表无字段）；Stripe 侧支持 → 模型必须允许 `amount ≤ payment.amount`，禁止假设全额 | §10 六层 0 命中；源规格 §26 |
| Q8 | multiple dispute 是否真实可达？ | **是**。同一 payment 可多次 dispute；本地无任何约束阻止 1:N → 提案按 `Payment 1:N Dispute` 建模（不假设 1:1） | 同上；源规格 §6 |
| Q9 | evidence deadline 数据在哪里？ | **本地不存在**。Stripe dispute 对象含 `evidence_details.due_by`，P7 必须落成 `due_at` 一等列 + 到期扫描告警 | 源规格 §16；本地 0 命中 |

**附加发现（同样影响切片设计）**：

- F1：`FinancialFact::FACT_TYPES` = `CASH_CAPTURED / STORE_CREDIT_APPLIED / OFFLINE_PAYMENT_RECORDED / REFUND_SUCCEEDED / ORDER_ALLOCATION / NONE`，**无 dispute 类型**（`financial_fact.rb:24-25`）。
- F2：`FinancialLedgerEntry::ENTRY_TYPES` 同名单 + `RESERVED = [PSP_FEE, PSP_NET_SETTLEMENT]`，dispute 需新增条目类型（`financial_ledger_entry.rb:23-27`）。
- F3：`FinancialLedgerEntry.fact_posting_key` 的 source 优先级是 `refund > payment > combination > split > order > txn`，**dispute 不在其中** → 同一 payment 的两个 dispute 会撞键/语义混淆，P7-2 必须扩展（`financial_ledger_entry.rb:88-93`）。
- F4：webhook 落库要求 `payment_session` 锚点（`WebhookEventStore` 记录 `payment_session_id`），而 dispute payload 只有 `ch_`/`pi_` → **不能复用现有 session 解析路径**，需 dispute 专用入口（P7-1）。
- F5：`pallastrade_shipments` 无 `tracking` 列（tracking 在 `schema.rb:2142/2188` 的 carton 层）→ evidence snapshot（P7-4）取物流凭证要走 carton/tracking 关联。
- F6：后台运维面现有 `PaymentsOpsController` / `TransactionsController`（Orders 导航组）→ P7-7 控制台可挂同一组，避免新顶级导航。

---

## 4. 功能需求（FR，供 P7-1..8 拆解）

- FR-001（P7-1）：`PallasTrade::Dispute` durable aggregate + `charge.dispute.*` 事件入口（**本 PRD 冻结其形状**）。
- FR-002（P7-2）：Dispute Fact Resolution（provider 状态 ↔ 本地状态裁决，AMBIGUOUS 不猜）。
- FR-003（P7-3）：dispute 财务事实进 Journal + 对账扩展（append-only，独立 idempotency key）。
- FR-004（P7-4）：Evidence Snapshot 生成与提交（immutable 证据包，人工确认后提交）。
- FR-005（P7-5）：`due_at` 到期扫描/告警/人工复核队列。
- FR-006（P7-6）：Dispute Recovery（webhook 与本地不一致时的安全收敛）。
- FR-007（P7-7）：Admin Dispute Console（只读优先 + 受控写动作）。
- FR-008（P7-8）：多 provider / legacy 能力边界（当前仅 Stripe SUPPORTED）。

> 本切片（P7-0）**不实现** FR-001..008，只冻结其前置语义与数据形状。

---

## 5. Dispute 数据模型提案（DB proposal，P7-1 落地）

### 5.1 `pallastrade_disputes`

| 列 | 类型 | 约束/说明 |
|---|---|---|
| `id` | bigserial | 主键；对外 `dsp_` 前缀（`has_prefix_id :dsp`） |
| `store_id` | bigint | 索引；多店隔离锚点 |
| `order_id` / `payment_id` | bigint | 索引；`payment_id` 必备（financial source owner） |
| `commerce_transaction_id` | bigint | 可空（P4 命名纪律：txn 归属优先，但不阻断事件入库） |
| `payment_combination_id` | bigint | 可空（组合支付场景） |
| `provider` | string | 非空（`stripe` …） |
| `provider_dispute_reference` | string | 非空；**UNIQUE(provider, provider_dispute_reference)** = 事件幂等键 |
| `provider_charge_reference` / `provider_payment_reference` | string | 可空（Q3/Q4 结论：需 durable 保存，供反查与 evidence） |
| `kind` | string/enum | `inquiry / warning / chargeback / retrieval`（provider 映射后的域内分类） |
| `state` | string | `opened / needs_response / accepted / submitted / under_review / won / lost / expired / closed / manual_review`（源规格 §7 落地） |
| `reason` / `network_reason_code` | string | provider 原因码与卡组织码 |
| `amount` / `currency` | decimal(12,2) / string | 允许 `amount ≤ payment.amount`（Q7 partial），禁止假设全额 |
| `fee_amount` | decimal(12,2) 可空 | dispute fee（Q6：provider 侧确认后再填，不猜） |
| `evidence_due_at` | datetime 可空 | **一等事实**（Q9）；索引用途见下 |
| `evidence_submitted_at` / `responded_at` / `resolved_at` | datetime 可空 | 生命周期时间戳 |
| `outcome` | string 可空 | `won / lost / accepted / expired` |
| `private_metadata` / `public_metadata` | jsonb | 与全站一致 |
| `created_at` / `updated_at` | datetime | |

**索引**：`(provider, provider_dispute_reference)` UNIQUE；`payment_id`；`order_id`；`(state, evidence_due_at)`（sweeper 用）。

**不变量（P7-2 执行，入库不阻断）**：
1. 同一 `provider_dispute_reference` 只建一行（webhook 重投 → 幂等更新）；
2. `Σ(active disputes.amount) ≤ payment.amount`——**违反时记 `NEEDS_ATTENTION` 并保留事实**，绝不拒收事件、绝不自动资金动作；
3. 状态机单向收敛（`won/lost/expired/accepted/closed` 为终态，终态可被 provider 更正为 `manual_review`）。

### 5.2 `pallastrade_dispute_evidence_snapshots`（P7-4）

| 列 | 说明 |
|---|---|
| `dispute_id` | 归属 |
| `payload` (jsonb) | immutable 证据包（order/txn/payment/shipment/tracking/refund history/policy refs） |
| `content_hash` | 幂等与防篡改 |
| `submitted_at` / `provider_submission_reference` | 提交回执（人工确认后写入） |

### 5.3 与既有模型的边界

- **不改** `pallastrade_payments`（如未来需要 `provider_charge_reference` 列，另开迁移并在 PRD 记录，属于 P7-1 的决策点之一）；
- **不改** `CommerceTransaction` 状态机与既有 refund 体系；
- `PallasTrade::Dispute` 不做 STI 子类（kind/state 用枚举），避免与 `kind` 语义混淆。

---

## 6. 事件入口方案（P7-1）

1. **订阅**：把 `charge.dispute.created / updated / closed / funds_reinstated / funds_withdrawn` 加入
   `PallasTradeStripe::Config[:supported_webhook_events]`（Q2 阻断点之一），并在文档/部署说明记录需要重新注册 webhook endpoint（`CreateGatewayWebhooks` 以该配置下发）。
2. **映射与分流**：`Gateway::WEBHOOK_EVENT_ACTIONS` 增加 dispute 动作（如 `'charge.dispute.created' => :dispute_created`），
   但 **`parse_webhook_event` 必须按事件族分流**：payment/checkout 族沿用现有 session 解析；dispute 族**不要求 payment_session**
   （F4），改为解析 `payment_intent`/`charge` 锚点后返回 dispute 专用 structure。
3. **落库与 replay 复用**：dispute 事件同样写 `PaymentWebhookEvent`（`payload` jsonb + `provider_event_id` 去重），
   从而复用 P0 的 dedupe / replay / 失败可见性；`action` 字段区分 dispute 动作。
4. **无锚点事件**：无法解析到本地 Payment 的 dispute（历史数据/外部账户）→ 记 `NEEDS_ATTENTION`（**不丢事件**），
   由 P7-6 Recovery 兜底。
5. **顺序与幂等**：事件处理以 `(provider, provider_dispute_reference)` 为幂等键做 upsert；
   乱序（created 后到 updated 先到）由状态机单调性 + `updated_at` 比较兜底。

---

## 7. 财务与对账集成面（P7-2/P7-3）

| 集成点 | 现状 | P7 扩展 |
|---|---|---|
| `FinancialFact::FACT_TYPES` | 无 dispute 类型（F1） | 增加 `DISPUTE_OPENED / DISPUTE_FUNDS_WITHDRAWN / DISPUTE_FUNDS_REINSTATED / DISPUTE_WON / DISPUTE_LOST`（首批上几个由 §9 的 provider 实测决定） |
| `FinancialLedgerEntry::ENTRY_TYPES` | 5 类 + 2 reserved（F2） | 激活 `DISPUTE_DEBIT / DISPUTE_CREDIT`（`PSP_FEE / PSP_NET_SETTLEMENT` 保持 RESERVED） |
| `fact_posting_key` | source 不含 dispute（F3） | 扩展为 `dispute > refund > payment > …`，保证同一 payment 多 dispute 各自独立条目 |
| `FinancialLedger::PostPayment/PostRefund` | 事件订阅式恰好一次 | 新增 dispute 编排（`PostDispute` 或等价），仍走 `Post.call` 幂等原语 |
| `Reconciliations::*` | Payment / Refund / Transaction 三层只读（FIN-P4-6/7） | 新增 `ReconcileDispute`（只读、零写），`SourceResult` 复用；dispute 相关 BT 需进 provider 快照（Q5/Q6） |
| Provider 快照 | `ProviderFinancialDetails`（transient，9 值 settlement enum） | 覆盖 dispute 相关 BT（type/amount/fee）与 funds reinstated/withdrawn |

---

## 8. 非功能需求（NFR）

- **幂等**：webhook `provider_event_id` 去重 + dispute 幂等键 + ledger `idempotency_key`；
- **不可变**：evidence snapshot 不可变（content_hash）；Journal append-only（B5）；
- **可观测**：`(state, evidence_due_at)` 索引 + sweeper 告警 + `manual_review` 队列 + 事件 replay；
- **安全**：复用既有 webhook 验签（无新凭证）；后台写动作需 capability（沿用 batch5b 注册表模式）；
- **兼容**：非 Stripe provider 维持 `UNSUPPORTED` 语义（FIN-P4-5 模式），不静默降级。

---

## 9. 开放项（provider 侧实测）— **已取证关闭（2026-09-11，dev + Stripe test mode）**

| # | 开放项 | 实测结论（2026-09-11，三次真实 dispute 实验） | 状态 |
|---|---|---|---|
| O1 | Stripe dispute 相关 BalanceTransaction 类型、dispute fee 表现 | **扣款** = 单条 `adjustment` BT：`amount = -争议额`、`fee = 1500`（**固定 $15**，与争议额无关）、`net = -(争议额+fee)`；**不存在独立的 fee BT**。**胜诉返还** = 另开一条 `adjustment` BT：`amount = +争议额`、**`fee = 0`**、`net = +争议额` → **dispute fee 胜诉也不退还** | ✅ 已确认 |
| O2 | partial dispute 的字段语义（`amount` 与 `payment_intent.amount` 的关系） | **未覆盖**：test helper 令牌仅能产生全额 dispute（`amount == payment_intent.amount`，三次实验 $10/$25/$50 均为全额）；账户禁用 raw card data API，partial 无法构造 | ⚠️ 未实测（设计按"不假设相等"处理，见 §9.2） |
| O3 | 两次 dispute 同一 payment 的实际事件序列与恢复路径 | **乱序必然存在（三次实验均复现）**：`funds_withdrawn` 与 `created` 恒为**同一秒**，但两者先后在 B1/B3 与 B2 中**不一致**；`funds_withdrawn` 与 `closed` 可同秒（B3）| ✅ 已确认 |
| O4 | `evidence_details.due_by` 的时区/窗口 | `due_by = 1789862399` → **2026-09-19 23:59:59 UTC**（UTC 日末；B1/B2 同一值，窗口 ≈ 8 天）。**非本地时区、非事件时刻+8×24h** | ✅ 已确认 |
| O5 | `funds_reinstated` 与 `closed` 的先后关系（win 场景） | **两条终局路径均已实测**：① **won**（B3，$50）→ `closed` 与 `funds_reinstated` **同一秒（18:10:33Z）**，列表序 `closed` 在前；② **lost**（B2，$25）→ `closed` 在 `funds_withdrawn` 后 2 秒，**无** `funds_reinstated`。**先后关系不稳定 ⇒ 不可依赖顺序**。本地收敛：`state=won/outcome=won` 且 `funds_reinstated_at` 写入 ✓；`state=lost/outcome=lost` 且 `funds_reinstated_at=nil` ✓ | ✅ 已确认 |

> O1–O5 是 **P7-3 财务切片的输入**；P7-1（模型 + 事件入口）可以先落地。

### 9.1 取证方法与原始证据（2026-09-11）

**环境**：dev 栈（`pallastrade-dev-*`）+ Stripe test mode，gateway `PallasTradeStripe::Gateway` id=4；
webhook endpoint `we_1U7VcvBP3yRzFgyp5bylxUb2` → `https://dev.pallastrade.cn/api/v3/webhooks/payments/pm_VqXmZF31wY`（订阅 13 事件，含 5 个 `charge.dispute.*`）。
**链路为真实 provider → 真实 webhook → 真实入库，非 mock。**

**三次实验（覆盖 3 条不同终局路径）**：

| 实验 | 金额 | 构造方式 | 终局 | 关键观测 |
|---|---|---|---|---|
| B1 | $10 | `tok_createDispute` + 提交通用证据 | `under_review`（长期挂起） | 扣款 BT；`funds_withdrawn`/`created` 同秒；`updated` 驱动状态收敛 |
| B2 | $25 | `tok_createDispute` + `Stripe::Dispute.close` | **lost** | `created`→`funds_withdrawn`（同秒）→`closed`(+2s)；无返还款 |
| B3 | $50 | `tok_createDispute` + `uncategorized_text='winning_evidence'` + `submit` | **won** | **两条 BT**（扣款 + 返还）；`closed` 与 `funds_reinstated` 同秒 |

> **测试方法学（供后续切片复用）**：test mode 下 `Dispute.close` 只产出 `lost`；**唯一可编程的 `won` 路径**是提交证据时把
> `uncategorized_text` 设为 `winning_evidence`（Stripe 测试文档 §模拟争议 §证据）。这是 P7 线复现"胜诉 + 资金返还"的确定手段。

**原始证据（逐项）**：

- **O1（扣款）**：B1 `txn_1UEXiSBP3yRzFgypVXuOWcHW type=adjustment amount=-1000 fee=1500 net=-2500`；
  B2 `txn_1UEYrjBP3yRzFgypFbbfXF8f type=adjustment amount=-2500 fee=1500 net=-4000`；
  B3 `txn_1UEYu7BP3yRzFgypmYAvgVuv type=adjustment amount=-5000 fee=1500 net=-6500`
  → **fee 恒为 1500（$15）**，与争议额 $10/$25/$50 无关
- **O1（返还，B3）**：`txn_1UEYuCBP3yRzFgyp4yzMNSzV type=adjustment amount=5000 fee=0 net=5000`
  → **只返还争议额，$15 dispute fee 不返还**（净损失 = fee）
- **O3/O5（事件序列，provider 侧 `Stripe::Event` 时间戳）**：
  - B1：`created` + `funds_withdrawn`（同秒 16:54:21Z）→ `updated`（16:58:29Z）
  - B2：`created` + `funds_withdrawn`（18:07:59Z）→ `closed`（18:08:01Z）
  - B3：`created` + `funds_withdrawn`（18:10:27Z）→ `updated`（18:10:28Z）→ `closed` + `funds_reinstated`（**同秒 18:10:33Z**）
  - **同秒事件的相对顺序在三次实验间不一致（B1/B3 `funds_withdrawn` 在前，B2 `created` 在前）**
- **O4**：`evidence_details.due_by = 1789862399` → `2026-09-19 23:59:59 UTC`（B1/B2 均为该值）

**P7-1/P7-2 代码在真实环境的联动验证**（同批实验顺带完成）：

| 断言 | 实测结果 |
|---|---|
| webhook 落地 + 幂等键 | `PaymentWebhookEvent` 11 条 dispute 事件全部 `processed`（含乱序到达） |
| dispute 落库（P7-1） | 3 行 `PallasTrade::Dispute`，`state` 随事件正确收敛（`under_review` / `lost` / `won`） |
| `funds_withdrawn_at` 写入（P7-2） | B1 `16:54:21Z`、B3 `18:10:27Z`（由 `charge.dispute.funds_withdrawn` 首次观测写入） |
| **`funds_reinstated_at` 写入（P7-2）** | **B3 `2026-09-11 18:10:33 UTC` ✓（win 路径首次真实写入）**；B1/B2 为 `nil`（未收到 reinstate 事件，语义正确） |
| 终局字段 | B2 `outcome=lost`/`resolved_at=18:08:01`；B3 `outcome=won` |
| 乱序容错（P7-1/2） | `funds_withdrawn` 早于 `created` 到达时仍正确落库与收敛（无丢失、无覆盖） |
| 无锚点不丢事件（P7-1） | 三行均 `attention_reason = unlinked_payment`（独立测试支付无本地 payment 锚点，事件仍落库不丢失） |

### 9.2 对 P7-3 的设计含义（依据上述事实）

| 事实 | P7-3 设计结论 |
|---|---|
| 扣款与 fee 在**同一条** `adjustment` BT（`amount=-争议额, fee=1500, net=-(争议额+1500)`） | 打款事实必须**拆两条**流水：`DISPUTE_DEBIT` = 争议额、dispute fee = 独立费用条目（`PSP_FEE` 语义）；二者共享同一 provider BT 引用。**不得**把 `net` 当成单一发生额 |
| 返还 BT 只含争议额（`fee=0`），**fee 不退** | 胜诉时记 `DISPUTE_CREDIT` = 争议额；**dispute fee 是净损失，必须单独入账且不可冲回**（对账需能识别"已扣 fee 未返还"） |
| `funds_withdrawn` 可早于/晚于 `created`（同秒、顺序不稳） | 入账**不可依赖事件到达顺序**；必须以 `DisputeFact`（P7-2 裁决）为准，`fact_posting_key` 用 dispute 维度去重而非事件序 |
| `closed` 与 `funds_reinstated` 同秒、顺序不定 | **金额事实与胜负结论解耦**：金额由 `funds_*` 驱动、胜负由 `won/lost` 驱动，两者不互推 ⇒ 顺序无关即正确 |
| `due_by` 为 UTC 日末 23:59:59（≈8 天） | P7-5 sweeper 用 **UTC** 语义判定到期；窗口长度**不写死**，读 provider 快照 |
| partial 未实测（`amount` 与 PI 金额关系未证） | 金额**一律取 dispute 自身快照**（`DisputeFact.amount`），**禁止**用 `payment_intent.amount` 推导；partial 场景留 `AMBIGUOUS` + reason_code 出口 |
| 无锚点（`unlinked_payment`）真实可达 | P7-3 入账需处理"无 payment 锚点"的事实：**不得静默丢弃**，应进 `NEEDS_ATTENTION`/manual_review 通道（P7-6 兜底） |

---

## 10. 跨层搜索记录（6 层，2026-09-11 实测）

| 层 | 路径 | 关键词 | 找到 | 是否满足需求 |
|---|---|---|---|---|
| App（宿主） | `backend/` | `dispute\|chargeback` | 0 命中（含 app/gems/config/db） | 绿地 |
| Core | `pallastrade_gems/pallastrade_core/app/`+`lib/` | 同上 | 0 命中 dispute；但集成面齐备：`FinancialFact`、`FinancialLedgerEntry`、`FinancialFacts::*`、`FinancialLedger::*`、`Reconciliations::{ReconcilePayment,ReconcileRefund,ReconcileTransaction}`、`Payments::{WebhookEventStore,HandleWebhook,ReplayWebhookEvent}` | 需新建（P7） |
| API | `pallastrade_gems/pallastrade_api/app/` | 同上 | 0 命中 dispute；入口 = `Api::V3::Webhooks::PaymentsController` | 需扩展入口 |
| Admin | `pallastrade_gems/pallastrade_admin/app/`+`lib/` | 同上 | 0 命中 dispute；运维面 = `PaymentsOpsController`、`TransactionsController`（Orders 导航组） | P7-7 挂载点已定位 |
| Storefront | `storefront/src/` | 同上 | 0 命中 | 不涉及（dispute 不面向店面） |
| Platform | `platform/packages/` | 同上 | 0 命中 | 不涉及（无 SDK/CLI 面；若未来暴露 Admin API 再议） |

**结论**：P7 属绿地；**不新建并行体系**——一律复用 P0 webhook inbox、P4 Fact/Journal/Reconciliation、P6 的
durable + manual_review 模式；防重复判定：无任何既有 dispute 能力可复用，也无历史包袱需兼容。

---

## 11. 技术影响

- **本切片**：仅新增文档（本 PRD + REQ + `docs/prd/README.md` 索引），**不改代码/迁移/契约**。
- **对后续切片的影响**：P7-1 迁移（新表 + 事件入口）、P7-3 会触及 `FinancialFact::FACT_TYPES` /
  `FinancialLedgerEntry::ENTRY_TYPES` / `fact_posting_key`（**跨域常量扩展，需按 §7 表格逐条做 AC 与回归**）。

---

## 12. 测试计划

| 切片 | 测试策略 |
|---|---|
| P7-0（本切片） | **无代码 → 不新增测试**；验收方式 = 审计结论的代码级证据 + 评审（review evidence）。`prd verify` 的 AC↔测试映射在 P7-1 建立测试时补齐 |
| P7-1 | 模型 spec（状态机/幂等/部分金额）+ webhook 入口 request spec（含"未知/无锚点事件不丢"）+ 回归（promotions/refund/payment 全套） |
| P7-3 | Fact 解析 spec + Journal posting 幂等 spec + `ReconcileDispute` spec + 既有 FIN-P4 回归 |

---

## 13. 文档同步清单（知识同步门）

- [x] 本 PRD + `docs/prd/README.md` 索引
- [x] `harness/requirements/REQ-20260911-dsp-p7-0-dispute-semantic-audit.md`
- [ ] `ai/skills/pallastrade-payments/SKILL.md`：**P7-1 实施时新增 P7 章节**（本切片 audit-only，不改 Skill；
      在 §11 已记录该待办，避免"文档先行于代码"）
- [ ] 机制类资产（AGENTS.md / copilot-instructions / scenarios）：P7-1 起按 sync-check 判定

**知识同步门结论（sync-check，2026-09-11）**：全资产 19 项逐项评估完成 —— **all reviewed-no-change**
（本切片未改代码，故领域 Skill / data-model / 测试 / 场景库 / 契约 / SDK / storefront / events /
security / 机制类资产均无需变更），已 `sync-check --ack`，知识环 19/4 通过。其中"领域 Skill 的 P7 章节"
与"scenarios 的 dispute 场景"显式留给 P7-1 一并交付（避免文档先行于代码）。

---

## 14. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-11 | 0.1 | 初稿：P7-0 审计冻结（边界 B1–B7、Q1–Q9 结论 + F1–F6 附加发现、Dispute DB proposal、事件入口、财务/对账集成面、O1–O5 开放项、DSP-P7-1..8 切片计划） | AI |
| 2026-09-11 | 0.2 | §9 开放项取证落地：dev + Stripe test mode 三次真实 dispute 实验（B1 $10 / B2 $25 lost / B3 $50 won）→ **O1/O3/O4/O5 确认关闭**（扣款与 fee 同条 adjustment BT 且 fee 恒定 $15、返还仅返争议额 fee 不退、事件同秒乱序必然、`closed` 与 `funds_reinstated` 同秒且顺序不定、`due_by` 为 UTC 日末）；**O2 partial 未覆盖**（test helper 令牌仅能产生全额争议）；新增 §9.1 原始证据（含测试方法学：`uncategorized_text='winning_evidence'` 是唯一可编程 won 路径）与 §9.2「对 P7-3 的设计含义」；同批完成 P7-1/P7-2 代码在真实环境的联动验证（含 `funds_reinstated_at` 首次真实写入） | AI |
