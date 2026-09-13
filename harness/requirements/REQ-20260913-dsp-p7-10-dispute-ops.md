# REQ-20260913-dsp-p7-10 — 争议本地运营增强 B1（素材库 / 提交前校验 / 版本回执）

| 字段 | 值 |
|---|---|
| 任务 | TASK-20260913110421-028cb0f6（gate `GATE-2026-09-13T11-16-21`，type=feature，risk=critical） |
| PRD | `docs/prd/payments/PRD-20260913-payments-争议本地运营增强与-stripe-深化-规格-68-边界-c-证据素材库-提交前校验-证据版本回执-审批复核-运营报表-.md`（approved） |
| 上游决策 | `docs/research/RESEARCH-20260913-p7-spec68-advanced-dispute-boundary-options.md` → **D1=B/C、D2=C、D3=否** |
| 本批范围 | **B1**（FR-001 / FR-003 / FR-004；FR-002 与 FR-010 为贯穿性约束） |
| 用户确认 | 用户明确指令「**实施**」（2026-09-13），对应 PRD 的 B1 交付批次 |

## 1. 目标与非目标

- **目标**：在不依赖 provider 凭据、不触碰规格 §71 禁区的前提下，补齐争议**运营侧**三件事：
  1. **证据素材库**（FR-001）：可复用的文本/文件素材，**只读引用**；
  2. **提交前完整性/合规校验**（FR-003）：提交**前**给出阻断项与修复建议，**零写**；
  3. **证据版本与回执追踪**（FR-004）：append-only 提交历史 + 版本对比 + provider 回执。
- **非目标（本批明确不做）**：自动提交/自动抗辩/自动退款/自动补货/自动再收款（§71）；不新增对外 API；不改 `Dispute#state` 机；
  不改账本语义（`FinancialFact::FACT_TYPES` / `FinancialLedgerEntry::ENTRY_TYPES` 冻结词汇不动）。
- **硬约束**：`PallasTrade::Disputes::SubmitEvidence` 仍是**唯一**提交入口，且仍需显式确认（permission + confirmation + audit 三件套）。

## 2. Step 0 — 六层跨层搜索结果（先搜索，再决策）

| 层 | 路径 | 关键词 | 命中 | 是否已满足 |
|---|---|---|---|---|
| App | `backend/app/` | dispute / evidence | 无争议域业务代码（本仓约定：域代码在 gem 内） | ❌ |
| Core | `backend/pallastrade_gems/pallastrade_core/app/` | `disputes` | **15 个服务**：`submit_evidence` `evidence_catalog` `build_evidence_snapshot` `evidence_snapshot` `resolve_fact` `handle_provider_event` `recover` `scan_deadlines` `scan_recovery_candidates` `accept_dispute` `capture_fee` `mark_manual_review` `payment_dispute_summary` `provider_payload` `dispute_fact`；模型 `dispute.rb` `dispute_evidence_submission.rb` | ⚠️ 部分：已有**字段级**校验（`EvidenceCatalog#validate`）与**不可变回执**，缺素材库 / 提交前编排校验 / 时间线 |
| API | `backend/pallastrade_gems/pallastrade_api/app/` | dispute | 无端点（本批不新增） | ❌（不需要） |
| Admin | `backend/pallastrade_gems/pallastrade_admin/app/` | `disputes_ops` | `disputes_ops_controller.rb`（含危险操作三件套 + 只读降级范式）、`disputes_ops_helper.rb`、`show.html.erb` | ⚠️ 部分：危险操作区已有，缺素材插入 / 预检展示 / 时间线 |
| Storefront | `storefront/src/` | dispute | 无（客户侧不涉及争议） | ❌（不需要） |
| Platform | `platform/packages/` | dispute / evidence | 无 | ❌（不需要） |

**结论**：本批为**纯增量**，无重复实现风险；`EvidenceCatalog` 作为唯一字段校验权威被**复用**（不复制校验逻辑）。

## 3. Skill Consultation Evidence（R2 — 逐格真实结论）

| Skill | 真实结论（对本次实现的具体影响） |
|---|---|
| `pallastrade-customization` | 三层优先级判定：素材库属**新增域模型**（在 `pallastrade_core` gem 内新表 + 服务），无需 decorator / 无需宿主 `backend/app` 覆盖；沿用既有 `PallasTrade.base_class` + `has_prefix_id` 范式。 |
| `pallastrade-payments`（domain） | 争议域既有常量与铁律：`DisputeEvidenceSubmission` **append-only 不可变**（`before_update` + `update_columns` 双拦）、**无金额列**、`(dispute_id, kind, payload_digest)` 唯一幂等；`DSP-P7-8` 危险操作三件套（permission/confirmation/audit）；本次所有新代码必须遵守「零资金副作用 + 不改 `Dispute#state`」。 |
| `pallastrade-prd` | 交付物必须回填 PRD、更新 `docs/prd/README.md` 索引、跑 `prd-status-sync --check`、AC↔测试标记须写**完整 PRD-ID + AC 号同行**。 |
| `pallastrade-data-model` | 新表须 store 作用域、`prefixed_id` 前缀 `dea`、迁移只新增不修改历史迁移、`schema.rb` 不手改。 |
| `pallastrade-admin` | 控制台页面铁律：面包屑三要素（标题/面包屑/图标）、Turbo `data-turbo-method`、只读在线调用**逐个降级**（页面恒 200）。 |
| `pallastrade-testing` | 新行为必配 spec；预算友好用定向 spec 文件；负向断言（表计数不变）作为「零写」证据。 |

## 4. 功能需求（B1）

| # | 需求 | 关键约束 |
|---|---|---|
| FR-001 | 证据素材库：`DisputeEvidenceAsset` 支持 `text` / `file` 两类素材，按 store 作用域、可按 reason code 与 provider 证据键归类；`EvidenceAssets` 服务提供 list/create/retire/insert（插入=返回 `{key,value}` 纯值，**不提交**） | 只读引用；不触网；不建回执 |
| FR-003 | `PreSubmitCheck`：在**不提交**的前提下给出 `blocking[]` / `warnings[]` / `missing_required[]` / `unsupported` / `late` / `fix_hints` | **零写**（含零审计、零事件）；复用 `EvidenceCatalog` |
| FR-004 | `SubmissionTimeline`：append-only 回执的时间线 + 每次提交的 `version` 与相对上一版的 `diff`（added/removed/changed） | 只读；不改写回执 |
| FR-010 | 负向约束：以上三者**任何路径**不得产生资金/库存/订单/账本写入 | 由 spec 断言表计数不变 |

## 5. 验收标准 → 测试映射

| AC | 断言 | 测试 |
|---|---|---|
| AC-001 | 素材可入库 / 可停用 / 可被引用；引用后不产生提交（回执计数不变） | `spec/services/pallastrade/disputes/evidence_assets_spec.rb` |
| AC-003 | 缺必填 / 超期 / 未知键 / 不支持 provider → 各自可辨识阻断码；全满足 → `ok?` | `spec/services/pallastrade/disputes/pre_submit_check_spec.rb` |
| AC-004 | 时间线按时间可列、version 递增、diff 正确；重放不新增记录 | `spec/services/pallastrade/disputes/submission_timeline_spec.rb` |
| AC-002（贯穿） | 无契约 provider → `UNSUPPORTED` 且不编造建议 | B1 各 spec 内断言 |
| AC-010（贯穿） | 全片断言零资金/库存/订单写 | 每个 spec 末尾表计数断言 |

## 6. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 新增表触碰 critical 风险判定 | 迁移仅新增表；`recovery create` 建人工回滚计划（drop 新表 / revert commit） |
| 与既有 `EvidenceCatalog` 校验漂移 | 预检**复用** catalog，不复制字段规则 |
| 素材库被误当作「自动提交」通道 | 服务层不持有 provider 句柄；`insert` 仅返回纯值；spec 断言零回执 |
