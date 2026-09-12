# REQ-20260912-dsp-p7-4-dispute-evidence-snapshot

> 关联 PRD：`docs/prd/payments/PRD-20260912-payments-dsp-p7-4-dispute-evidence-snapshot.md`
> 任务：`TASK-20260912124024-67920c95` ｜ Gate：`GATE-2026-09-12T12-40-37`（feature，branch `dev`）

---

## Step 0：跨层搜索（强制执行）

关键词：`evidence` / `snapshot` / `proof_of_delivery` / `delivered_at` / `shipment` / `tracking` / `Dispute`

| 层 | 搜索路径 | 找到的文件 | 是否满足需求？ |
|---|---|---|---|
| App — models/controllers | `backend/app/` | 无命中 | ❌ 无既有能力 |
| App — views/decorators | `backend/app/` | 无命中 | ❌ |
| Core Gem — models | `.../pallastrade_core/app/models/` | `dispute.rb`、`financial_ledger_entry.rb`（账本行） | ⚠️ 只提供原始记录，无证据投影 |
| Core Gem — services | `.../pallastrade_core/app/services/` | `disputes/{dispute_fact,resolve_fact,handle_provider_event,provider_payload}.rb`、`financial_ledger/post_dispute.rb`、`reconciliations/reconcile_dispute.rb` | ⚠️ 事实/账行/对账可作只读输入；**BuildEvidenceSnapshot 不存在** |
| API Gem | `.../pallastrade_api/app/` | 无 dispute/evidence 命中 | ❌ 本切片无 API 变更 |
| Admin Gem | `.../pallastrade_admin/app/` | 无命中 | ❌ 无 Admin UI（归 P7-7） |
| Storefront | `storefront/src/` | 无命中 | ❌ 不适用 |
| Platform | `platform/packages/` | 无命中 | ❌ 无 SDK 变更 |

### 搜索结论

- 6 层均无「争议证据快照」能力 → **新增**；落点 `pallastrade_core`（AGENTS §3 第 8 级「直接改 Gem」+ `# PALLAS-CUSTOM` 注释）。
- 复用只读输入：P7-2 `Disputes::ResolveFact`（事实/确认度/裁决）、P7-3 `Reconciliations::ReconcileDispute`（对账分类）+ 既有 Order/Shipment/Refund 记录。
- 证据**提交**给 provider 明确不在本切片（源计划 §43/§67 属危险操作，归 P7-8）。

---

## Step 1：Skill 文件咨询（强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树第 8 级「直接改 Gem」适用于框架自研产品线（本切片沿用 FIN-P4/P7-1..3 同口径） |
| `ai/skills/pallastrade-data-model/SKILL.md` | ✅ 已读 | §Disputes：`pallastrade_disputes`（`dsp_`）含 `evidence_due_at`/`evidence_submitted_at`（已有一等列）→ 证据快照**无需新表**（源计划 §41 同结论） |
| `ai/skills/harness-prd/SKILL.md` | ✅ 已读 | 全新切片（P7-3 PRD 已预留 Evidence）→ `prd new --force` 成立；PRD 需完整扩充后再请用户确认 |

**按需 Skill：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-payments` | ✅ | ✅ 已读 | 争议域既有事实/入账/对账段落（P7-1..3）确定本切片的只读边界与命名纪律 |
| `pallastrade-testing` | ✅ | ✅ 已读 | rspec 容器内执行；断言型用例优于注释（本切片用「禁推导」「零调用」显式断言） |
| `pallastrade-events-webhooks` | ⬜ 否 | — | 本切片无事件/subscriber |
| `pallastrade-api-v3` | ⬜ 否 | — | 无 API 变更 |

---

## 需求标题

DSP-P7-4：争议**证据快照**（确定性只读投影，不可得即显式 `not_available`，禁止推导）。

## 任务类型

新功能（只读服务 + VO；0 migration、0 API/UI）。

## 需求描述

把既有事实（订单/交易/支付/退款/发货/账本/对账/可选 provider 只读快照）投影为一张**可审阅的证据卡**，
每段显式标注 `availability` + `reason`；`delivered_at` 与客户沟通一律 `not_available`（源计划 §42 禁推导），
`missing_evidence[]` 供 P7-5/P7-6/P7-7 使用，`submission_ready` 恒 false（不提交证据）。范围与 AC 见 PRD §3/§5。

**范围外**：Deadline/Sweeper（P7-5）、Recovery 收敛（P7-6）、Admin Console（P7-7）、证据提交/多 provider 证据类型（P7-8）、快照持久化。

## 验证方案（AC ↔ 命令）

| AC | 命令/证据 |
|---|---|
| AC-P74-01..11 | `docker exec pallastrade-web-1 bash -lc "cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/services/pallastrade/disputes/build_evidence_snapshot_spec.rb"` |
| AC-P74-12 | 注册 verifier `backend-rspec`（全量）；`harness generated:check`；`harness doc-impact --base origin/dev` |

## 用户确认

| 项 | 状态 |
|---|---|
| PRD 已呈现 | ✅ 2026-09-12 已呈现（三条铁律 + 分段清单 + 规模 + 范围外） |
| 用户确认 | ✅ **已确认**（2026-09-12 问答工具『确认实施 P7-4』）；批准证据 EVD-20260912130127-b67e613eef |
