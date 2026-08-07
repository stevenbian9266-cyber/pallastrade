# 需求文档：实现私有化项目的优秀 Harness 工程级机制

> 日期：2026-08-07
> Gate：GATE-2026-08-07T03-02-49
> 类型：feature
> 决策人：Steven Bian（授权自行制定计划实施）
> 依据：本会话三轮审计结论（门禁可信度 42/100、治理体系 58/100、环境适配 30/100）
> 状态：✅ **已实施完成**（三阶段全部落地并验证通过）

---

## 背景与目标

私有化已完成（全仓零 Spree 残留）。目标：把 harness 从"L2 自觉协议"升级为"L3 工程级机制"。
**L3 达成标准：①CI 真实红绿 ②git 物理拦截生效 ③gate 不可被 AI 自清。**

本方案分三阶段实施，逐阶段验证。

---

## Step 0：跨层搜索（已全部执行）

| 层 | 搜索路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | harness / lefthook / CI | 无 | ✅ 无相关，本任务纯顶层工具 |
| Core | `pallastrade_core/` | upgrade / lefthook | `lib/tasks/upgrade.rake`（框架升级执行引擎，**不在本次范围**） | ✅ 无冲突 |
| API | `pallastrade_api/` | 同上 | 无 | ✅ |
| Admin | `pallastrade_admin/` | 同上 | 无 | ✅ |
| Storefront | `storefront/src/` + `storefront/lefthook.yml` | lefthook | 组件级 lefthook（pre-commit biome） | ⚠️ 参考其模式 |
| Platform | `platform/lefthook.yml` + 各 package.json | lefthook / test | 组件级 lefthook（pre-commit biome + typelizer，pre-push biome-ci） | ⚠️ 参考其模式 |
| 根级 | `package.json` / `scripts/harness/` / `harness/` / `.github/workflows/` | — | 根级**无 lefthook、无 harness 测试脚本** | ❌ 本次新增点 |

### 搜索结论
- 物理门禁需在**根级新建**（platform/storefront 的 lefthook 只覆盖各自组件）。
- 根 `package.json` 仅有 `harness` 脚本，无测试脚本、无 lefthook 依赖。
- 本次全部改动集中在：`scripts/harness/`、`harness/`、`.github/workflows/`、根级新增文件。

---

## Step 1：Skill 文件咨询

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 本任务是顶层工具建设，不涉及框架定制模式；无 gem 修改 |
| `ai/skills/pallastrade-testing/SKILL.md` | ✅ 已读 | 确认测试栈为 RSpec + Factory Bot（backend）与 Vitest（platform/storefront），harness 契约测试用 `node:test`（Node ≥22 内建，零依赖） |

**按需 Skill：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-project` | ✅（根级命令约定） | ✅ 已查 | 根级无 `pallastrade` CLI 包装，harness 命令以 `node scripts/harness/cli.mjs` 为准 |
| `pallastrade-deployment` | ✅（CI/release） | ✅ 已读 | release-phase 依赖 `pallastrade:upgrade`（保留），与本次 CI 修复无冲突 |

---

## 实施计划（三阶段）

### 阶段一（P0 · 可信度修复）—— 本次实施

| # | 改动 | 目标文件 | 说明 |
|---|---|---|---|
| 1.1 | **CI fail-open 修复**：移除 `harness-full.yml` 全部 `\|\| echo` 吞错（RSpec/Brakeman/bundle-audit/storefront/platform），失败即红 | `.github/workflows/harness-full.yml` | 最优先，恢复"绿色=通过"语义 |
| 1.2 | **diff 盲区修复**：`affected` 与 `doc-impact` 合并 `git diff HEAD`（unstaged）+ `git diff --cached`（staged）+ `origin/main...HEAD`（committed） | `scripts/harness/cli.mjs`、`doc-impact.mjs` | 本地变更可被感知 |
| 1.3 | **degraded-loop 接入 quick**：把 `degraded-loop` 加进 `config.json` quick profile | `harness/config.json` | AP-009 从此真正生效 |
| 1.4 | **扫描器修复**：`scan-anti-patterns.mjs` 每行重置 `lastIndex`；规则异常改为收集并失败而非静默 | `scripts/harness/scan-anti-patterns.mjs` | 消除漏报源 |
| 1.5 | **策略一致性**：`task-rules.json` TR-005 重复修复（重编号 TR-003/TR-005）；`doc-impact.mjs` 实现 `anyOf` 语义；SYNC_RULES 与 AGENTS.md §7 对齐 | `harness/policies/task-rules.json`、`doc-impact.mjs` | 消除声明与执行不一致 |
| 1.6 | **harness 契约测试**：`node:test` 覆盖 gate 生命周期、diff 合并、doctor、扫描器正则重置 | 新增 `scripts/harness/*.test.mjs` + 根 `package.json` 加 `test:harness` 脚本 | harness 自身有兜底 |

### 阶段二（P1 · 物理执行 + 环境适配）—— 本次实施

| # | 改动 | 目标文件 | 说明 |
|---|---|---|---|
| 2.1 | **git 物理门禁**：根级新增 `lefthook.yml`（pre-commit 挂 anti-patterns-error + degraded-loop 限 staged；pre-push 挂 doc-impact + generated-check）+ 根 devDependency `lefthook` + 文档说明安装 | 新增根 `lefthook.yml`、改根 `package.json` | **L3 条件②：agent 无关的物理拦截** |
| 2.2 | **扫描器支持按文件过滤**：`scan-anti-patterns.mjs` 增加 `--files` 参数（供 lefthook 传 `{staged_files}`），避免全仓 106 项噪音阻塞提交 | `scan-anti-patterns.mjs` | 物理门禁可用的前提 |
| 2.3 | **gate 加固**：任务类型增加 `research/audit/docs/refactor/security`；gate 记录 branch + HEAD commit；`gate:clear` 记录操作上下文 | `scripts/harness/cli.mjs` | **L3 条件③：gate 不可被随意自清** |
| 2.4 | **freshness 误报修复**：`eval-ai` 区分"示例路径"与"规范引用"（示例代码块内的路径不强制校验） | `scripts/harness/eval-ai.mjs` | 消除 38 项假阳性 |
| 2.5 | **指令强化**：`.github/copilot-instructions.md` 增加"编辑前必须 `gate:status` 校验"前置断言 + 任务类型清单更新 | `.github/copilot-instructions.md` | 环境适配：Copilot 唯一自动注入通道 |

### 阶段三（P2 · 质量闭环）—— 本次最小可用

| # | 改动 | 目标文件 | 说明 |
|---|---|---|---|
| 3.1 | **scenario 校验器**：`eval-ai --scenarios` 校验 `scenarios.json` 结构（schema 校验 + 编号唯一 + mustDo/mustNotDo 完整）并输出结构化报告 | `scripts/harness/eval-ai.mjs` | 让 11 个场景从"死数据"变"可校验资产"；LLM 评分执行器留作后续（建议 promptfoo） |
| 3.2 | **证据结构化**：`evidence collect` 真实采集 command/SHA/env/测试结果写入 `artifacts/harness-evidence/` | `scripts/harness/cli.mjs` | 交付证据不再靠 AI 自报 |

### 明确不在本次范围（留档）
- AST 级反模式迁移（ESLint rule / RuboCop cop / Semgrep）——阶段三之后单独任务
- promptfoo LLM 场景执行器——需引入外部依赖，单独评估
- 覆盖率门禁（SimpleCov/codecov 阈值）——依赖现有测试基建，单独任务

---

## 反模式自查

- [x] AP-001~009：本次改动为 CLI/CI/文档，无 TSX/Ruby 业务代码，不涉及
- [x] 不新建业务模块；新文件仅在 `scripts/harness/`、根级、`.github/`（工具层）
- [x] 不触碰 `backend/db/migrate/`、`Gemfile.lock`、`db/schema.rb`

## 验证计划（逐阶段）

| 阶段 | 验证命令 | 预期 |
|---|---|---|
| 一 | `node --test scripts/harness/*.test.mjs` | 全绿 |
| 一 | `node scripts/harness/cli.mjs check --profile quick` | degraded-loop 出现在运行列表 |
| 一 | 本地改一个未提交文件后 `doc-impact` | 能报出该文件 |
| 二 | `npx lefthook run pre-commit --all-files`（或 dry-run） | 拦截逻辑生效且不误伤 |
| 二 | `node scripts/harness/cli.mjs gate --task "审计：..."` | 识别为 audit 类型 |
| 二 | `node scripts/harness/cli.mjs eval-ai --check-freshness` | 误报大幅下降（<10） |
| 三 | `node scripts/harness/cli.mjs eval-ai --scenarios` | 输出 11 场景校验报告 |
| 三 | `node scripts/harness/cli.mjs evidence collect` | 生成结构化证据文件 |
| 全部 | `node scripts/harness/cli.mjs doctor` | 11/11 |
