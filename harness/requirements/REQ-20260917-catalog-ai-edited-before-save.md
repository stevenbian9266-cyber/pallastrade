# REQ-20260917-catalog-ai-edited-before-save

> 关联 PRD：`docs/prd/catalog/PRD-20260917-catalog-ai-edited-before-save.md`（approved）
> 任务：`TASK-20260917023444-1673cffd` · Gate：`GATE-2026-09-17T02-34-49`
> 来源：「实施」→ 方案 §十六 `AI-generated content edited before save`（G-5 留下的最后一片）

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| **App** | `backend/app/` | `acceptance` / `ai_runs` | `controllers/pallastrade/admin/ai_controller.rb`（`acceptances` 端点）、`views/.../ai/runs.html.erb`（Acceptance 列） | ⚠️ 端点已存在，缺 `edited` 状态 |
| **Core** | `pallastrade_ai/app/` | `acceptance_state` / `record_acceptance` | `models/pallastrade/ai/run.rb`（`ACCEPTANCE_STATES` = accepted/discarded）、`services/.../record_acceptance.rb`（返回 `Result` 带 `changed?`） | ⚠️ 状态机就位，需加一个状态 |
| **Admin gem** | `pallastrade_admin/app/javascript/` | `ai-assist` | `controllers/ai_assist_controller.js` —— `accept()` 已取到 `run_id`、已报 `accepted`；`reportAcceptance` 已是 fire-and-forget + try/catch | ⚠️ 需加"快照 + submit 对比" |
| **API** | `pallastrade_api/app/` | `acceptance` | 无 | ✅ 不涉及（后台 JSON 端点） |
| **Storefront** | `storefront/src/` | `ai_acceptance` | 无 | ✅ 不涉及 |
| **Platform** | `platform/packages/` | `acceptance` | 无 | ✅ 不涉及 |

**结论**：**零新表、零新路由、零迁移**；改动 = 1 个状态常量 + 1 个 JS 控制器 + 文案 + specs。

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树 **"Settings → Configuration → Events → Dependencies → Admin/Ransack APIs → Generators → Decorators → Extensions"**；本批是**既有后台功能的行为补全**（加一个观测状态 + 前端上报），落在 Admin 一级，不碰 Decorator/Events |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | 后台 Stimulus 控制器是**前端交互**的既有范式（`ai_assist_controller.js` 已在用）；"Acceptance 列"属于既有列表页，**不动导航**（故 `navigation_consistency_spec` 无需改） |
| `ai/skills/pallastrade-ai/SKILL.md` | ✅ 已读 | AI 能力契约：**AI 绝不直接落库**，草稿只进表单、由商家显式保存；本批**不改变**这条边界，只是给"采纳后的去向"补一个留痕 |
| `ai/skills/pallastrade-catalog/SKILL.md` | ✅ 已读 | §AI 采纳审计（D-2 批次）确立 `acceptance_state` 语义为"商家最终怎么处理这份草稿"；本批在同一状态机上**新增一个终态**，而非另起一套 |
| `ai/skills/pallastrade-i18n/SKILL.md` | ✅ 已读 | 新键必须**同步**补宿主 zh-CN；**进 HTML 属性**的文案须用 `I18n.t` + 纯文本兜底（上一批血的教训） |

**按需 Skill：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-testing` | ✅ 涉及 | ✅ 已读 | 验证器注册约定 + CI 测试库非空 gotcha → 断言自建夹具 + 随机 store code；**本项目前端无 JS 测试基建** → 前端行为用**源码契约断言**（已在 PRD §8/D5 如实记录取舍） |
| `pallastrade-events-webhooks` | ⬜ 不涉及 | — | 观测留痕走既有 JSON 端点，不发领域事件 |
| `pallastrade-data-model` | ⬜ 不涉及 | — | 零新表、零新列（`acceptance_state` 是既有 string 列） |
| `pallastrade-api-v3` | ⬜ 不涉及 | — | 后台 JSON 端点，非 v3 契约 |
| `pallastrade-security` | ⬜ 不涉及 | — | 沿用既有跨店校验（他人 run → 404），无权限模型变更 |
| `pallastrade-data-model` / `pallastrade-decorators` / `pallastrade-dependencies` | ⬜ 不涉及 | — | 无结构改动、不替换核心服务 |

---

## 需求标题

AI 采纳后编辑审计：记录 `edited before save`（补方案 §十六 最后一项指标）

## 任务类型

功能优化（可观测性补全）

## 需求描述

G-5 让"商家有没有用 AI 草稿"可测（Accept / Discard），但 §十六 还要 `AI-generated content edited before save`。两个数字合起来才说明问题：高采纳率 + **高编辑率** = 商家在"把 AI 草稿改成能用的东西"，采纳率**虚高**。

## 影响范围

| 变更文件 | 说明 |
|---|---|
| `pallastrade_ai/app/models/pallastrade/ai/run.rb` | `ACCEPTANCE_STATES` 加 `edited` |
| `pallastrade_admin/app/javascript/.../ai_assist_controller.js` | Accept 记快照；表单 submit 前对比 → 报 `edited` |
| admin `en.yml` + 宿主 `admin_ai.zh-CN.yml` | `edited` 文案 |
| specs × 4 | 端点/模型（扩展）+ 列表文案 + 前端源码契约 |

**不可触碰**：`record_acceptance!` 的幂等语义、既有端点的鉴权与跨店校验、**AI 不直接落库**的安全边界。

## 技术方案（初步）

1. **状态**：`ACCEPTANCE_STATES = %w[accepted discarded edited]` —— `edited` 是**终态**，覆盖先前的 `accepted`（D1）。
2. **快照**：`accept()` 写入表单后，记录 `{ inputName → value }` 与 `run_id`。
3. **对比与上报**：`connect()` 里取 `this.element.closest('form')`，监听 `submit`；比对快照与当前值，**有差异**才上报 `edited`（只报一次，报后清空）。
4. **可靠性**：`fetch(..., { keepalive: true })`（Turbo 提交会跳转，普通 fetch 可能被中断），异常一律吞掉（NFR-001）。

## 不变量（不得破坏）

1. **观测不得阻断主流程**：上报失败/超时不得影响保存（keepalive + try/catch）。
2. **不误报**：只有**值真的不同**才算 edited；未 Accept、未改动、无 `run_id` 一律不报。
3. **幂等**：同一 run 重复上报不报错、不产生副作用。
4. **跨店隔离**：他人 run → 404 且不被修改。
5. **零新表/零迁移/零新路由**。
6. **AI 安全边界不变**：AI 输出仍只进表单，绝不直接落库。
7. **文案双语**：新增键必须 en + zh-CN 同时存在（键集断言会守）。

## 文件级实施计划

1. `Run::ACCEPTANCE_STATES` 加 `edited`（模型校验随之生效）。
2. 前端控制器：快照 + submit 对比 + keepalive 上报 + 清快照。
3. 文案：gem `en.yml` + 宿主 `admin_ai.zh-CN.yml`（该域文件已存在，追加即可）。
4. Specs：端点 AC-001~004、模型 AC-001/003、列表 AC-005、前端源码契约 AC-006~009。
5. i18n 量化结果落盘：`docs/research/RESEARCH-20260917-admin-i18n-gap.md`。
6. 知识同步：catalog/admin Skill + 场景 + PRD 索引。

## 证据计划

| 改动类型 | 证据 |
|---|---|
| 后端状态机 + 端点 | `harness verify ai-edited-audit-rspec` |
| 前端行为 | 同上（源码契约断言）+ **浏览器真实渲染**（本会话前几批证明 spec 看不见渲染） |
| 文档 | `doc-impact` |

## 用户确认

用户 2026-09-17 明确指示「**实施**」本节两项：`AI-generated content edited before save` 与 i18n 剩余缺口量化。
