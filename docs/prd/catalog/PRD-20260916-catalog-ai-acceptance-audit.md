# PRD-20260916-catalog-ai-acceptance-audit

> AI 采纳审计：记录 Accept / Discard 结果，让「AI 接受率」可测

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-16 |
| 来源 | 「继续」→ 商品域审计（`docs/research/RESEARCH-20260916-catalog-domain-audit.md`）的 **G-5（P1）** |
| 分类 | catalog（AI 能力 PRD 惯例归此，见 E-1/E-2/E-3） |
| 关联 Skill | pallastrade-catalog、pallastrade-admin、pallastrade-testing |
| 关联 REQ | `harness/requirements/REQ-20260916-ai-acceptance-audit.md`（实施时回填） |
| 关联 PRD | 承接 `PRD-20260915-catalog-batch-e1-ai-copilot` / `-e2-ai-translate-missing` / `PRD-20260916-catalog-batch-e3-ai-fix-suggestion`（生成侧）；本批补**采纳侧** |
| 需求类型 | 优化迭代（可观测性补全） |

## 1. 背景与目标

- **背景（审计 G-5）**：方案 §十六 要求衡量「AI Generation acceptance rate」与「AI 生成内容在保存前被编辑的比例」，但实测发现：
  - **生成侧已完备**：`AI::Run`（`pallastrade_ai_runs`）记录每次调用（status/mode/tokens/cost/timing），`AI::Artifact` 存草稿 payload，三个 copilot 服务的 `Result` **已经带 `run_id`**，端点也已把它下发（`render_copilot_result` → `payload.merge(run_id: result.run_id)`）。
  - **采纳侧完全缺失**：`Run` 没有"是否被采纳"的字段，`ai_assist_controller.js` 的 `accept()` / `discard()` **只改表单与 UI，不发任何请求**。于是：**草稿被丢掉还是被采用，系统一无所知**，接受率无从计算。
- **目标**：把「Accept / Discard」变成一次**可审计的记录**，使 AI 接受率可统计、可在后台 Runs 列表直接看到。
- **成功指标**：任意一次生成后，Accept（或 Discard）都能在 `AI::Run` 上留下状态与时间；AI Runs 列表可见；跨店/无效 run_id 不产生任何写入。

## 2. 用户故事 / 场景

- 作为**商品运营负责人**，我要知道 AI 草稿的接受率，才能判断值不值得继续为它付费。
- 作为**审计者**，我要能从 Run 追溯到"这条草稿后来被采用了 / 被丢弃了"，而不是只有"模型跑过"。
- 边界：
  - 跨店 `run_id` → **404 且零写入**（多店隔离铁律）。
  - 重复提交同一状态 → **幂等**（不产生第二条记录，不重置时间）。
  - 状态被改判（先 accepted 后 discarded）→ 覆盖并更新 `accepted_at`。
  - 记录动作**失败不得影响商家**：前端静默失败，Accept 的表单写入照常完成。
  - AI 引擎未安装时，admin 照常工作（既有 `defined?(...)` 守卫模式）。

## 3. 功能需求（FR）

- FR-001：`pallastrade_ai_runs` 新增 `acceptance_state`（`accepted` / `discarded`，未处理为 NULL）与 `accepted_at`（时间戳）；`AI::Run` 暴露 `ACCEPTANCE_STATES`、`accepted?`、`discarded?`、`record_acceptance!(state:)`。
- FR-002：新增端点 `POST /admin/ai/acceptances`，入参 `run_id` + `state`（`accepted` / `discarded`）：校验 run 属于 `current_store`，写状态与时间，返回 200 JSON；无效/跨店 run → 404，非法 state → 422，均零写入。
- FR-003：`ai_assist_controller.js` 在 `accept()` 与 `discard()` 时调用该端点（带 `pending.run_id`）；**整段包 try/catch，失败静默**，UI 行为（写入表单 / 隐藏预览 / 状态文案）不受影响。
- FR-004：AI Runs 列表（`/admin/ai/runs`）展示采纳状态（含"未处理"），使接受率可现场核对。
- FR-005（本批**不做**，记录理由）：`edited`（Accept 之后、Save 之前被商家改动）需要把 `ai_run_id` 随表单提交并在保存时对比草稿 —— 涉及 3 个入口表单与 Trix/TinyMCE 取值，**留到下一片**；本批先把 `acceptance_state` 字段与记录链路建好，下一片只需加 `edited` 判定。

## 4. 非功能需求（NFR）

- **多店隔离**：run 查询一律经 `current_store.ai_runs`（或 `for_store(current_store)`），禁止全局 find。
- **幂等**：同一 run 重复提交相同状态不改变 `accepted_at`。
- **不阻塞**：前端记录失败不得影响 Accept/Discard 的表单效果；后端记录失败不得影响生成端点。
- **无 PII**：只记录状态与时间，不新增任何草稿内容到 Run（沿用"Run 不存 prompt/全文"的既有隐私边界）。
- **兼容**：AI 引擎缺席时 admin 不受影响；`runs` 列表在字段为 NULL 时显示"未处理"。

## 5. 验收标准（AC，与测试一一映射）

| AC | ← FR | 判定条件 |
|---|---|---|
| AC-001 | FR-001 | 新列存在；`acceptance_state` 仅接受 `accepted`/`discarded`/NULL |
| AC-002 | FR-001 | Run 未标记时 `accepted?` / `discarded?` 均为 false（不误报） |
| AC-003 | FR-002 | `POST /admin/ai/acceptances` 传合法 run_id + accepted → 200，run 状态与时间被写入 |
| AC-004 | FR-002 | 跨店 run_id → 404，且该 run **零改动** |
| AC-005 | FR-002 | 非法 state → 422，零写入 |
| AC-006 | FR-002 | 重复提交同状态 → 幂等（`accepted_at` 不变） |
| AC-007 | FR-002 | 改判（accepted → discarded）→ 状态覆盖且 `accepted_at` 更新 |
| AC-008 | FR-004 | Runs 列表渲染采纳状态；未处理显示对应文案 |
| AC-009 | FR-003 | `accept()` / `discard()` 均触发记录请求；记录抛错时表单写入与 UI 状态不变（前端行为，由 JS 实现保证 + 代码审查记录） |

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | `ai/product_*` | `controllers/pallastrade/admin/ai_controller.rb`（4 个 copilot action；私有 `render_copilot_result` **已下发 run_id**）、`config/routes.rb:31-34` | ⚠️ 需加 1 个端点 |
| AI Gem（模型/服务） | `pallastrade_ai/app/` | `acceptance` / `accept` | `models/pallastrade/ai/run.rb`（status/mode/tokens/cost，**无采纳字段**）、`artifact.rb`（payload + checksum）、`catalog/{product_copy,product_translation,health_fix_suggestion}.rb`（`Result` **已带 run_id**） | ⚠️ **G-5 修正点**（缺字段 + 缺记录动作） |
| AI Gem（迁移） | `pallastrade_ai/db/migrate/` | `ai_runs` | `20260724000005_create_pallastrade_ai_runs.rb` + 6 个基础迁移 | ✅ 可加增量迁移 |
| Admin Gem（前端） | `pallastrade_admin/app/javascript/` | `ai_assist` | `controllers/ai_assist_controller.js`（`generate()` 存 `pending`、`accept()` 写表单、`discard()` 丢弃，**均不发请求**）、`helpers/ai_assist_helper.rb`、3 个视图的 `ai_assist_*` data 属性 | ⚠️ **G-5 修正点**（Accept/Discard 需上报） |
| API Gem | `pallastrade_api/app/` | `ai` | 无 AI 端点 | ✅ 不涉及 |
| Storefront | `storefront/src/` | `ai` | 无（AI 只在后台） | ✅ 不涉及 |
| Platform | `platform/packages/` | `ai` | 无 | ✅ 不涉及 |

**结论**：改动集中在 **AI gem（1 迁移 + Run 模型 + 1 服务）** 与 **admin（1 端点 + 1 路由 + 1 处 JS + 1 个列表视图）**；
**零 API 契约变更、零前台改动、零新表**（只加 2 列）。

## 7. 技术影响

| 组件 | 文件 | 变更 |
|---|---|---|
| 迁移 | `pallastrade_ai/db/migrate/<ts>_add_acceptance_to_pallastrade_ai_runs.rb` | 加 `acceptance_state`(string) + `accepted_at`(datetime) |
| 模型 | `pallastrade_ai/app/models/pallastrade/ai/run.rb` | `ACCEPTANCE_STATES`、校验、`accepted?`/`discarded?`、`record_acceptance!` |
| 服务 | `pallastrade_ai/app/services/pallastrade/ai/catalog/record_acceptance.rb` | 校验 store 归属 + 幂等写入 |
| 端点 | `backend/app/controllers/pallastrade/admin/ai_controller.rb` | `acceptances` action |
| 路由 | `backend/config/routes.rb` | `post 'ai/acceptances'` |
| 前端 | `pallastrade_admin/app/javascript/.../ai_assist_controller.js` | Accept/Discard 上报（try/catch 静默） |
| 视图 | `pallastrade_admin/app/views/pallastrade/admin/ai/runs.html.erb` | 采纳状态列 |

**接口契约**：无 Store/Admin API 变更（新端点是 **admin HTML 会话内的 JSON**，与既有 copilot 端点同类）→ `generated:check` 应无漂移。

## 8. 测试计划

| 文件 | 覆盖 AC |
|---|---|
| `backend/spec/models/pallastrade/ai/run_acceptance_spec.rb` | AC-001/002/006/007 |
| `backend/spec/requests/pallastrade/admin/ai_acceptances_spec.rb` | AC-003/004/005/008 |
| 既有 `ai-copilot-rspec` / `ai-translate-rspec` / `ai-health-suggestion-rspec` | 回归（生成侧不被破坏） |

**验证器**：新增 `ai-acceptance-rspec`（覆盖上述 2 个新 spec）；生成侧沿用既有三个 verifier 回归。

## 9. 文档同步清单（知识同步门）

- [ ] `ai/skills/pallastrade-catalog/SKILL.md`（AI 采纳审计章节：Run 的采纳状态 + 端点 + 后端判定的责任边界）
- [ ] `ai/skills/pallastrade-admin/SKILL.md`（AI Runs 列表新增列 + ai-assist 的上报约定）
- [ ] `harness/scenarios/scenarios.json`（新场景：AI 草稿的采纳与否必须留痕，且记录失败不得影响商家）
- [ ] `docs/research/RESEARCH-20260916-catalog-domain-audit.md`（G-5 状态更新）
- [ ] 本 PRD 状态 + `docs/prd/README.md` 索引（`prd-status-sync --fix`）

## 10. 关键决策

| # | 决策 | 取值 | 理由 |
|---|---|---|---|
| D1 | 记录时机 | **Accept / Discard 时上报**（不等 Save） | Accept 是"商家采纳了草稿"的语义动作；等 Save 会漏掉"采纳后没保存"（该行为本身也值得统计） |
| D2 | `edited` 是否本批做 | **不做**（FR-005 记理由，留下一片） | 需要 3 个入口表单携带 `ai_run_id` 并在保存时对比草稿（含 Trix/TinyMCE 取值），范围与风险明显更大；先把字段与链路建好，下一片只补判定 |
| D3 | 幂等语义 | 同状态重复提交**不更新时间**；跨状态则**覆盖并更新时间** | 前者是重复上报（网络重试），后者是商家的真实改判 |
| D4 | 端点归属 | 放在既有 `Admin::AIController`（而非新控制器） | 与 4 个 copilot 端点同域同权限模型，避免新增导航/权限面 |
| D5 | 失败策略 | 前端 try/catch 静默；后端 4xx 不写库 | 观测性数据不得反过来伤害主流程（与 AP-009b 同一精神） |

## 11. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-16 | 0.1 | 初稿：由审计 G-5 提炼（记录 Accept/Discard，使接受率可测） | AI |
| 2026-09-16 | 1.0 | 用户「继续」推进；补 D1~D5、AC 表、测试与同步清单 → 状态 approved | AI |
