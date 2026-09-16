# REQ-20260916-ai-acceptance-audit

> 关联 PRD：`docs/prd/catalog/PRD-20260916-catalog-ai-acceptance-audit.md`（approved）
> 任务：`TASK-20260916121353-317d7d9b` · Gate：`GATE-2026-09-16T12-14-07`
> 来源：商品域审计 `docs/research/RESEARCH-20260916-catalog-domain-audit.md` 的 **G-5（P1）**

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — controllers | `backend/app/` | `ai/product_description` / `acceptance` | `controllers/pallastrade/admin/ai_controller.rb`（4 个 copilot action；`render_copilot_result` **已下发 run_id**）、`config/routes.rb:31-34` | ⚠️ 缺 1 个采纳端点 |
| App — views/decorators | `backend/app/` | `ai_assist` | 无（AI 面板视图在 admin gem） | ✅ 不涉及 |
| AI Gem — models | `pallastrade_ai/app/models/` | `acceptance` / `accept` | `ai/run.rb`（status/mode/tokens/cost/error，**无采纳字段**）、`ai/artifact.rb`（payload + checksum） | ⚠️ **G-5 修正点**（缺字段） |
| AI Gem — services | `pallastrade_ai/app/services/` | `run_id` / `Result` | `ai/catalog/{product_copy,product_translation,health_fix_suggestion}.rb` 的 `Result` **均已带 run_id** | ⚠️ 缺记录服务 |
| AI Gem — 迁移 | `pallastrade_ai/db/migrate/` | `ai_runs` | `20260724000005_create_pallastrade_ai_runs.rb` + 6 个基础迁移 | ✅ 可加增量迁移 |
| Admin Gem — 前端 | `pallastrade_admin/app/javascript/` | `ai_assist` | `controllers/ai_assist_controller.js`（`accept()`/`discard()` **只改 UI，不发请求**）、`helpers/ai_assist_helper.rb`、3 个视图的 `ai_assist_*` data | ⚠️ **G-5 修正点**（需上报） |
| Admin Gem — 控制器/视图 | `pallastrade_admin/app/` | `ai` | 无 AI 端点（AI 配置与 copilot 端点都在宿主 `app/`）；`views/pallastrade/admin/ai/runs.html.erb` 待加列 | ⚠️ 需加列 |
| API Gem | `pallastrade_api/app/` | `ai` | 无 AI 端点 | ✅ 不涉及 |
| Storefront | `storefront/src/` | `ai` | 无（AI 仅后台） | ✅ 不涉及 |
| Platform | `platform/packages/` | `ai` | 无 | ✅ 不涉及 |

### 搜索结论

- 生成侧**已完备**（Run + Artifact + run_id 下发），**采纳侧完全缺失** → 本批只补"记录"这一段。
- 改动面：AI gem（1 迁移 + Run 模型小改 + 1 服务）+ admin（1 端点 + 1 路由 + 1 处 JS + 1 个视图列）。
- **零新表**（只加 2 列）、**零 API 契约变更**、**零前台改动**。

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树：**"Settings → Configuration → Events → Dependencies → Admin/Ransack APIs → Generators → Decorators → Extensions"**；本项目 AI gem 为团队产品（AGENTS §1 可直改），本批是**框架内部可观测性补全**，不是宿主定制 → 直改 gem + 宿主控制器 |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | 后台约定：`tables.register` + 逐列 `.add`、动作需 `data: { turbo_method: }`；本批在 `ai/runs` 视图加一列，**不改导航**（沿用既有 AI Tools 菜单） |
| `ai/skills/pallastrade-catalog/SKILL.md` | ✅ 已读 | §"Catalog Health 的 AI 修复建议"与 E-1/E-2 章节确立了 **Generate → Preview → Accept → Save 的安全边界**（AI 只出草稿、Accept 才写表单）；本批**不改变该边界**，只是给 Accept 加一次留痕 |

**按需 Skill：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-testing` | ✅ 涉及 | ✅ 已读 | 新增 gotcha："CI 测试库非空（`db:prepare` 会 seed）"—— 本批 spec 必须避免假设空库；验证器注册 + 环境无关用例 |
| `pallastrade-events-webhooks` | ⬜ 不涉及 | — | 采纳记录是**同步写本地表**，不是领域事件，不发 webhook |
| `pallastrade-api-v3` | ⬜ 不涉及 | — | 新端点是 admin 会话内 JSON，不经 v3 契约 |
| `pallastrade-data-model` | ⬜ 不涉及 | — | 只加 2 列、无新表 |
| `pallastrade-i18n` | ⬜ 涉及（轻） | — | 采纳状态文案进 admin locale（en + zh-CN 双补），沿用 `admin.ai.*` 命名空间 |
| `pallastrade-decorators` / `pallastrade-dependencies` | ⬜ 不涉及 | — | 不改既有类结构，不替换核心服务实现 |

---

## 需求标题

AI 采纳审计：记录 Accept / Discard 结果，让「AI 接受率」可测

## 任务类型

功能优化（可观测性补全）

## 需求描述

商家点了 AI 面板的 Accept 或 Discard 之后，系统应当记下来 —— 现在什么都没记，于是"AI 草稿的接受率"无法计算。本批把这两个动作变成可审计的记录，并在后台 AI Runs 列表里可见。

## 影响范围

| 变更文件 | 说明 |
|---|---|
| `pallastrade_ai/db/migrate/<ts>_add_acceptance_to_pallastrade_ai_runs.rb` | 加 `acceptance_state` + `accepted_at` |
| `pallastrade_ai/app/models/pallastrade/ai/run.rb` | 状态常量、校验、`accepted?`/`discarded?`/`record_acceptance!` |
| `pallastrade_ai/app/services/pallastrade/ai/catalog/record_acceptance.rb` | 归属校验 + 幂等写入 |
| `backend/app/controllers/pallastrade/admin/ai_controller.rb` | `acceptances` action |
| `backend/config/routes.rb` | `post 'ai/acceptances'` |
| `pallastrade_admin/app/javascript/.../ai_assist_controller.js` | Accept/Discard 上报（try/catch 静默） |
| `pallastrade_admin/app/views/pallastrade/admin/ai/runs.html.erb` | 采纳状态列 |
| `pallastrade_admin/config/locales/en.yml` + `backend/config/locales/admin*.zh-CN.yml` | 状态文案 |

**不可触碰**：4 个既有 copilot 端点的响应形状（生成侧回归）、Accept 写入表单的前端语义、Store/Admin API。

## 技术方案（初步）

- **数据**：`acceptance_state`（string，NULL/accepted/discarded）+ `accepted_at`（datetime）。
- **服务**：`AI::Catalog::RecordAcceptance.call(run:, state:)` →
  - 校验 state ∈ ACCEPTANCE_STATES，否则返回 `:invalid_state`
  - 同状态重复提交：**不改** `accepted_at`（幂等）
  - 跨状态改判：覆盖状态并更新 `accepted_at`
- **端点**：`POST /admin/ai/acceptances` → 参数 `run_id`、`state`；run 经 `current_store.ai_runs.find_by_prefix_id!`（跨店 → 404）；成功 200，非法 state 422。
- **前端**：`accept()` / `discard()` 末尾 `this.reportAcceptance('accepted'|'discarded')`，整段 try/catch；`pending.run_id` 缺失时静默跳过（老响应/降级场景）。

## 不变量（不得破坏）

1. 生成侧 4 个端点的响应形状与状态码不变（既有 3 个 verifier 必须继续全绿）。
2. Accept 仍只写表单、Discard 仍只清预览 —— **不得**因为上报而改变 UI 时序。
3. 跨店 run_id 一律 404 且零写入。
4. 未标记的 run：`acceptance_state` 为 NULL，`accepted?`/`discarded?` 均为 false。
5. 同一状态重复上报不得改写 `accepted_at`。

## 文件级实施计划

1. 写迁移（AI gem）→ 跑 `db:migrate`（dev/test 容器内执行）。
2. `Run`：常量 + 校验 + 谓词 + `record_acceptance!`。
3. `RecordAcceptance` 服务（含幂等与改判语义）。
4. `AIController#acceptances` + 路由。
5. JS：`reportAcceptance(state)` + 在 `accept()`/`discard()` 调用。
6. `ai/runs` 视图加列 + locale（en/zh-CN）。
7. Specs：模型 + 请求两个新文件；注册 `ai-acceptance-rspec` 验证器。
8. 知识同步：catalog Skill（AI 采纳审计章节）、admin Skill（runs 列 + 上报约定）、场景 GS-158、审计报告 G-5 状态更新。

## 证据计划

| 改动类型 | 证据 |
|---|---|
| 后端逻辑 | `harness verify ai-acceptance-rspec`（模型 + 请求） |
| 生成侧回归 | `ai-copilot-rspec` / `ai-translate-rspec` / `ai-health-suggestion-rspec` |
| 前端 JS | 无独立测试框架覆盖 controller → 以**代码审查 + 端点 spec** 记录（并在 PRD AC-009 标注为审查项） |
| 文档 | `doc-impact` + `sync-check` |

## 用户确认

用户 2026-09-16 回复「**继续**」，承接审计建议的下一优先级（G-5），PRD 状态置 approved。
