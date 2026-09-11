# REQ-20260911-dsp-p7-2-dispute-fact-resolution

| 项 | 值 |
|---|---|
| 需求 | DSP-P7-2 — Dispute Fact Resolution（P7 线第三个切片：只读裁决层 + provider 只读契约 + funds 时间戳） |
| 类型 | 新功能（新服务/VO + 迁移 + provider 只读契约） |
| 关联 PRD | `docs/prd/payments/PRD-20260911-payments-dsp-p7-2-dispute-fact-resolution.md`（draft → 用户确认后 approved） |
| 前置 PRD | `PRD-20260911-payments-dsp-p7-0-*`（语义冻结）、`PRD-20260911-payments-dsp-p7-1-*`（模型与事件入口，已发布 `143842e3`） |
| 关联任务 | TASK-20260911141145-338e4420 |
| Gate | GATE-2026-09-11T14-12-00（type: feature，risk: critical） |
| 分支 | dev（基线 143842e3） |

---

## Step 0 — 跨层搜索（6 层，2026-09-11 实测）

| 层 | 搜索路径 | 关键词 | 结果 | 是否已满足需求 |
|---|---|---|---|---|
| App（宿主） | `backend/app`、`backend/config` | `dispute\|fetch_dispute\|resolve_fact` | **0 命中** | 绿地；迁移走宿主 `backend/db/migrate/`（P7-1 同惯例） |
| Core | `pallastrade_core/app`、`pallastrade_core/lib` | 同上 | 0 dispute 契约；**只读契约模式先例**：`PaymentMethod#fetch_payment_status` / `fetch_financial_details` / `fetch_refund_details`（base `NotImplementedError`）、`provider_refund_amount`（base nil）；capability 检测 = method owner ≠ base（`CaptureEvidencePolicy.implements_financial_details?`、`ReconcileRefund.implements_refund_details?`）；降级语义 = `SourceResult::UNSUPPORTED` + `PROVIDER_CONTRACT_UNSUPPORTED` | 复用模式新建 dispute 契约 |
| API | `pallastrade_api/app` | 同上 | 0 命中 | 不涉及（无端点变更） |
| Admin | `pallastrade_admin/app` | 同上 | 0 命中 | 不涉及（P7-7） |
| Storefront | `storefront/src` | 同上 | 0 命中 | 不涉及 |
| Platform | `platform/packages` | 同上 | 0 命中 | 不涉及 |

**结论**：裁决层不新起体系——沿用 P7-1 的 `PallasTrade::Disputes::*` 域 + FIN-P4-5/6 的 provider 只读契约
模式（base raise / owner capability / 封闭降级枚举）。

---

## Step 1 — Skill 咨询证据

| Skill | 读取 | 关键结论（用于本切片） |
|---|---|---|
| `pallastrade-customization` | ✅ | 决策树优先级「Settings → Configuration → Events → Dependencies → Admin/Ransack → Generators → Decorators → Extensions」；结构性新增（新模型/新服务）直接落在 gem 内；**能用既有基建不新起机制** → 本切片复用 P7-1 dispute 域与既有只读契约模式，不新增入口/依赖/订阅 |
| `harness-prd` | ✅ | R8 流程：`prd new`（查重）→ 模板扩充（背景/FR/AC/技术影响/测试计划/文档同步）→ 用户确认 → gate → 实施 → AC↔测试（`prd verify`）→ 知识同步 → evidence → finish；本切片改动含逻辑 + 新增文件 > 5 → **完整版 REQ**（本文件） |
| `pallastrade-payments` | ✅ | P7-1 章节：dispute 域边界（Refund≠Dispute、webhook=evidence）、入口链路、`Dispute` 状态机与 `attention_reason`；既有只读契约链（FIN-P4-5/6）证明"base raise + provider 实现 + owner 检测"是本仓既定模式；**funds 事件当前只记 action**（本切片补 `funds_*_at` 时间戳） |
| `pallastrade-data-model` | ✅ | `pallastrade_disputes`：unique `(provider, provider_dispute_reference)` 幂等键、10 态**阶段序单向**状态机、`evidence_due_at` 一等列、`attention_reason` 非空=需人工；本切片新增 `funds_withdrawn_at` / `funds_reinstated_at` 两列（不改状态机） |

---

## Step 2 — 实施范围（对齐 PRD §3/§7）

**新增**
1. `pallastrade_core/app/services/pallastrade/disputes/dispute_fact.rb`（VO + `FACT_TYPES`/`STATUSES`/`RESOLUTIONS`/`SOURCES` 冻结）
2. `pallastrade_core/app/services/pallastrade/disputes/resolve_fact.rb`（只读裁决；`fetch:` 可选只读快照）
3. `backend/db/migrate/20260911000003_add_funds_timestamps_to_pallastrade_disputes.rb`

**修改**
4. `pallastrade_core/app/models/pallastrade/payment_method.rb`（+ `fetch_dispute_details` base 契约）
5. `pallastrade_stripe/app/models/pallastrade_stripe/gateway.rb`（+ 实现 + `retrieve_dispute`）
6. `pallastrade_core/app/services/pallastrade/disputes/handle_provider_event.rb`（funds 时间戳落库，幂等）
7. `backend/db/schema.rb`（迁移产物）

**不改**：Order / Payment / Inventory / FinancialLedger / Reconciliation 语义；API 契约；Admin 导航；
Stripe 订阅清单；`Dispute` 状态机与 `attention_reason` 白名单（本切片零写、零新枚举）。

---

## Step 3 — 验证方案（AC → 命令/测试）

| AC | 验证 |
|---|---|
| AC-001 | `spec/models/pallastrade_stripe/gateway_fetch_dispute_details_spec.rb`（新） |
| AC-002 / 003 | `spec/services/pallastrade/disputes/resolve_fact_spec.rb`（新；8 矩阵 + 3 降级） |
| AC-004 | `spec/services/pallastrade/disputes/handle_provider_event_spec.rb`（扩展：funds 时间戳 + 幂等不覆盖） |
| AC-005 | `resolve_fact_spec`（VO 常量 + 非法属性） |
| AC-006 | `resolve_fact_spec`（零副作用快照断言） |
| AC-007 | 注册验证器 `p0-payment-rspec` + `harness check --profile quick` / `generated:check` / `doc-impact` |

**风险与恢复（critical）**：需 `harness recovery create` 恢复计划 + 用户显式批准（R7）。
恢复要点 = 迁移可回滚（`remove_column ×2`，无数据回填、无破坏性变更）+ 代码 revert（新增文件删除 +
3 处修改回退）+ provider 侧零变更（仅只读 retrieve，无需回滚远程状态）。
