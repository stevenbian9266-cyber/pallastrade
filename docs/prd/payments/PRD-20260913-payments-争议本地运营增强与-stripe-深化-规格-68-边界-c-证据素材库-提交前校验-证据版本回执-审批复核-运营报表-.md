# PRD-20260913-payments-争议本地运营增强与-stripe-深化-规格-68-边界-c-证据素材库-提交前校验-证据版本回执-审批复核-运营报表-

| 元数据 | 值 |
|---|---|
| 状态 | done（B1 / B1.5 / B2 / B3 **全部交付**；边界 C 收口） |
| 创建日期 | 2026-09-13 |
| 来源 | 优化：争议本地运营增强与 Stripe 深化（规格 §68 边界 C：证据素材库/提交前校验/证据版本回执/审批复核/运营报表/通知升级/RMA 联动） |
| 分类 | payments（自动判定） |
| 关联 Skill | `pallastrade-payments` / `pallastrade-data-model` / `pallastrade-admin` / `pallastrade-events-webhooks` / `pallastrade-testing` |
| 关联 REQ | REQ-20260913-dsp-p7-10-dispute-ops.md（实施时回填） |
| 关联 PRD | 上游：DSP-P7-4（证据快照）/ DSP-P7-5（期限扫描）/ DSP-P7-7（控制台）/ DSP-P7-8（证据提交与危险操作）/ DSP-P7-9（边界 C 语义）；本文件定义 §68 第 5 条的**剩余边界** |
| 需求类型 | 优化迭代（图 §68 边界 C 落地；**零资金自动化**） |

## 1. 背景与目标

- **一句话需求原文**：优化：争议本地运营增强与 Stripe 深化（规格 §68 边界 C）
- **背景**：
  1. 源规格 §68「DSP-P7-8 — Provider Expansion」列 5 条，先决条件为 `sandbox credential + provider contract + real E2E`；本次核实：**evidence submission**（P7-8）与 **provider-specific evidence types**（Stripe 文本/文件键 + 能力矩阵）**已完成**；**Adyen/PayPal 因缺凭据挂起（用户已确认不处理）**；**第 5 条 advanced dispute capabilities 边界从未定义**。
  2. 规格 §71「明确不做」21 条中 **6 条**正是争议自动化方向（Auto Representment / AI 生成证据 / 自动退款 / 自动补货 / 自动再收款 / EFW 工作流）→ 任何自动化都需先改规格，本片 **不做**。
  3. 落地现状：P7-9 已交付边界 C（partial 语义 / 同一 payment 多争议 / 争议手续费闭环 / provider 能力矩阵）；运营侧仍靠人工翻查，缺素材库、缺提交前校验、缺报表。
- **目标**：在不依赖任何 provider 凭据、不触碰 §71 禁区的前提下，把争议**运营**能力补到「可日常使用」水平；并借 Stripe 现有测试模式做真实 E2E。
- **成功指标**：① 每项能力都有「零资金/库存/订单写」负向断言且测试锁死；② dev 上无需凭据即可端到端演示；③ `SubmitEvidence` 仍是唯一提交入口且需显式确认。

## 2. 用户故事 / 场景

- 作为**争议运营**，我希望有可复用的证据**素材**与按 reason code 的**建议字段**，以便快速准备材料，同时**不担心系统替我提交**。
- 作为**运营负责人**，我希望提交前能有**完整性/合规校验**与**双人复核**，以便避免因漏字段/超期而丢单。
- 作为**财务**，我希望看到**胜诉率/时限达成/处理时长**等只读报表，以便评估争议处理质量。
- 场景：① 新建证据草稿 → 从素材库插入 → 校验通过 → 人工确认提交；② 校验不通过 → 给出阻断项与修复建议；③ 提交后回执状态回写（submitted/acknowledged/rejected）；④ 期限临近 → 通知升级；⑤ 争议详情 → 跳转创建退货单（人工）；⑥ mixed currency / 无 payment 锚点 → 报表降级不报错。
- 边界：无 provider 凭据时，Stripe 深化能力仍可在测试模式验证；Adyen/PayPal 一律 `UNSUPPORTED`，不崩不猜。

## 3. 功能需求（FR）

- FR-001 **证据素材库（只读引用）**：文本/文件素材可分类入库；证据草稿中只能**人工插入引用**，素材与草稿分离。
- FR-002 **按 reason code 的证据模板与建议字段**：启动于 provider 能力矩阵（有契约才给建议），**只提示**「建议填什么」与「可插入哪些素材」。
- FR-003 **提交前完整性/合规校验**：必填字段、文件类型/大小、期限、能力矩阵支持度；给出**阻断项**与修复建议。
- FR-004 **证据版本与回执追踪**：以 `DisputeEvidenceSubmission`（append-only）为基础，展示历史提交、provider 回执与版本对比。
- FR-005 **审批/双人复核工作流**：危险操作（提交/接受争议）支持二次确认与留痕（人/时/理由）。
- FR-006 **争议运营报表（只读）**：胜诉率、按 reason code 分布、时限达成率、平均处理时长；mixed currency / 无锚点时降级。
- FR-007 **通知与期限升级提醒**：期限临近/超期/状态变更的通知（不代替人决策）。
- FR-008 **RMA 联动入口**：争议详情页提供「创建退货/补货单」入口（**人工触发**；库存与订单仍走原有显式流程）。
- FR-009 **（Stripe 深化）提交回执状态机**：submitted → acknowledged / rejected（provider 回写驱动）。
- FR-010 **负向约束**：本片任何路径**不得**自动提交证据、自动抗辩、自动退款、自动补货、自动再收款（与 §71 一致）。

## 4. 非功能需求（NFR）

- **零资金自动化**：本片不新增任何资金/库存/订单写动作；报表与投影全部**只读**。
- **不扩展账本语义**：不改 `FinancialFact::FACT_TYPES` / `FinancialLedgerEntry::ENTRY_TYPES`。
- **降级**：无契约 provider 一律 `UNSUPPORTED`；数据缺失（无 payment 锚点/mixed currency）时逐项 rescue → `unavailable`，页面绝不 500。
- **幂等/可重放**：校验、通知、报表均幂等；素材入库重复名称不报错。
- **兼容**：`SubmitEvidence` 仍为唯一提交入口；既有控制台断言不回退。
- **可测**：每项能力至少一条「不做 X」负向断言。

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：素材可入库与引用；引用不改变证据内容；不产生任何提交。
- AC-002 ← FR-002：有契约 provider 给出建议字段；无契约返回 `UNSUPPORTED` 且不生造建议。
- AC-003 ← FR-003：缺必填/超期/类型不支持各自返回可辨识阻断码；全部满足时校验通过。
- AC-004 ← FR-004：提交历史按时间可列；回执状态可回写；重放不产生重复记录。
- AC-005 ← FR-005：未复核直接提交被阻断；复核后提交成功且留下审计（人/时/理由）。
- AC-006 ← FR-006：报表在正常、mixed currency、无 payment 锚点三种输入下均不报错（降级）。
- AC-007 ← FR-007：期限临近仅产生通知，**不产生任何自动动作**。
- AC-008 ← FR-008：入口存在但跳转后仍走原有退货流程；争议侧不直接写库存/订单。
- AC-009 ← FR-009：submitted → acknowledged / rejected 状态推进正确且单向（禁回退）。
- AC-010 ← FR-010（负向，锁死禁区）：全片测试中断言无自动提交/自动抗辩/自动退款/自动补货/自动再收款。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | dispute / evidence | 无争议域代码（约定：域代码在 gem） | 否 |
| Core | `pallastrade_core/app/` | `disputes` | **15 个服务**（`handle_provider_event`/`resolve_fact`/`build_evidence_snapshot`/`scan_deadlines`/`recover`/`submit_evidence`/`accept_dispute`/`capture_fee`/`payment_dispute_summary`…）+ `Dispute` / `DisputeEvidenceSubmission` 模型 | **部分（缺素材库/校验/复核/报表）** |
| API | `pallastrade_api/app/` | dispute | 无对外端点（本片不新增） | 否 |
| Admin | `pallastrade_admin/app/` | `disputes_ops` | `disputes_ops_controller` + `show.html.erb`（能力矩阵 + payment 张敞 + 危险操作三件套） | **部分（控制台已有，需扩展）** |
| Storefront | `storefront/src/` | dispute | 无（客户侧不涉及争议） | 否 |
| Platform | `platform/packages/` | dispute | 无 | 否 |

**结论**：争议域**已具备**事件入口/事实裁决/账本/对账/期限/收敛/控制台/证据提交能力；本片为**纯增量**（素材库、校验、复核、报表、通知、RMA 入口、回执状态机），无重复实现风险。

## 7. 技术影响

- 新增 core 服务：`Disputes::EvidenceAssets`（素材库 CRUD 只读引用）、`Disputes::PreSubmitCheck`、`Disputes::SubmissionTimeline`、`Disputes::OpsReport`；订阅者：期限通知。
- 新增迁移：证据素材表、提交回执字段（基于既有 `DisputeEvidenceSubmission` 扩展）；扩展 `disputes_ops/show` 视图与控制器 action。
- 不改：`FinancialFact` / `FinancialLedgerEntry` / `Reconciliations::*` / `Transactions::*` / 任何资金路径。
- 交付分批：**B1** 素材库 + 提交前校验 + 版本回执（本片先做）；**B2** 复核流 + 通知；**B3** 报表 + RMA 入口 + Stripe 回执状态机。

## 8. 测试计划

- 新增：`spec/services/pallastrade/disputes/evidence_assets_spec.rb`、`pre_submit_check_spec.rb`、`submission_timeline_spec.rb`；`spec/requests/.../disputes_ops_*_spec.rb`（控制器路径）。
- 修改：既有 disputes 回归套件（确保 `SubmitEvidence` 唯一入口不被绕过）。
- AC 映射：AC-001/003/004 → B1 测试；AC-005/007 → B2；AC-006/008/009 → B3；AC-002/010 为贯穿性断言（每批均跑）。

## 9. 文档同步清单（知识同步门）

- [x] 不涉及 API 文档（本片不新增对外端点）
- [x] Skill 文档：`ai/skills/pallastrade-payments/SKILL.md`（新增 DSP-P7-10 节）
- [x] `harness/scenarios/scenarios.json`（新增 Eval 场景：争议运营增强不越界）
- [x] `docs/prd/README.md` 索引（本 PRD 自身）
- [x] 本 PRD 状态更新 + 收口报告 §5-2 「解除条件」回填

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-13 | 0.1 | 初稿。**边界决策记录**：用户 2026-09-13 授权「自主采取最优方案」→ AI 采纳 `RESEARCH-20260913-p7-spec68-advanced-dispute-boundary-options.md` 的**方案 C**（D1=B/C、D2=C、D3=否，即不修订 §71、不做任何自动化），分 B1/B2/B3 三批交付 | AI |
| 2026-09-13 | 0.2 | **B1 交付**（用户指令「实施」）：新增表 `pallastrade_dispute_evidence_assets` + 模型 `DisputeEvidenceAsset` + 服务 `Disputes::EvidenceAssets` / `Disputes::PreSubmitCheck` / `Disputes::SubmissionTimeline`；spec 3 个文件 20 例全绿（AC-001/002/003/004/010）；Skill §DSP-P7-10 B1 + 场景库 GS-104 同步。**未做**：控制台渲染（B1.5）、FR-005…009（B2/B3） | AI |
| 2026-09-13 | 0.3 | **B1.5 交付**（用户指令「自主完成全部决策，直接实施」）：控制台接线 —— `show` 新增只读**提交历史卡**（版本/回执/证据键 diff）与**素材库·建议卡**；`member post :precheck` 草稿校验动作（零写：不建回执/不写审计/不调 provider）；危险操作表单新增「Check draft」按钮（`formaction` 复用同一张表单，无字段重复）；en.yml 新增 14 个键；新 spec `disputes_ops_evidence_ops_spec.rb` 9 例 + 全套 35 例全绿；Skill §边界行更新 | AI |
| 2026-09-13 | 0.4 | **B2（FR-006 运营报表）交付**（用户指令「继续」）：新增只读服务 `Disputes::OpsReport`（口径写死：win_rate=won/(won+lost)、met_rate=截止前提交、处理时长=resolved_at−created_at；状态取 `Dispute::TERMINAL_STATES`）；**降级不猜**（mixed currency → 金额置 nil；异常 → 降级信封）；`/admin/disputes` 列表页新增报表卡（`safe_value` 包裹，异常不 500）+ en.yml 8 键；spec `ops_report_spec.rb` 9 例 + `disputes_ops_report_spec.rb` 3 例；争议域全套 **152 例全绿**。**未做**：FR-005 双人复核（需改危险提交路径，单独切片）、FR-007 通知升级、B3（RMA / Stripe 回执状态机） | AI |
| 2026-09-13 | 0.5 | **B2（FR-005 双人复核）交付**（用户指令「继续」）：新表 `pallastrade_dispute_evidence_approvals`（`dap_`，append-only，无金额列）+ 服务 `Disputes::ApproveEvidenceDraft`（签核绑定载荷摘要；自批自被拒；幂等；审计 approved/rejected）；`SubmitEvidence` 新增 `require_approval:`（**默认 false，既有行为不变**）→ 缺签核 `evidence_review_required`、同人签发 `approval_requires_different_operator`，通过后 `approval_id` 入回执与审计；控制台新增 Approve draft（第二人）按钮（`formaction` 复用同一表单）+ 签核列表；开关 `PallasTrade::Config[:dispute_evidence_requires_second_review]`；spec `approve_evidence_draft_spec.rb` 9 例；争议域全套 **183 例全绿** | AI |
| 2026-09-13 | 0.6 | **B2（FR-007 期限提醒与升级）交付**（用户指令「继续」）：新增订阅者 `Disputes::DeadlineAlertSubscriber`（消费 sweeper 已发布的 `dispute.evidence_due_soon` / `dispute.evidence_overdue`）；`due_soon` 只留痕（审计 + 指标），`overdue` 在 `attention_reason` 为空时升级为新增词表值 `evidence_overdue`（**不覆盖**更具体原因），该值同时进入 `Attentions` 与运营报表 `needs_attention`；engine.rb 注册；spec 7 例 + sweeper 回归 5 例全绿；Skill § 提醒升级节 + GS-108 | AI |
| 2026-09-13 | 0.7 | **B3（FR-009 回执状态机）交付**（用户指令「继续」）：新增只读服务 `Disputes::ReceiptStatus`（**派生不落表** —— 回执 append-only 不可改写）：`submitted → acknowledged → rejected` 单向，信号取 provider 回写（争议推进到 `under_review` / 回执回 `under_review` / `invalid_transition` + 状态回到 `needs_response`），冲突或缺失 → `unknown`/`no_receipt`（不猜）；单调性由状态机拒绝倒退 + attention 不被覆盖保证；`SubmissionTimeline` 输出新增 `receipt:` 字段 + 时间线卡徽章 + en.yml 6 键；spec 9 例 + 时间线回归 5 例全绿；SKILL §回执状态机节 + GS-109 | AI |
| 2026-09-13 | 0.8 | **B3（FR-008 退货/补货人工入口）交付 → 本 PRD 收口（done）**：争议详情页新增只读卡「Returns / restock (manual)」，经既有 `parent_order_returns_admin_order_path(order)` 跳转订单域既有售后流程（**只跳转**：争议侧零库存写、零自动补货）；无锚点订单时显式提示而非隐藏入口；en.yml 4 键；spec 3 例（链接存在 / 无订单提示 / 渲染零写）；**争议域全套 232 例全绿**；SKILL § 入口节 + GS-110。**边界 C 完整交付**：素材库、提交前校验、版本回执、运营报表、双人复核、期限提醒升级、回执状态机、RMA 入口；全程零资金/库存/订单自动化（§71 未动），Adyen/PayPal 按用户决议挂起 | AI |
