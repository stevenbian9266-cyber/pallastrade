# PRD-20260917-catalog-ai-edited-before-save

> AI 采纳后编辑审计：记录 `edited before save`（补方案 §十六 最后一项指标）

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-17 |
| 来源 | 「实施」→ 方案 §十六「AI-generated content edited before save」；G-5 明确留下的最后一片 |
| 分类 | catalog |
| 关联 Skill | pallastrade-catalog、pallastrade-admin、pallastrade-ai、pallastrade-testing |
| 关联 REQ | `harness/requirements/REQ-20260917-catalog-ai-edited-before-save.md` |
| 关联 PRD | 承接 `PRD-20260916-catalog-ai-acceptance-audit`（那批记 Accept / Discard；本批记"采纳后又改了"） |
| 需求类型 | 优化迭代（可观测性补全） |

## 1. 背景与目标

- **背景**：`PRD-20260916-catalog-ai-acceptance-audit` 让"商家有没有用 AI 草稿"可测（Accept / Discard）。但方案 §十六 要的还有一项：**`AI-generated content edited before save`** —— 采纳之后、保存之前**又被改过**。这两个数字合起来才说明问题：
  - 高采纳率 + 低编辑率 → AI 输出基本可用；
  - 高采纳率 + 高编辑率 → 商家在"把 AI 草稿改成能用的东西"，采纳率**虚高**。
- **目标**：把"采纳后被编辑"变成一条**可查询的记录**。
- **非目标**：不做编辑幅度 diff、不做 AI 质量评分、不阻断保存、不改"AI 不直接落库"的安全边界。

## 2. 用户故事 / 场景

- **US-1**：作为店主/运营，我想知道 AI 草稿被采纳后有多少被实际改动过，好判断 AI 输出质量是不是真在提升。
- **US-2**：作为运维，我希望这个记录**不影响商家操作** —— 记录失败绝不能拦住保存。
- **场景**：商家点 Accept（草稿填入表单）→ 又手动改了标题 → 点 Save。此时该 run 记为 `edited`，而不是停留在 `accepted`。

## 3. 功能需求（FR）

| ID | 需求 | 说明 |
|---|---|---|
| FR-001 | 新增终态 `edited` | `PallasTrade::AI::Run::ACCEPTANCE_STATES` 增加 `edited`（服务端校验随之生效） |
| FR-002 | Accept 时记快照 | 前端在 Accept 写入表单后，记录**刚写入的值**（按 input name → value）与该 run_id |
| FR-003 | 保存前对比 | controller 所在表单 submit 前，对比快照与当前值；**任一被改**即报告 `edited` |
| FR-004 | 复用既有端点 | 仍用 `POST /admin/ai/acceptances`（`state: 'edited'`），不新增路由 |
| FR-005 | 最多报一次 | 同一 run 只报一次 `edited`（上报后清空快照） |
| FR-006 | 失败不阻断 | 上报用 `keepalive` 的 fire-and-forget；任何异常都被吞掉，不影响保存 |
| FR-007 | 列表可见 | `/admin/ai/runs` 的 Acceptance 列显示 `edited`（含中文文案） |

## 4. 非功能需求（NFR）

| ID | 要求 |
|---|---|
| NFR-001 | **不阻断**：上报失败/超时都不得阻止表单提交（`keepalive` + 吞异常） |
| NFR-002 | **不误报**：只有**值真的不同**才算 edited；未 Accept 过、未改动、`run_id` 缺失都不报 |
| NFR-003 | **零新表**：复用 `pallastrade_ai_runs.acceptance_state`（字符串列，无需迁移） |
| NFR-004 | **幂等**：重复提交同一 run 不产生额外记录（沿用既有 `record_acceptance!` 语义） |
| NFR-005 | **跨店隔离**：沿用既有端点校验（他人 run → 404，不触碰） |

## 5. 验收标准（AC，与测试一一映射）

| ID | 验收标准 |
|---|---|
| AC-001 | `edited` 是合法终态；未知状态仍返回 422 |
| AC-002 | `accepted` 之后报 `edited` 会覆盖为 `edited`（终态取最后决定） |
| AC-003 | 同一 run 重复报 `edited` 不改变 `accepted_at` 之外的语义（幂等，不报错） |
| AC-004 | 跨店「他人 run」报 `edited` → 404 且不修改 |
| AC-005 | AI Runs 列表在 en / zh-CN 下都能显示 `edited`（含既不 `translation missing`） |
| AC-006 | 前端：Accept 后未改动 → **不**报 edited（不误报） |
| AC-007 | 前端：Accept 后修改了任一被写入字段 → 报一次 edited |
| AC-008 | 前端：未 Accept 直接保存 → 不报任何状态 |
| AC-009 | 上报失败被吞掉，表单提交不受影响 |

> AC-006~009 是 JS 行为，用**静态契约断言**（源码级）+ 后端端点断言覆盖：本项目前端无 JS 单测基建，故以「后端端点行为 + 前端源码契约」双重守住（见 §8）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 搜索路径 | 关键词（含同义词） | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| **App** | `backend/app/` | `acceptance` / `ai_runs` | `controllers/pallastrade/admin/ai_controller.rb`（既有 `acceptances` 端点）、`views/.../ai/runs.html.erb` | ⚠️ 端点已存在，**缺 `edited`** |
| **Core** | `pallastrade_ai/app/` | `acceptance_state` / `record_acceptance` | `models/pallastrade/ai/run.rb`（`ACCEPTANCE_STATES` + `record_acceptance!`）、`services/.../record_acceptance.rb`（`Result` 带 `changed?`） | ⚠️ 状态机就位，**需加一个状态** |
| **Admin gem** | `pallastrade_admin/app/javascript/` | `ai-assist` | `controllers/ai_assist_controller.js`（`accept()` 已取到 `run_id` 并报 `accepted`；`reportAcceptance` 已是 fire-and-forget） | ⚠️ 需加快照 + submit 对比 |
| **API** | `pallastrade_api/app/` | `acceptance` | 无 | ✅ 不涉及（后台 JSON 端点） |
| **Storefront** | `storefront/src/` | `ai_acceptance` | 无 | ✅ 不涉及 |
| **Platform** | `platform/packages/` | `acceptance` | 无 | ✅ 不涉及 |

**结论**：无新表、无新路由；改动集中在 1 个状态常量 + 1 个 JS 控制器 + 文案 + specs。

## 7. 技术影响

| 变更文件 | 说明 |
|---|---|
| `pallastrade_ai/app/models/pallastrade/ai/run.rb` | `ACCEPTANCE_STATES` 加 `edited` |
| `pallastrade_admin/app/javascript/.../ai_assist_controller.js` | Accept 记快照；表单 submit 前对比并上报 |
| admin `en.yml` + 宿主 `admin_ai.zh-CN.yml` | `edited` 文案 |
| specs | 端点/模型 + 前端源码契约 |

**不可触碰**：`record_acceptance!` 的幂等语义、既有 `acceptances` 端点的鉴权、AI 安全边界（AI 绝不直接落库）。

## 8. 测试计划

| 测试文件 | 覆盖 |
|---|---|
| `backend/spec/requests/pallastrade/admin/ai_acceptances_spec.rb`（扩展） | AC-001 ~ AC-004 |
| `backend/spec/models/pallastrade/ai/run_acceptance_spec.rb`（扩展） | AC-001 / AC-003 |
| `backend/spec/requests/pallastrade/admin/ai_runs_locale_spec.rb`（新） | AC-005（en/zh-CN 列文案） |
| `backend/spec/javascript/ai_assist_edited_source_spec.rb`（新） | AC-006 ~ AC-009（对控制器源码的契约断言：快照、对比、keepalive、try/catch） |

> **为什么用源码契约断言**：本项目前端没有 JS 单测基建（无 jest/vitest），
> 而"采纳后编辑"的核心风险是**误报/阻断**。与其引入一套新测试基建，
> 不如对控制器源码断言四个必有行为（记快照、真比较、keepalive、吞异常）——
> 它挡不住所有回归，但能挡住"忘记清快照""忘了 keepalive""去掉 try/catch"这三类真实风险。
> 这是**有取舍的**，已在 §10 D5 记录。

## 9. 文档同步清单（知识同步门）

- [ ] `ai/skills/pallastrade-catalog/SKILL.md`（AI 采纳审计三态：accepted / discarded / edited 的语义）
- [ ] `ai/skills/pallastrade-admin/SKILL.md`（Acceptance 列三态）
- [ ] `harness/scenarios/scenarios.json`（新场景：观测不得阻断主流程、编辑判定必须真比较）
- [ ] `docs/research/RESEARCH-20260917-admin-i18n-gap.md`（**新建**：i18n 缺口量化结果）
- [ ] 本 PRD 状态 + `docs/prd/README.md` 索引

## 10. 关键决策

| # | 决策 | 取值 | 理由 |
|---|---|---|---|
| D1 | `edited` 是**覆盖**还是**并存** | **覆盖** `accepted` | `acceptance_state` 表达"商家最终怎么处理这份草稿"。要让"曾 accepted"也可查需再加列，而 §十六 要的是"编辑率"= edited ÷ (accepted + edited)，覆盖即可算 |
| D2 | 判定放前端还是后端 | **前端** | Accept 只改 DOM、草稿不入库（AI 安全边界），服务端拿不到"刚写入的草稿"，无法对比 |
| D3 | 对比方式 | **按被写入字段逐一比对值** | 用"表单被触碰过"会把商家改了别的字段也算成编辑（误报），值比较才准确 |
| D4 | 上报时机的可靠性 | **submit 事件 + `keepalive`** | Turbo 会接管提交并跳转，普通 fetch 可能被中断；`keepalive` 让请求在导航中存活 |
| D5 | 前端行为怎么测 | **源码契约断言**（不引入 JS 测试基建） | 见 §8 说明：这是**有取舍**的 —— 挡住真实风险（漏清快照/漏 keepalive/去掉 try-catch），但不等于完整前端测试 |
| D6 | 是否记录编辑幅度 | **不记** | 方案只要"是否被编辑"；记 diff 会引入内容留存与隐私面，超出本批 |

## 11. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-17 | 0.1 | 初稿：G-5 留下的最后一片（采纳后编辑） | AI |
| 2026-09-17 | 1.0 | 用户「实施」授权；补 FR/AC/NFR、6 层搜索、D1~D6（含 D5 对前端测试取舍的如实记录）→ status approved | AI |
