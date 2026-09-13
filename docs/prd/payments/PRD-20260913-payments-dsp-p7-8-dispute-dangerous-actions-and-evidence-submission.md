# PRD-20260913-payments-dsp-p7-8-dispute-dangerous-actions-and-evidence-submission（争议危险操作与证据提交）

| 元数据 | 值 |
|---|---|
| 状态 | done（2026-09-13 收口：TASK-20260913033838-fe7f725c gate finished） |
| 创建日期 | 2026-09-13 |
| 来源 | 新增：DSP-P7-8 争议危险操作与证据提交（Accept Dispute / Submit Evidence，Stripe 先行） |
| 分类 | payments（关键词命中 payments） |
| 关联 Skill | `ai/skills/pallastrade-payments/SKILL.md`（+ `pallastrade-admin`、`pallastrade-security`、`pallastrade-events-webhooks`） |
| 关联 REQ | REQ-20260913-dsp-p7-8-...（gate 时回填） |
| 关联 PRD | N/A（P7-4 是**只读**证据快照投影，本片是**写**路径与 provider 危险操作，能力不同；查重命中 32% 已评估为关键词「证据」重合） |
| 需求类型 | 新功能 |

## 1. 背景与目标

- **一句话需求原文**：`新增：DSP-P7-8 争议危险操作与证据提交（Accept Dispute / Submit Evidence，Stripe 先行）`
- **背景**：DSP-P7 线已完成 P7-1…P7-7（事件接入 → 事实裁决 → 资金入账/对账 → 证据快照 → 期限告警 → 收敛 → 运营控制台）。
  P7-7 控制台的 5 个动作**全部是安全动作**，并在实现中用负向断言把两个危险动作钉在门外
  （源计划 §67：`Accept Dispute` / `Submit Evidence` 若实现，**必须** `permission + confirmation + audit`）。
  源计划 §68 把 P7-8 定为 **Provider Expansion**（Adyen / PayPal / evidence submission / provider-specific
  evidence types / advanced dispute capabilities），并给出前置条件：**sandbox credential + provider contract + real E2E**。
  现状核查：dev 店铺已配置 `PallasTradeStripe::Gateway`（`pk_test_` / `sk_test_`，test 模式）→ **Stripe 侧前置条件满足**；
  Adyen / PayPal 尚无合同与凭证 → 二选一：等凭证，或先把可用 provider 的危险操作做扎实。
- **目标**：
  1. 在**现有 provider（Stripe）**上落地争议危险操作的**写路径**：证据提交（Submit Evidence）与接受争议（Accept Dispute）；
  2. 把 provider 交互抽成 **capability-gated 写契约**（基类 `NotImplementedError` + 类级 owner 检测，沿用
     `fetch_dispute_details` 既有范式），使未来 provider 只需实现契约即可接入（**本片不实现 Adyen/PayPal 适配器**）；
  3. 三件套强制：`permission`（CanCanCan）+ `confirmation`（不可逆二次确认）+ `audit`（`PallasTrade::Audit` + 事件）；
  4. 铁律不变：**webhook 仍是资金事实的权威** —— 提交证据/接受争议**不得**直接改 Payment / Refund / FinancialLedger /
     Order / Inventory / CommerceTransaction。
- **成功指标**（可量化）：
  - 危险动作在无权限账号下**不可见且不可执行**（请求级 403/404，负向断言）；
  - 每次提交产生 1 条 durable 回执（含 provider 引用、payload 摘要、actor、时间）且审计 1 条；
  - 同一 payload 重复提交**不产生**第二次 provider 调用（幂等）；
  - provider 不支持时页面显示"该网关不支持"，零 500；
  - 全量 `backend-rspec` 与定向 specs 全绿；无新 migration 的情况下 0 DDL 风险（见 §7 的取舍）。

## 2. 用户故事 / 场景

- 作为**运营/客服**，我希望在证据截止前把交付证明（物流单号、签收证明、客户沟通记录等）提交给 provider，以便争议能被判我方胜诉。
- 作为**运营主管**，我希望"接受争议"（放弃抗辩、认赔）是一个**必须二次确认**且留痕的动作，以便审计谁在何时做了这个不可逆决定。
- 作为**审计/合规**，我希望每一次向 provider 的写操作都有 durable 回执与审计记录（actor / 时间 / payload 摘要 / provider 响应状态）。
- 作为**开发者**，我希望新 provider 接入只需实现一个写契约 + 一份证据类型目录，不需要改核心编排。
- **场景**：
  1. 正常流：`needs_response` → 运营打开控制台 → 提交证据（文本字段 + 可选文件）→ provider 返回 `under_review` → 本地回执落库 + 审计 + 事件；
  2. 边界：已超 `evidence_due_at` → 拒绝（或要求二次确认，取决于 §6 决策项）；
  3. 边界：provider 不支持写契约（如 `Bogus`）→ 按钮禁用 + 明确原因，请求 422 而非 500；
  4. 异常：provider 网络失败 → 明确错误 + 指引重试（不产生半成品回执）；
  5. 危险：`Accept Dispute` 不可逆 → 二次确认文案含"不可撤销"，执行后审计 + 事件，本地状态仍由后续 webhook/收敛推进；
  6. 越权：无 `:update` 权限账号 → 按钮不可见，直接 POST 被 403。

## 3. 功能需求（FR）

- FR-001：**provider 写契约（capability-gated）**——`PallasTrade::PaymentMethod#submit_dispute_evidence(dispute:, evidence:)` 与
  `#accept_dispute(dispute:)`：基类 `raise NotImplementedError`；能力检测沿用**类级 method owner != 基类**（零 I/O，不受 RSpec 打桩干扰）。
- FR-002：**provider 证据类型目录**——每个 provider 声明支持的证据键（Stripe：`customer_name` / `customer_email_address` /
  `product_description` / `uncategorized_text` / `shipping_documentation` / `receipt` …）+ 每键的必填/可选与类型（文本 / 文件引用）；
  未知键拒绝；目录用于控制台渲染与提交校验。
- FR-003：**提交编排** `Disputes::SubmitEvidence.call(dispute:, evidence:, actor:)` —— 前置校验（provider 引用存在、未终态、
  未超期〔按策略〕、payload 合法）→ 调 provider 写 → 落 **durable 回执** → `PallasTrade::Audit.record` → 发事件；重复提交同一 payload → 幂等返回既有回执。
- FR-004：**接受争议** `Disputes::AcceptDispute.call(dispute:, actor:, reason:)` —— 不可逆语义，要求显式 reason；同样落回执 + 审计 + 事件。
- FR-005：**控制台危险动作**——在 P7-7 的 `/admin/disputes/:id` 增加 `submit_evidence` / `accept_dispute`（POST）：
  仅 `can?(:update, PallasTrade::Dispute)` 可见；`turbo_confirm` 二次确认（接受争议文案含"不可撤销"）；
  provider 不支持时禁用并展示原因。
- FR-006：**截止守护**——`evidence_due_at` 之后提交按 §6 决策项处理（默认：允许但需二次确认 + 审计标注 `late: true`）。
- FR-007：**事件**——`dispute.evidence_submitted` / `dispute.accepted`（供订阅者、审计、指标）。
- FR-008：**负向铁律**——不建/改 Payment、Refund、`FinancialLedgerEntry`、Order、Inventory、CommerceTransaction；
  不自动退款、不重扣款；仅 provider 写 + 本地回执/审计/事件。

## 4. 非功能需求（NFR）

- **安全**：三件套（permission + confirmation + audit）不可绕过；provider 写路径只在服务内可达（控制器不直接调网关）；
  不回显任何密钥；日志与事件不落敏感 payload 全文（只落摘要）。
- **兼容**：非 Stripe 网关（`Bogus` / Check / StoreCredit）零行为变化；无 dispute 的店铺零影响；P7-1…P7-7 行为逐字节不变。
- **可维护**：能力检测零 I/O；新 provider = 实现 2 个契约方法 + 1 份证据目录 + specs。
- **可观测**：回执表可查询；审计 `action` 名稳定（`dispute_evidence_submitted` / `dispute_accepted`）；事件名稳定。

## 5. 验收标准（AC，与测试一一映射）

- AC-P78-01 ← FR-001：基类两个写契约存在且 `NotImplementedError`；Stripe 网关 owner ≠ 基类（能力可检测）。
- AC-P78-02 ← FR-002：目录返回 Stripe 支持键集合；未知键提交被拒（422），且**不触发** provider 调用。
- AC-P78-03 ← FR-003：成功提交 → 回执 1 条（provider 引用 + payload 摘要 + actor + at）+ 审计 1 条 + 事件 1 次。
- AC-P78-04 ← FR-003：同一 payload 重复提交 → 幂等（provider 只被调用 1 次，回执不新增）。
- AC-P78-05 ← FR-003：provider 抛错 → 服务返回 failure，**无**回执落库（或落 failed 回执，按 §6 决策），无异常冒泡到页面。
- AC-P78-06 ← FR-004：接受争议 → 回执 + 审计 + 事件；响应体**不含**资金字段；本地 state 未被直接改写为终态（由 webhook/收敛推进）。
- AC-P78-07 ← FR-004：非法/缺失 reason → 拒绝（422）。
- AC-P78-08 ← FR-005：有权限账号可见两个按钮；无权限账号不可见且 POST 被 403。
- AC-P78-09 ← FR-005：provider 不支持 → 按钮禁用 + 页面文案说明；直接 POST → 422（非 500）。
- AC-P78-10 ← FR-006：超过 `evidence_due_at` 的提交按策略执行并在审计标注 `late: true`。
- AC-P78-11 ← FR-007：两个事件在成功路径各发布一次，失败路径不发布。
- AC-P78-12 ← FR-008：负向断言——提交/接受前后 Payment/Refund/Ledger/Order/Inventory/CommerceTransaction 计数与金额不变。
- AC-P78-13 ← 全局：控制台不新增除这两个动作外的路由（尤其**无**自动化批量提交、无"批量接受"）。
- AC-P78-14 ← 全局：注册 verifier `backend-rspec` 全量绿 + `generated:check` 无漂移 + `doc-impact` 同步。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | `dispute` / `evidence` | **无命中** | ❌ 需新建于 gem（沿用 P7 线约定） |
| Core | `pallastrade_gems/pallastrade_core/app/` | `submit_dispute` / `accept_dispute` / `evidence_types` | 仅 `payment_method.rb:167 fetch_dispute_details`（**只读**契约） | ❌ 写契约需新增 |
| API | `pallastrade_gems/pallastrade_api/app/` | `dispute` | **无命中**（P7-7 亦为 Admin HTML 路由） | ✅ 不适用（本片不做 API v3 端点） |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | `disputes_ops` | P7-7 `disputes_ops_controller.rb`（5 个安全动作）+ helper + 2 views + tables 注册 | ⚠️ 需**扩展**（+2 危险动作），复用既有 `authorize_admin` / `load_dispute` 范式 |
| Storefront | `storefront/src/` | `dispute` | **无命中** | ✅ 不适用 |
| Platform | `platform/packages/` | `dispute` | **无命中** | ✅ 不适用（无 SDK 变更） |
| 附加（provider 适配） | `pallastrade_gems/pallastrade_stripe/app/models/pallastrade_stripe/gateway.rb` | `fetch_dispute_details` | P7-2 只读实现（`retrieve_dispute` + 归一化快照） | ⚠️ 需新增写实现（`Stripe::Dispute.update` / `close`） |

**结论**：本片是**新增写路径**，无既有能力可复用（只读契约与快照是**输入**而非提交能力）；
Admin 层是**扩展**而非新建（P7-7 控制台已就位）；**不涉及** API v3、Storefront、Platform、多店铺。

**⚠️ 用户决策（2026-09-13 已确认，实施依据）**：
1. **范围**：**(A) 仅 Stripe 危险操作**（dev 凭证已具备，可做真实 E2E）；Adyen/PayPal 适配与合同谈判**延后**至凭证齐备。
2. **证据形态**：**含文件上传**（Stripe `File` 上传 + ActiveStorage 存储）；文本字段与文件字段同表返回。
3. **逾期提交**：**允许 + 二次确认 + 审计标注 `late: true`**。
4. **回执存储**：**新建不可变表** `pallastrade_dispute_evidence_submissions`（append-only）。
5. 用户已明确确认实施（问答工具，非模糊同意）。

## 7. 技术影响

- **新增（core）**：`PallasTrade::Disputes::SubmitEvidence`、`PallasTrade::Disputes::AcceptDispute`、
  `PallasTrade::Disputes::EvidenceCatalog`（provider 证据类型目录 + 校验）。
- **新增（core 契约）**：`PaymentMethod#submit_dispute_evidence` / `#accept_dispute`（基类 `NotImplementedError`）+ 能力探测方法。
- **新增（stripe 适配）**：`PallasTradeStripe::Gateway#submit_dispute_evidence` / `#accept_dispute`（`Stripe::Dispute.update` / `close`；
  归一化回执：provider 引用 / status / submitted_at / 接受或拒绝原因）。
- **扩展（admin）**：`disputes_ops_controller.rb`（+2 action）、`show.html.erb`（危险区 + 确认文案）、
  locales（en + zh-CN 双份）、helper（按钮可用性/降级原因）。
- **数据**：新增 1 张**不可变表** `pallastrade_dispute_evidence_submissions`（append-only：dispute_id / kind / payload_digest / provider_reference /
  provider_status / actor_type / actor_id / actor_label / late / accepted_reason / response_metadata(jsonb) / created_at）+ 1 个 migration（`pallastrade_core/db/migrate/`）；
  **不**修改既有表；**不动** `Dispute#state` / 资金字段（状态仍由 webhook/收敛推进）。
- **文件证据**（用户确认纳入）：控制台表单支持文件字段 → ActiveStorage 附件（`has_many_attached` 或显式 blob 引用）→ 网关内
  `Stripe::File.create({ purpose: 'dispute_evidence', file: … })` → 把返回的 `file_…` 引用写入 `Stripe::Dispute.update(evidence: { <key>: 'file_…' })`；
  文件大小/类型白名单（与 Stripe 限制对齐）+ 上传失败不回滚已提交文本字段（分段提交 + 回执记录每段结果）。
- **权限**：写动作沿用 `:update`（当前仅 `order_management` 的 `modify` 覆盖）；新增更细粒度可选（`dispute_accept` 独立权限）→ 待决策。
- **事件**：`dispute.evidence_submitted` / `dispute.accepted`（events Skill 登记）。
- **接口**：Admin HTML 路由（非 API v3）→ **无** OpenAPI/SDK 变更；`generated:check` 应无漂移。
- **回滚**：删路由 + 控制器 action 即停用（provider 侧已发生的写不可撤销，属业务语义）；无资金/账本回退需求。

## 8. 测试计划

| AC | 测试文件（新增/修改） | 类型 |
|---|---|---|
| AC-P78-01 契约与能力探测 | `backend/spec/models/pallastrade/dispute_write_contracts_spec.rb`（新增） | 模型/契约 |
| AC-P78-02 目录与校验 | `backend/spec/services/pallastrade/disputes/evidence_catalog_spec.rb`（新增） | 服务 |
| AC-P78-03/04/05/10/12 编排 | `backend/spec/services/pallastrade/disputes/submit_evidence_spec.rb`（新增） | 服务（回执/幂等/失败/逾期/文件/负向） |
| AC-P78-06/07/12 编排 | `backend/spec/services/pallastrade/disputes/accept_dispute_spec.rb`（新增） | 服务（不可逆/理由/负向） |
| AC-P78-08/09/13 控制台 | `backend/spec/requests/pallastrade/admin/disputes_ops_dangerous_actions_spec.rb`（新增） | 请求（权限/降级/双重确认/文件上传/路由） |
| AC-P78-14 回归 | 注册 verifier `backend-rspec`（全量）+ `generated:check` + `doc-impact` | 回归 |

## 9. 文档同步清单（知识同步门）

- [x] `ai/skills/pallastrade-payments/SKILL.md`：新增「Dispute 危险操作与证据提交（DSP-P7-8）」段 + Changelog（写契约 / 证据目录 / 不可变回执 / 逾期策略 / 事件 / 铁律）
- [x] `ai/skills/pallastrade-events-webhooks/SKILL.md`：事件目录新增 `dispute.evidence_submitted` / `dispute.accepted`
- [x] `ai/skills/pallastrade-data-model/SKILL.md`：新增不可变回执表 `pallastrade_dispute_evidence_submissions` 语义（append-only、幂等键、无金额列）
- [x] `ai/skills/pallastrade-security/SKILL.md`：已评估，无需更新——三件套（permission/confirmation/audit）沿用既有 `Ability` + `Audit.record` 机制，**未新增**权限/注册表项（危险操作三件套约定登记在 payments SKILL 与 PRD）
- [x] `harness/scenarios/scenarios.json`：新增 **GS-100**（危险操作必须三件套 + 幂等 + 零资金/零状态回写；GS-099 已被并行会话的「管理台登出重定向」修复占用）
- [x] `docs/prd/README.md`：本 PRD 索引行（状态随实施推进）
- [x] `harness/requirements/REQ-20260913-dsp-p7-8-dispute-dangerous-actions.md`：已生成（含 6 层搜索 + Skill 咨询证据表）
- [x] API 文档：N/A（无接口变更；Admin HTML 路由）→ 以 `generated:check` 无漂移为证
- [x] `ai/skills/pallastrade-testing` / `pallastrade-i18n` / `pallastrade-admin`：已评估，无需更新（沿用既有 spec 栈、双语成对约定与控制台范式）

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-13 | 0.1 | 初稿（承接 DSP-P7-7；源计划 §67/§68；含 6 层跨层搜索与 4 项待决策项） | AI |
| 2026-09-13 | 0.2 | **用户确认（approved）**：A 仅 Stripe 先行 / **含文件上传**（Stripe File + ActiveStorage）/ 逾期允许+二次确认+`late:true` / **新建不可变表**；允许按 §3 FR-001…FR-008 全量实施 | AI |
| 2026-09-13 | 0.3 | 实施完成：core 写契约 + 证据目录 + `SubmitEvidence`/`AcceptDispute` + 不可变回执表（migration `20260913000001`）+ Stripe 写实现（含 `Stripe::File` 上传）+ 控制台危险操作卡（双重确认）；specs 31 例全绿（服务/模型/请求；含幂等、失败不落回执、逾期确认、文件类型白名单、权限 302、无批量路由、零资金副作用负向断言）；管理台回归 51 例全绿 | AI |
| 2026-09-13 | 0.4 | 知识同步补强：`GS-100` 追加 2 条验收点（控制台面须有请求规格钉住权限 302 / confirm 标记 / 空目录网关分支 + 双语 locale；不得对无权限或空目录网关暴露写动作）；`eval-ai --scenarios` 101/101 | AI |
| 2026-09-13 | 0.5 | 验证完成 → **done**：注册 verifier `backend-rspec` 全量绿（EVD-20260913051900-9011fb695a：1619 examples / 0 failures / 6 pending；Line 65.8% / Branch 27.94%）；定向 31 examples + 管理台回归 51 examples 全绿；RuboCop 触及 15 文件 0 offenses；`generated:check` 无漂移、`doc-impact` 判定知识已同步、`eval ai --check-freshness` 0 warning；gate `GATE-2026-09-13T05-19-32` 16/16 关闭（review EVD-20260913052005-45c56879d2 / knowledge EVD-20260913052006-13694a7872 / approval EVD-20260913052008-f495bb2261）；恢复计划 `REC-a8e54a9bb46fac`；提交 `207529db`（实现）与 `c75936e2`（并行提交捎带 GS-100 补强）已推送 `origin/dev`；CI（`c75936e2`）：AI CI / Monorepo Contract / Deploy / Backend CI **全部 ✅**；dev 部署核验：`pull-deploy` state=`c75936e2`，容器内 `submit_evidence.rb` 与 `dispute_evidence_submission.rb` 已就位，`submit_evidence` / `accept_dispute` 等 7 条 member 路由 + index/show 已注册，线上 `GET /admin/disputes` → **302**（登录跳转） | AI |
