# PRD-20260911-payments-dsp-p7-2-dispute-fact-resolution

| 元数据 | 值 |
|---|---|
| 状态 | done（2026-09-11 实施、验证、知识同步完成；待提交） |
| 创建日期 | 2026-09-11 |
| 来源 | 用户指令「实施」「应该可以继续工作了」→ 承接 `PRD-20260911-payments-dsp-p7-0-*` / `-p7-1-*` → 实施 DSP-P7-2 |
| 分类 | payments（`harness prd new` 自动判定 other，按 AGENTS §0.3 语义微调：属 payments 域） |
| 关联 Skill | `pallastrade-payments`、`pallastrade-data-model`、`pallastrade-customization` |
| 关联 REQ | `REQ-20260911-dsp-p7-2-dispute-fact-resolution.md` |
| 关联 PRD | `PRD-20260911-payments-dsp-p7-0-dispute-semantic-audit-and-data-model-freeze.md`（语义冻结）、`PRD-20260911-payments-dsp-p7-1-durable-dispute-model-and-provider-event-ingestion.md`（模型与入口） |
| 需求类型 | 新功能（只读裁决层 + provider 只读契约 + 迁移） |

> 本切片只做 **事实裁决层**（P7-0 §7 / FR-002）：provider 只读 fetch 契约 + `DisputeFact` 裁决
> + funds 时间戳落地。**不做**：Journal/Entry 激活（P7-3）、Evidence（P7-4）、Sweeper（P7-5）、
> Recovery 收敛动作（P7-6）、Admin Console（P7-7）、多 provider 实现（P7-8）。

---

## 1. 背景与目标

- **一句话需求原文**：「实施」→「应该可以继续工作了」（承接 P7-0/P7-1，按切片计划实施 DSP-P7-2）。
- **背景**（P7-1 交付后的三个缺口）：
  1. **状态是"单事件直译"**：`Disputes::HandleProviderEvent` 只把当次 webhook 的 provider 状态映射到本地；
     没有跨源裁决——本地可能**落后**（漏事件）、**超前**（本地先行处置）或**冲突**（双方终态相反），无人知晓；
  2. **funds 事件缺时间戳**：`charge.dispute.funds_withdrawn` / `funds_reinstated` 目前只落
     `PaymentWebhookEvent.action`，dispute 行没有"何时扣款/何时返还"的事实 → P7-3 资金入账缺输入；
  3. **缺事实契约**：P7-3（Journal/Reconciliation）需要稳定的事实词汇 + 确认度语义（AMBIGUOUS 不猜），
     否则会重演 P7-0 审计指出的"多源判定"风险。
- **目标**：
  1. 落地 `PaymentMethod#fetch_dispute_details(dispute:)` **只读**契约（Stripe 实现；其余 provider 自然降级
     `UNSUPPORTED`），同时作为 P7-0 §9 的 **O1–O5 取证工具**；
  2. 落地只读 `Disputes::ResolveFact` → `DisputeFact`（transient VO），给出**裁决矩阵**
     （aligned / stale_local / stale_provider / conflict / unknown / unsupported / unavailable / not_applicable）
     与确认度（CONFIRMED / AMBIGUOUS / UNSUPPORTED / NOT_APPLICABLE）；
  3. **冻结事实词汇**：`DISPUTE_OPENED / DISPUTE_FUNDS_WITHDRAWN / DISPUTE_FUNDS_REINSTATED / DISPUTE_WON /
     DISPUTE_LOST`（P7-3 扩展 `FinancialFact::FACT_TYPES` 时按同名对齐）；
  4. 补 funds 时间戳列（`funds_withdrawn_at` / `funds_reinstated_at`）并由入口服务落库（幂等、不覆盖）。
- **成功指标**（可验证）：
  1. 任一 dispute 可回答"本地状态 vs provider 状态 vs 判定（含确认度）"，失败路径全部为封闭枚举；
  2. 裁决与 fetch 全链路**零本地资金/状态副作用**（快照断言）；
  3. 契约缺失 / provider 故障 / 金额不可证三类降级各有独立可断言语义；
  4. 回归：`p0-payment-rspec` + 新增 spec 全绿；`generated:check` / `doc-impact` 通过。

## 2. 用户故事 / 场景

- 作为**平台运维**：我希望知道"本地状态是否与 provider 一致"，以便发现漏事件（stale_local）或本地先行处置
  （stale_provider），而不是等对账时才暴露；
- 作为**财务**：我希望得到可入账的资金事实（何时扣款 / 返还 / 输赢），而不是从事件名推断；
- 作为**开发**：我希望 dispute 只读契约与降级语义与既有 `fetch_refund_details` / `fetch_payment_status`
  完全一致，可直接复用既有模式；
- 场景（正常 / 边界 / 异常）：
  1. 正常：本地 `needs_response`，provider 快照 `needs_response` → `aligned` / CONFIRMED；
  2. 落后：本地 `under_review`，provider `lost` → `stale_local`（P7-6 收敛输入）；
  3. 超前：本地 `won`（本地先行），provider `needs_response` → `stale_provider`；
  4. 冲突：本地 `won`，provider `lost` → `conflict`；本地 `manual_review` → 一律 `conflict`；
  5. 未知：无快照且无历史 `provider_status` → `unknown` / AMBIGUOUS；
  6. 契约缺失：非 Stripe provider（未实现 fetch）→ `unsupported` / UNSUPPORTED（不猜）；
  7. 故障：provider API 报错 → `unavailable` / AMBIGUOUS（不阻断、不猜测）；
  8. 金额不可证：`amount` 缺失或 ≤ 0 → AMBIGUOUS + `AMOUNT_UNPROVABLE`（**不产生资金事实**）；
  9. 非 PSP 载体：StoreCredit / Check → `not_applicable` / NOT_APPLICABLE；
  10. funds：`charge.dispute.funds_withdrawn` → `funds_withdrawn_at` 落库（重复投递不覆盖已有时点）。

## 3. 功能需求（FR）

- **FR-001（provider 只读契约）**：`PaymentMethod#fetch_dispute_details(dispute:)`；base raise
  `NotImplementedError`；Stripe 实现 `Stripe::Dispute.retrieve` 并归一为
  `{ provider_dispute_reference:, status:, amount:, currency:, reason:, network_reason_code:,
  evidence_due_at:, evidence_submitted_at:, has_evidence:, outcome:, balance_transaction_references:,
  observed_at: }`（金额 **major units**，零小数货币不除 100；无引用 → `PallasTrade::Core::GatewayError`；
  只读、零本地写、无 provider mutation）。
- **FR-002（只读裁决）**：`Disputes::ResolveFact.call(dispute:, fetch: false)`；`fetch: true` 时先取 provider
  快照（只读）再判定；异常在被调用链内降级为封闭 verdict（不抛出）。
- **FR-003（事实 VO）**：`Disputes::DisputeFact`（transient、`freeze`、属性白名单）；
  `FACT_TYPES` / `STATUSES` / `RESOLUTIONS` / `SOURCES` 常量冻结；非法属性 raise `ArgumentError`。
- **FR-004（裁决矩阵）**：以 provider 状态（快照优先，回退 `private_metadata['provider_status']`，
  再回退无）与本地 `Dispute#state` 比较（复用 `ProviderPayload::STATE_BY_PROVIDER_STATUS` +
  `Dispute::STATE_ORDER` 阶段序）：`aligned` / `stale_local` / `stale_provider` / `conflict` / `unknown` /
  `unsupported` / `unavailable` / `not_applicable`；`manual_review` 一律 `conflict`。
- **FR-005（funds 时间戳）**：迁移新增 `funds_withdrawn_at` / `funds_reinstated_at`（datetime，可空，索引留 P7-5）；
  `Disputes::HandleProviderEvent` 在 `dispute_funds_withdrawn` / `dispute_funds_reinstated` 动作落库
  （首次观测写入，不覆盖既有值；重复投递幂等）。
- **FR-006（降级纪律）**：契约缺失 → `UNSUPPORTED` + `PROVIDER_CONTRACT_UNSUPPORTED`；provider 故障 →
  `AMBIGUOUS` + `PROVIDER_UNAVAILABLE`；无 payment 锚点且请求 fetch → `AMBIGUOUS` + `UNLINKED_PAYMENT`；
  金额不可证 → `AMBIGUOUS` + `AMOUNT_UNPROVABLE`。
- **FR-007（零写边界）**：`ResolveFact` / fetch **不写** order / inventory / payment / ledger / dispute
  （如需持久化裁决观察，由 P7-5 sweeper 或 P7-6 收敛切片决定并另建 AC）。
- **FR-008（词汇对齐）**：`DisputeFact::FACT_TYPES` 与 P7-0 §7 提案一致，P7-3 扩展
  `FinancialFact::FACT_TYPES` / `FinancialLedgerEntry::ENTRY_TYPES` 时按同名对齐。

> **明确不做**（本切片）：`attention_reason` 扩展（当前无 writer，延后至 P7-6）、裁决持久化/告警（P7-5）、
> Journal posting（P7-3）、其他 provider 实现（P7-8）、Admin 可见性（P7-7）。

## 4. 非功能需求（NFR）

- **只读 / 幂等**：重复裁决结果稳定；fetch 无副作用；重复 webhook 不改变已落 funds 时间戳；
- **降级**：provider 不可用/未实现不阻断调用方（封闭枚举 + reason_code）；
- **兼容**：非 Stripe provider 不误报——capability 检测沿用 `fetch_refund_details` 的 method owner 模式；
- **可观测**：`observed_at` + `source`（local / provider_fetch）可追溯；
- **安全**：无新凭证、无新端点、无后台写面、无 provider mutation（仅 retrieve）。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001 ← FR-001**：Stripe `fetch_dispute_details` 归一正确（status/amount/currency/evidence_due_at/
  balance_transaction refs）；无引用 → `GatewayError`；base 实现 raise `NotImplementedError`；
  capability 检测（method owner）Stripe = true / base = false。
- **AC-002 ← FR-002/004**：裁决矩阵 8 用例断言（aligned / stale_local / stale_provider / conflict /
  unknown / unsupported / unavailable / not_applicable）。
- **AC-003 ← FR-006**：三类降级语义断言（UNSUPPORTED+PROVIDER_CONTRACT_UNSUPPORTED /
  AMBIGUOUS+PROVIDER_UNAVAILABLE / AMBIGUOUS+AMOUNT_UNPROVABLE）。
- **AC-004 ← FR-005**：funds 事件写时间戳；重复事件不覆盖已有时点；非 funds 事件不写。
- **AC-005 ← FR-003/008**：VO 常量（FACT_TYPES/STATUSES/RESOLUTIONS/SOURCES）冻结 + 非法属性 raise。
- **AC-006 ← FR-007**：零副作用——dispute/order/payment/ledger 快照对比断言；fetch 路径仅调用只读 retrieve。
- **AC-007 ← 全**：`p0-payment-rspec` 回归全绿 + 新增 spec 全绿 + `harness check --profile quick` /
  `generated:check` / `doc-impact` 通过。

## 6. 跨层搜索记录（6 层，2026-09-11 实测）

| 层 | 路径 | 关键词 | 找到 | 是否满足需求 |
|---|---|---|---|---|
| App（宿主） | `backend/app`、`backend/config` | `dispute\|fetch_dispute\|resolve_fact` | 0 命中 | 绿地；迁移继续走宿主 `backend/db/migrate/` |
| Core | `pallastrade_core/app`、`lib` | 同上 | 0 dispute 契约；**模式先例齐备**：`fetch_payment_status` / `fetch_financial_details` / `fetch_refund_details`（base `NotImplementedError`）+ `provider_refund_amount`（base nil） + capability owner 检测（`CaptureEvidencePolicy.implements_financial_details?`、`ReconcileRefund.implements_refund_details?`） | 复用模式，新建 dispute 契约 |
| API | `pallastrade_api/app` | 同上 | 0 命中 | 不涉及（无端点变更） |
| Admin | `pallastrade_admin/app` | 同上 | 0 命中 | 不涉及（Console 属 P7-7） |
| Storefront | `storefront/src` | 同上 | 0 命中 | 不涉及 |
| Platform | `platform/packages` | 同上 | 0 命中 | 不涉及 |

**结论**：**不新建并行体系**——裁决层落在 P7-1 已建立的 dispute 域内（`PallasTrade::Disputes::*`），
provider 只读契约沿用 FIN-P4-5/6 的既有模式与降级语义；迁移沿用宿主 `backend/db/migrate/` 惯例。

## 7. 技术影响

**新增**
- `pallastrade_core/app/services/pallastrade/disputes/dispute_fact.rb`（VO + 词汇常量）
- `pallastrade_core/app/services/pallastrade/disputes/resolve_fact.rb`（只读裁决）
- `backend/db/migrate/20260911000003_add_funds_timestamps_to_pallastrade_disputes.rb`

**修改**
- `pallastrade_core/app/models/pallastrade/payment_method.rb`（+ `fetch_dispute_details` base 契约）
- `pallastrade_stripe/app/models/pallastrade_stripe/gateway.rb`（+ `fetch_dispute_details` 实现 + `retrieve_dispute`）
- `pallastrade_core/app/services/pallastrade/disputes/handle_provider_event.rb`（funds 时间戳落库）
- `backend/db/schema.rb`（迁移产物）

**不改**：Order / Payment / Inventory / FinancialLedger / Reconciliation 语义；API 契约（无新端点）；
Admin 导航；Stripe 订阅清单（P7-1 已含 funds 事件）。

**部署注意**：迁移需在 dev/test 执行（`RAILS_ENV=... db:migrate`）；本切片**无 provider 侧变更**
（仅只读 retrieve，不注册端点、不改订阅）。

## 8. 测试计划

| 文件 | 类型 | 覆盖 AC |
|---|---|---|
| `backend/spec/services/pallastrade/disputes/resolve_fact_spec.rb`（新） | service | AC-002 / AC-003 / AC-005 / AC-006 |
| `backend/spec/models/pallastrade_stripe/gateway_fetch_dispute_details_spec.rb`（新） | gateway | AC-001 |
| `backend/spec/services/pallastrade/disputes/handle_provider_event_spec.rb`（扩展） | service | AC-004 |
| `backend/spec/models/pallastrade/dispute_spec.rb`（扩展，如需列/谓词断言） | model | AC-005 |
| `p0-payment-rspec` 验证器（注册） | 回归 | AC-007 |

## 9. 文档同步清单（知识同步门）

- [ ] `ai/skills/pallastrade-payments/SKILL.md`：新增 P7-2 章节（只读契约 + 裁决矩阵 + funds 时间戳）
- [ ] `ai/skills/pallastrade-data-model/SKILL.md`：`pallastrade_disputes` 补 funds 时间戳两列
- [ ] `harness/scenarios/scenarios.json`：GS-092
- [ ] `docs/prd/README.md` 索引 + 本 PRD 状态
- [ ] 契约：无 API 变更 → `generated:check` 确认无漂移
- [ ] 机制类资产（AGENTS.md / copilot-instructions）：本切片无机制变更 → reviewed-no-change

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-11 | 0.1 | 初稿：DSP-P7-2 范围（fetch_dispute 只读契约 + DisputeFact 裁决矩阵 + funds 时间戳 + 词汇冻结），AC-001..007 与测试映射 | AI |
| 2026-09-11 | 1.0 | 实施完成：只读契约（base + Stripe）、`DisputeFact`/`ResolveFact`（8 裁决 + 3 降级）、funds 时间戳迁移与落库；spec 37 例绿 + p0/backend-rspec 回归；Skill×2（payments/data-model）+ GS-092 同步；用户「实施」「应该可以继续工作了」确认 | AI |
