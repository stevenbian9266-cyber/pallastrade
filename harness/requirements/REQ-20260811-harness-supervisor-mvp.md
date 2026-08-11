# Harness 可靠性基线与开发监督器 MVP

> Gate：`GATE-2026-08-11T12-51-18`
> 方案来源：`harness升级方案.md`
> 关联权威路线图：`docs/standards/harness-standalone-roadmap.md`（approved）
> 目标仓库：`stevenbian9266-cyber/pallastradeharness`
> 基线：`main@dee768eb` / `pallastrade-harness@0.2.3`

## Step 0：跨层搜索

统一关键词：`harness`、`supervisor`、`evidence`。搜索未在首个命中处停止；六层分别执行并记录。

| 层 | 搜索路径 | 找到的文件 | 是否满足需求？ |
|---|---|---|---|
| App | `backend/app/` | 0 | 否；业务 App 层无 Harness 实现 |
| Core | `backend/pallastrade_gems/pallastrade_core/app/` | 0 | 否；Core 领域模型不承担工程治理 |
| API | `backend/pallastrade_gems/pallastrade_api/app/` | 0 | 否；API 层无同类能力 |
| Admin | `backend/pallastrade_gems/pallastrade_admin/app/` | 0 | 否；Admin 层无同类能力 |
| Storefront | `storefront/src/` | 0 | 否；Storefront 层无同类能力 |
| Platform | `platform/packages/` | 0 | 否；Platform 包未实现 Harness 引擎 |

### 搜索结论

PallasTrade 六个业务层均不应新增重复实现。现有通用能力位于独立 npm 包 `pallastrade-harness@0.2.3`，PallasTrade 仅通过 `harness.config.mjs`、`harness/policies/`、CI 和知识资产进行项目级配置。因此实现应进入独立仓库，PallasTrade 侧只做必要的版本接入、规范登记与 dogfood 验证。

现状还发现一项流程级缺口：当前单个 Gate 同时包含“编码前检查”和“实施后 verify-test”，导致 Gate 生命周期无法准确表达 pre / during / post 三阶段。该问题纳入本次可靠性基线和 Supervisor 生命周期设计，不继续增加人工清单来掩盖它。

## Step 1：Skill 与规范咨询

| Skill / 规范文件 | 状态 | 关键结论 |
|---|---|---|
| `AGENTS.md` | ✅ 已读 | Harness 变更必须走 feature gate、六层检索、客观验证和知识同步；PallasTrade 日常提交在 `dev` |
| `.github/copilot-instructions.md` | ✅ 已读 | Gate、REQ、用户确认和 verify evidence 是强制流程 |
| `ai/skills/pallastrade-prd/SKILL.md` | ✅ 已读 | 复用既有 PRD/路线图，需求确认后再实施；AC 必须映射测试并完成知识同步 |
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 本任务不是 Rails 领域扩展；应保持独立引擎与项目配置分离 |
| `ai/skills/pallastrade-testing/SKILL.md` | ✅ 已读 | 测试应验证行为而非实现细节；本包采用现有 `node:test` 合同测试，并在 PallasTrade 真实项目 dogfood |
| `platform/CLAUDE.md` | ✅ 已读 | 不直接提交到 `main`；重大架构变化应有计划与测试；文档解释能力、目的和用法 |
| `harness/policies/task-rules.json` | ✅ 已读 | TR-001/002/004/005/006 要求 REQ、Go/No-Go、跨层搜索、Skill 证据和客观验证 |
| `harness/policies/anti-patterns.json` | ✅ 已读 | 本任务不改变业务反模式；新增监督 Finding 必须引用机器可读规范 ID |
| `github:yeet` | ✅ 已读 | 发布前核对范围、显式暂存、提交、推送功能分支并创建 Draft PR |

不涉及 `pallastrade-admin`、`pallastrade-catalog`、API、Storefront、数据模型等领域 Skill；原因是六层检索确认这些业务层不在实现范围内。

## 需求标题

将 `pallastrade-harness` 从 Gate/扫描工具升级到具备可靠性基线、机器可读规范与实际开发监督能力的 0.4 MVP。

## 任务类型

功能优化 / 架构演进 / Harness 独立包版本升级。

## 需求描述

本次实施 `harness升级方案.md` 的下一阶段，即 Phase 0（0.3 可靠性基线）与 Phase 1（0.4 Standards Registry + Development Supervisor MVP）。交付重点是让 Harness 能够在编码前选择规范并形成 Change Plan、编码中识别范围漂移、编码后生成引用规范 ID 的结构化 Finding，同时先修复当前 0.2.3 已确认的 fail-open、Windows 参数和退出码契约问题。

本次不提前实施 Phase 2–6：完整 Task/Project Brain、多会话恢复、全领域 Supervisor、浏览器/数据库证据、MCP/TUI 和 1.0 兼容承诺继续保留在路线图中。当前版本会定义统一数据对象和稳定扩展边界，避免后续返工。

## 影响范围

`npx harness affected` 在当前 `dev` 相对 `origin/main` 输出：

```json
{
  "filesChanged": 251,
  "affectedComponents": ["harness", "ai", "backend", "platform", "storefront"],
  "errors": [],
  "estimatedTests": 753
}
```

该结果包含 `dev` 相对 `origin/main` 的既有 251 个文件差异，不是本任务的净变更范围。本任务计划范围如下：

- 独立仓库：`bin/`、`rules/`、`presets/`、测试、README/docs、CI；
- PallasTrade：本 REQ、升级方案/权威路线图同步、必要时更新 Harness 依赖与项目配置；
- 明确不改：Rails 业务模型/API/Admin、Storefront 业务代码、历史 migration、生成文件。

## 交付范围

### A. Phase 0 — 可靠性基线（0.3）

1. 修复 `init` 写错 Gate 配置层级，并确保 starter rules 真正初始化。
2. 统一 `--files` 在 Windows、POSIX、Lefthook 空格参数与逗号参数下的解析。
3. 修复 `eval-llm --check`、`report` 文件计数。
4. `generated:check`、插件加载/校验、Git diff 失败全部 fail-closed，并输出可行动错误。
5. 定义 CLI 退出码契约：成功 `0`、质量/策略失败 `1`、配置/调用错误 `2`、内部错误 `3`。
6. 定义并校验统一对象：`Task`、`Standard`、`Risk`、`Finding`、`Evidence`、`KnowledgeAsset`、`AgentRun`。
7. 把 Gate 生命周期拆成 pre / implementation / verification / finish 阶段，消除 `verify-test` 与预编码锁的矛盾，并提供旧 Gate 兼容迁移。

### B. Phase 1 — Standards Registry 与 Supervisor MVP（0.4）

1. 建立机器可读 Standards Registry，强制标准 ID、类别、权威来源、scope、severity、enforcement level、evidence、exception 和 knowledge impact 字段。
2. 提供规范列表、适用规范选择与 Standards Enforcement Coverage 报告。
3. 建立 `supervise plan`：根据 diff/计划输出允许范围、禁止范围、适用标准、风险和必需验证。
4. 建立 `supervise diff`：检查范围漂移、历史 migration/生成文件、依赖新增、架构边界、循环依赖、复杂度与新代码重复度基线。
5. Finding 必须包含规范 ID、文件/行号、问题、风险、修复建议、置信度和 blocking 状态。
6. Technology Choice Gate 对新增 npm/gem、顶层架构目录和基础设施配置变更自动要求 review。
7. 采用“只约束新增/修改代码”的增量基线，历史技术债务只报告不阻断。
8. 内置通用 starter standards；PallasTrade 项目标准通过项目配置/规则文件扩展，不硬编码进引擎。

## CLI 与数据契约（拟定）

```text
harness standards list [--category <name>] [--json]
harness standards select [--base <ref>] [--files ...] [--json]
harness standards coverage [--json]
harness supervise plan --task <text> [--base <ref>] [--allow <glob> ...] [--deny <glob> ...]
harness supervise diff [--base <ref>] [--plan <path>] [--json]
harness gate:migrate [--dry-run]
```

持久化对象使用带 `schemaVersion` 的 JSON；0.4 只承诺本地文件和 CLI 契约，不引入数据库、SaaS、OPA 或 LLM 阻塞判定。

## 验收标准

- AC-001：`init` 生成正确的 `gates.checkDefs`，starter rules 可立即被扫描器加载。
- AC-002：Windows/POSIX 的 `--files a b`、`--files a,b` 和路径含空格场景均有合同测试。
- AC-003：`eval-llm --check`、`report`、generated check、插件和 Git 失败路径返回约定退出码，关键路径不再 fail-open。
- AC-004：七类统一对象均通过 schema 校验；无效对象给出字段级错误。
- AC-005：现有 Gate 可迁移为分阶段生命周期；预编码检查完成后允许实施，verify/finish 仍保持阻塞语义。
- AC-006：每条 Standard 有唯一 ID 和执行等级；`standards coverage` 能区分 verified / review-required / documented。
- AC-007：基于 changed diff 自动选择适用 Standard，输出可复现且支持 JSON。
- AC-008：Change Plan 能声明 allow/deny scope；范围漂移生成引用 Standard ID 的 blocking Finding。
- AC-009：新增依赖和架构目录自动触发 Technology Choice review；未新增时不误报。
- AC-010：Code Quality / Architecture Supervisor 只对新增或修改代码执行复杂度、重复度与边界检查，历史债务不阻断。
- AC-011：所有 Finding 满足统一结构，且 JSON 输出不混入人类日志。
- AC-012：现有 0.2.3 命令保持兼容；`npm test`、CLI E2E、`npm pack --dry-run`、PallasTrade dogfood 均通过。
- AC-013：GitHub Actions 至少覆盖 Windows、Ubuntu、macOS 的 Node 22/24 合同测试。
- AC-014：独立仓库功能分支推送并创建面向 `main` 的 Draft PR；PallasTrade 集成变更在 `dev` 上提交/推送。

## 技术方案与 Change Plan

### 架构选择

采用“薄 CLI + 可测试领域模块 + Git adapter”结构：

```text
bin/harness.mjs
  -> command modules
  -> domain contracts / standards registry / supervisor
  -> adapters (git, filesystem, process)
```

确定性规则负责阻塞；LLM 仅作为未来语义 Review 的可选适配器。所有模块保持 Node 内置能力优先，不为 YAML、AST 或重复检测立即引入大型依赖；复杂检查通过 verifier/plugin 接口接入成熟工具。

### 允许修改

- 独立仓库 `bin/**`、`rules/**`、`presets/**`、`docs/**`、`.github/workflows/**`、`README.md`、`package*.json`、测试文件；
- PallasTrade 的 Harness 配置、需求/标准/场景/Agent 指针与依赖版本（仅实际需要时）。

### 禁止修改

- PallasTrade 业务层代码；
- 历史 migration、`schema.rb`、自动生成 API/SDK 文件；
- 与 Harness 无关的现有用户改动；
- 直接提交到任一仓库 `main`。

## 风险与恢复

| 风险 | 等级 | 控制与恢复 |
|---|---|---|
| 0.4 CLI 破坏 0.2.3 用户 | 高 | 合同测试覆盖所有既有命令；新命令增量加入；保留旧 Gate 读取与迁移 |
| fail-closed 造成误阻断 | 高 | 区分策略失败与配置/内部错误；输出下一步；在 PallasTrade dogfood |
| Supervisor 误报历史债务 | 高 | 默认 changed-lines/new-files baseline；全量审计需显式参数 |
| 规则权威冲突 | 中 | 标准对象必须记录 authority；重复 ID/冲突 scope 配置错误退出 |
| 跨平台 shell 差异 | 中 | 核心使用 `spawnSync` 参数数组；三系统 CI；Windows 本地实测 |
| 两仓库版本不同步 | 中 | 独立仓库先完成 PR；PallasTrade 只在可安装提交/版本确定后更新依赖 |

恢复点：实现前记录独立仓库分支、HEAD、工作树和 npm 版本；所有变更在功能分支完成，可通过关闭 Draft PR 或删除未合并分支恢复。除非用户另行授权，本任务不执行 npm 发布、不打 tag、不合并 PR。

## 验证计划

| 范围 | 最低验证 | 证据 |
|---|---|---|
| 合同与领域模块 | `npm test` | node:test 通过数与退出码 |
| CLI 生命周期 | 临时项目执行 init → gate migrate/pre → supervise → verify/finish | 命令日志 + 产物 JSON |
| 包完整性 | `npm pack --dry-run` | tarball 文件清单 |
| 跨平台 | GitHub Actions Windows/Ubuntu/macOS | workflow checks |
| PallasTrade dogfood | `npx harness config:check`、扫描、standards、supervise、quick profile | 命令证据包 |
| 文档/知识 | `harness docs:check`、`doc-impact`、`eval ai --check-freshness` | 0 missing / 场景通过 |

## Go / No-Go

建议：**有条件 Go**。

条件：本次只交付 Phase 0 + Phase 1（0.4 MVP），不把 0.5–1.0 的 Project Brain、全领域 Supervisor、完整 Evidence/Recovery、Agent MCP/TUI 压进同一个 PR；同时不执行 npm publish 或 PR merge。这样可以先建立可靠数据契约与开发监督主轴，再由后续版本消费。

## 决策节点

> ⏸️ 请确认以下实施边界：**本次完成 0.3 可靠性修复 + 0.4 Standards Registry / Development Supervisor MVP，推送独立仓库功能分支并创建 Draft PR；PallasTrade 侧只做必要集成和知识同步；不发布 npm、不合并 PR。**

收到明确“确认 / Go / 实施”后进入编码。

## 实施后知识同步结论

| 资产 | 结论 |
|---|---|
| `AGENTS.md` | 已更新：登记机器可读 Standards Registry、升级方案与 Development Supervisor 三阶段流程 |
| `ai/skills/pallastrade-prd/SKILL.md` | 已更新：Change Plan、diff 监督、分阶段 Gate 和 finding 可追溯要求 |
| `.github/copilot-instructions.md` | 已评估，无需更新：该文件保持强制命令速查，权威流程继续指向 `AGENTS.md`，未复制 Supervisor 细节 |
| `harness/scenarios/scenarios.json` | 已更新：新增 GS-020（开发监督闭环）与 GS-021（知识路径漂移） |
| `docs/standards/README.md` / 路线图 | 已更新：登记产品蓝图、项目级注册表和 0.4 候选实施记录 |
| `ai/skills/pallastrade-typescript-sdk/SKILL.md` | dogfood 发现并修正真实知识漂移：不再声称当前 checkout 存在缺失的 admin-sdk 源码路径 |
| API / DB / UI 领域文档 | 已评估，不适用：本次没有业务接口、数据模型或 UI 行为变更 |

`sync-check --base HEAD` 只命中本任务的 Skill / PRD 机制资产；此前未指定 base 的输出混入 `dev` 相对 `origin/main` 的既有 251 文件差异，因此 0.4 增加了任务级 `--base` 支持。

## Technology Choice Review

新增直接依赖 `minimatch` 用于 Standard scope、Change Plan 和架构边界的统一 glob 语义。自研匹配器会在 globstar、brace、dotfile 与 Windows 路径上产生不一致；依赖 `glob` 的传递安装也不是稳定契约。`minimatch` 已属于现有 `glob` 生态，锁文件与 Node 22/24 CI 控制维护风险；匹配入口集中在 `matchesScope`，退出成本低。结论：接受该非阻断 finding。

## 实施后验证

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| Harness Node 代码 | `bin/*.mjs` + contract/reliability/supervisor tests | `npm test` | 40/40 通过（最终提交前再跑） | ✅ |
| CLI / 数据契约 | CLI E2E、7 类 contract、Gate migration | CLI E2E + exit-code matrix | init → plan → phased gate → verify/finish 通过；0/1/2/3 契约覆盖 | ✅ |
| Package | `package.json` / lockfile / rules | `npm pack --dry-run` | 0.4.0 tarball 预检通过 | ✅ |
| PallasTrade 集成 | config / standards / Agent / Skills / scenarios | dogfood + `harness check --profile quick` | config valid；27 Standards / 48.1% machine coverage；quick profile 通过；supervise diff 0 blocking | ✅ |
| 知识资产 | docs / Skills / scenarios | docs-check / nav-check / doc-impact / eval freshness | 26 docs 无断链；17 导航引用有效；doc-impact 3/3；25 Skills 0 path error；场景最终复验待提交前执行 | ✅ |
| 跨平台 CI | `.github/workflows/test.yml` | Windows/Ubuntu/macOS × Node 22/24 | Workflow 已配置；远端结果待 PR checks | ⏳ |
