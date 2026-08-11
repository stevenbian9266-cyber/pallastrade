# Harness 完整生命周期治理 0.5–1.0

> Gate：`GATE-2026-08-11T15-01-03`
> 方案来源：`harness升级方案.md`（已批准）
> 前置交付：`REQ-20260811-harness-supervisor-mvp.md` / `pallastrade-harness@0.4.0-rc`
> 目标仓库：`stevenbian9266-cyber/pallastradeharness`
> 用户授权：2026-08-11 明确要求“继续完成剩下的阶段，全部完成后，统一合并发布”

## Step 0：跨层搜索

统一关键词：`project brain`、`task orchestrator`、`risk engine`、`development supervisor`、
`evidence bundle`、`knowledge loop`、`recovery plan`、`checkpoint`、`resume task`。
六层分别搜索，没有在首个命中处停止。

| 层 | 搜索路径 | 命中 | 是否满足需求？ |
|---|---|---:|---|
| App | `backend/app/` | 0 | 否；业务 App 不承担通用 SDLC 治理 |
| Core | `backend/pallastrade_gems/pallastrade_core/app/` | 0 | 否；Core 领域模型不应实现 Harness 引擎 |
| API | `backend/pallastrade_gems/pallastrade_api/app/` | 0 | 否；API 层无任务编排或证据引擎 |
| Admin | `backend/pallastrade_gems/pallastrade_admin/app/` | 0 | 否；Admin UI 无同类能力 |
| Storefront | `storefront/src/` | 0 | 否；Storefront 不属于实现层 |
| Platform | `platform/packages/` | 0 | 否；Platform 包没有 Harness 引擎 |

### 搜索结论

剩余能力必须继续实现于独立 npm 包。PallasTrade 只负责项目画像、项目规范、风险配置、
知识资产映射和真实仓库 dogfood，不在六个业务层复制任何编排或监督实现。

## Step 1：Skill 与规范咨询

| Skill / 规范 | 状态 | 关键结论 |
|---|---|---|
| `AGENTS.md` | ✅ 已读 | 变更必须遵循分阶段 Gate、六层检索、客观证据、知识同步和 `dev → main` 发布策略 |
| `.github/copilot-instructions.md` | ✅ 已读 | 实现前必须完成 preparation；`verify-test` 只能在客观证据完成后结束 |
| `ai/skills/pallastrade-prd/SKILL.md` | ✅ 已读 | 沿用已批准权威方案，Change Plan 与验收标准必须可追溯，发布前完成知识同步 |
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 该任务不属于 Rails 扩展点；引擎与项目配置应继续解耦 |
| `ai/skills/pallastrade-testing/SKILL.md` | ✅ 已读 | 测试验证外部行为和恢复能力；独立包用 `node:test`，PallasTrade 做真实项目 dogfood |
| `harness/policies/task-rules.json` | ✅ 已读 | TR-001/002/004/005/006 要求 REQ、设计、搜索和客观验证证据 |
| `harness/policies/anti-patterns.json` | ✅ 已读 | 不修改业务反模式；领域 Supervisor 的 Finding 必须引用 Standard ID |
| `github:yeet` | ✅ 已读 | 发布前核对范围、显式提交、推送、PR 检查；本机缺少 `gh`，使用既有 Git 凭据/API 回退 |

`pallastrade-admin`、API、Storefront、数据模型等业务 Skill 不适用，因为六层业务代码明确不在变更范围。

## 需求标题

完成 `pallastrade-harness` Phase 2–6，把 0.4 的规范与开发监督 MVP 升级为可发布的 AI 原生软件开发生命周期治理 1.0。

## 任务类型

功能优化 / 架构演进 / npm 主版本发布。

## 目标与非目标

### 目标

1. 用持久化任务状态、Project Brain 和 handoff package 支持跨会话、跨 Agent 续接。
2. 让 Risk Engine 自动选择 Quick / Standard / Critical，并在实际 Diff 扩大时升级风险。
3. 补齐 Database、API、Security、UI Style、Interaction、Accessibility、Knowledge 专项监督。
4. 让命令、测试、构建、截图、DOM、日志、数据库、Review、审批和知识评估成为 typed evidence。
5. 为高风险任务生成与校验恢复检查点、停止条件和恢复步骤。
6. 用统一 Knowledge Loop 保存 `updated / reviewed-no-change / not-applicable` 三种正式结果。
7. 提供 Agent adapters、stdio MCP、无依赖 TUI/状态视图、技术栈 preset、风险包和下一步建议。
8. 稳定插件/配置协议，支持配置迁移、缓存、大型 monorepo、worktree/并发任务、可选 GitHub checks。
9. 在独立仓库合并后通过 OIDC tag workflow 发布 1.0，并在 PallasTrade 升级依赖、验证、合并发布。

### 非目标

- 中央 SaaS、组织级 RBAC、OPA、供应链签名和远程数据库；
- 自研完整 Sonar/Semgrep/axe/浏览器或数据库引擎；这些通过 verifier/adapter 调用成熟工具；
- 让 LLM 成为唯一阻塞边界；语义 Review 只能提供结构化建议或由项目策略显式提升；
- 修改 PallasTrade Rails、Storefront 或 Platform 业务代码；
- 在没有证据时把历史技术债务一次性升级成阻塞错误。

## 影响范围

`npx harness affected --base HEAD --json` 在 PallasTrade 当前提交返回 0 个变更；本任务计划范围：

- 独立仓库：`bin/**`、`presets/**`、`rules/**`、`docs/**`、`.github/**`、`README.md`、`package*.json`；
- PallasTrade：本 REQ、Harness 依赖/lockfile、`harness.config.mjs`、项目 standards/场景/Agent/Skill/路线图；
- 禁止：业务六层、历史 migration、`schema.rb`、生成 API/SDK 文件和无关用户改动。

## 总体架构

```text
CLI / TUI / stdio MCP
        |
Task Orchestrator ---- Task Store / Locks / Handoff
        |
        +-- Project Brain ---- ProjectProfile / Knowledge Index / Context Pack
        +-- Risk Engine ------ Quick / Standard / Critical / escalation
        +-- Standards Registry
        +-- Domain Supervisors / verifier adapters
        +-- Evidence Engine -- typed records / verification policy / delivery report
        +-- Recovery Engine -- checkpoint / plan / restore verification
        +-- Knowledge Engine - impact / assessment / candidate update / freshness
```

核心保持本地优先、Git-native、JSON 可审计、原子写入、确定性检查优先。所有持久化对象包含
`schemaVersion`、稳定 ID、项目/任务作用域、Git/worktree identity 和时间戳。

## 分阶段交付与 CLI 契约

### Phase 2 — Task Orchestrator 与 Project Brain（0.5）

- `harness task start|status|checkpoint|resume|finish|abandon|list`
- 状态机：`draft → planned → approved → implementing → reviewing → verifying → completed`，
  支持 `paused / blocked / cancelled / superseded`，非法转换失败并保持原状态。
- 并发安全：每任务独立目录、原子写入和 lock；task 绑定 repository、branch、HEAD、worktree。
- `harness brain index|context|decision|status`：生成 ProjectProfile、KnowledgeAsset 索引、最小上下文包和历史决策。
- `harness task handoff` 输出不含秘密的 Agent 交接包，包含目标、范围、标准、证据、阻塞和下一步。
- Risk Engine 基于用户声明、文件路径和代码语义取最大风险，支持 diff 后自动升级。

### Phase 3 — 领域 Supervisor（0.6）

- `harness supervise review --domains <...>` 统一编排领域 verifier；`supervise diff` 自动选择适用领域。
- Database：migration 可逆性、数据回填、大表/索引/外键/null/default、多租户、schema drift、恢复要求。
- API/Security：原始 HTTP、认证/权限、秘密、高风险命令、公共 API 文档/兼容性信号。
- UI/Interaction/A11y：设计系统/token、重复组件、状态矩阵、重复提交、destructive confirmation、键盘/焦点/a11y 证据。
- Knowledge：引用、权威冲突、Skill freshness、PRD/实现/API 示例漂移。
- 确定性 verifier 产生 blocking Finding；未配置外部工具时明确 `not-run`，不得伪造通过。

### Phase 4 — Evidence 与 Recovery（0.7）

- `harness evidence run|record|list|verify|bundle|report`；记录命令、时间、退出码、工具版本、Git 状态和文件 hash。
- `verify-test` 由满足任务风险与 Standards 要求的有效 evidence 自动完成；手工 clear 不再替代证据。
- `harness recovery create|status|verify` 保存非破坏性恢复检查点与步骤；不自动执行 destructive restore。
- Critical 任务必须有失败判断、停止条件、代码/数据恢复方案及恢复验证。
- `task finish` 生成交付报告，列出修改、规范结果、证据、知识状态、未解决 Finding 和剩余风险。

### Phase 5 — Agent 生态与体验（0.8）

- `harness adapter generate|list` 从同一策略生成 AGENTS/Claude/Copilot/Cursor/Generic 适配片段，标记 managed block，保留用户内容。
- `harness mcp` 实现本地 stdio JSON-RPC/MCP tools：project context、task lifecycle、standards、risk、decision、evidence、review、finish。
- `harness tui` 提供可脚本化的任务/风险/证据/下一步状态视图；非交互环境自动降级文本/JSON。
- 官方 stack presets、risk packs、standards packs；自动修复只输出建议或显式 `--apply`，默认不写代码。

### Phase 6 — 稳定版本（1.0）

- 插件 API/version capability negotiation；旧插件给出迁移提示，未知/不兼容插件 fail-closed。
- `harness config:migrate` 与 state migration 支持 dry-run、备份提示、幂等迁移和向后读取。
- 内容寻址缓存、monorepo 分片、worktree identity、并发任务 lock 与缓存隔离。
- `harness ci github` 生成可选 workflow/required-check 建议，不直接修改 GitHub 分支保护。
- 完整参考文档、迁移指南、样例项目、兼容性表、性能预算和发布检查表。

## 数据与兼容契约

在 0.4 七类对象基础上新增并导出：

```text
ProjectProfile, ChangePlan, Decision, ContextPack, TaskCheckpoint,
EvidenceBundle, RecoveryPlan, KnowledgeAssessment, HandoffPackage
```

- 0.2/0.4 既有 CLI 保持兼容；弃用项至少保留一个主版本并输出机器可读 warning。
- 所有 JSON 输出 stdout 纯 JSON；日志写 stderr；稳定退出码继续为 0/1/2/3。
- schema migration 是幂等、可 dry-run、写前原子备份；未知未来 schema 拒绝降级读取。
- 1.0 插件协议不保证插件内部实现，但保证 manifest、capability、输入输出和错误语义。

## Change Plan

### 独立仓库允许修改/新增

- 领域模块：Task/Brain/Risk/Evidence/Recovery/Knowledge/Adapters/MCP/TUI/CI/State Store；
- 对应 `*.test.mjs` 合同与 E2E；
- 现有 CLI、contracts、config、plugins、supervisor、gate lifecycle 的兼容扩展；
- presets/rules、README、docs、示例和 GitHub workflows；
- 版本与 lockfile。

新增领域文件是必要的：现有 0.4 模块只覆盖 contracts、standards、gate 和 supervisor，继续堆入
`harness.mjs` 或 `supervisor.mjs` 会形成 God module，并破坏插件和 1.0 public exports 边界。

### PallasTrade 允许修改

- `package.json` / lockfiles：升级正式发布版本；
- `harness.config.mjs`、`harness/standards/**`、场景与知识导航：启用/记录新能力；
- 本 REQ、总体方案/路线图、必要的 Skill/Agent 指针；
- 不修改六层业务代码。

### 明确禁止

- 直接在功能分支之外混入无关改动；
- 直接覆盖用户维护的 Agent/知识文件；
- 把截图、日志、DB 内容伪装成已执行证据；
- 自动执行数据库恢复、强制 push、历史重写或分支保护变更；
- 在独立包中硬编码 PallasTrade 路径、标准或业务语义。

## 验收标准

- AC-201：合法/非法/暂停/恢复/跨会话任务状态均有合同测试，交接包可在新进程恢复。
- AC-202：Project Brain 只选择相关知识资产，索引 hash 变化可检测 freshness，秘密文件不进入上下文包。
- AC-203：Quick/Standard/Critical 结果可解释；高风险文件或语义使任务只升不降，除非有记录的显式 override。
- AC-204：任务和缓存按 repo/worktree/task 隔离；并发写入不会产生损坏 JSON。
- AC-301：六类领域 Review 至少各有正/负合同案例，所有 Finding 引用 Standard ID 和源码位置。
- AC-302：DB 高风险变更要求恢复计划；UI 任务要求状态矩阵和截图/DOM/a11y 证据；未执行 verifier 显式报告。
- AC-303：领域 Supervisor 默认只检查 changed/new code，不用历史债务阻断当前任务。
- AC-401：九类 typed evidence 可记录、校验 hash/HEAD freshness，过期或失败证据不能完成验证。
- AC-402：证据策略满足后自动完成 `verify-test`；缺证据、错误 commit 或错误 worktree 必须拒绝。
- AC-403：Critical checkpoint/recovery plan 完整；恢复命令只作为人工步骤输出，不自动运行。
- AC-404：交付报告完整列出已验证、未运行、剩余风险和知识评估，不把 unknown 变成 success。
- AC-501：Codex/Claude/Copilot/Cursor/Generic adapters 来自同一策略，managed block 更新幂等且保留用户文本。
- AC-502：stdio MCP 完成 initialize、tools/list、tools/call，并覆盖方案列出的十个核心工具；协议错误可诊断。
- AC-503：TUI 在 TTY 与 CI/pipe 下均可用，提供 JSON/text 输出和明确下一步。
- AC-601：插件/配置/state 迁移合同覆盖旧版本、当前版本、未来版本和失败回滚；0.2/0.4 CLI 回归全绿。
- AC-602：大型 monorepo/Unicode/空格路径/worktree/并发 task 合同通过，缓存不跨作用域污染。
- AC-603：样例项目可完成 init → task → context → plan → supervise → evidence → knowledge → finish。
- AC-604：三系统 Node 22/24 CI、`npm test`、`npm pack --dry-run`、自监管和 PallasTrade dogfood 全绿。
- AC-605：PR 合并后 `v1.0.0` OIDC 发布成功，registry/provenance 可查询；PallasTrade 锁定正式版本并通过发布门。

## 风险、自我保护与恢复

| 风险 | 等级 | 控制 | 恢复 |
|---|---|---|---|
| 一次跨越五个阶段造成接口漂移 | 高 | 每阶段独立领域模块、测试与提交；最终一次合并发布 | 功能分支逐提交 revert，不改已发布 0.2.3 |
| 自动验证误把旧证据当新证据 | Critical | 绑定 repo/worktree/HEAD/hash/command/tool version | 拒绝 finish，重新采集证据 |
| MCP/插件成为任意命令入口 | Critical | allowlist、参数 schema、项目根边界、无 shell 拼接 | 禁用 capability / 回退 CLI |
| 状态并发写损坏 | 高 | lock + temp file + atomic rename + stale-lock 规则 | 从最近 checkpoint/备份恢复 |
| 领域规则误报 | 高 | changed-code baseline、confidence、assist/guard/strict | 降级到 review-required 并记录例外 |
| Adapter 覆盖用户规则 | 高 | managed markers、dry-run、原文件备份提示 | 恢复 managed block 前内容 |
| 1.0 破坏消费者 | 高 | 既有 CLI golden/contract、npm pack、真实 PallasTrade dogfood | 不打 tag；修复分支后重跑 |
| 发布中断 | 中 | PR checks → merge → tag → OIDC workflow → registry verify | tag 不发布则修复 workflow 后重跑；不重复 bump |

发布前恢复点：记录两个仓库 branch/HEAD/worktree；所有引擎变更留在现有功能分支；PallasTrade
保持 `dev`。不使用 force push，不执行 destructive 数据操作。

## 验证与发布计划

1. 每阶段：领域合同测试、CLI E2E、旧命令回归、自监管 diff。
2. 1.0 候选：全量 `npm test`、pack 内容、示例项目 E2E、性能/并发/迁移测试。
3. 远端：Windows/Ubuntu/macOS × Node 22/24 全绿，将 Draft PR 转 ready 后 squash/merge 或 merge commit。
4. 发布：在合并后的独立仓库 `main` 创建 `v1.0.0` tag，监控 OIDC publish workflow，查询 npm registry/provenance。
5. 消费：PallasTrade `dev` 升级到正式版，运行 config/doctor/standards/task/supervisor/evidence/docs/quick/full 适用检查。
6. 知识同步：总体方案、路线图、AGENTS/PRD Skill、场景、README 与迁移文档更新；逐项记录三态结论。
7. PallasTrade 所有 CI 通过后，按分支策略把 `dev` 合入 `main` 并推送；不跳过失败检查。

## Go / No-Go

结论：**Go**。

依据：用户已明确扩大上一轮边界，要求完成所有剩余阶段并在全部完成后统一合并发布。实现必须保持阶段化提交、
一份最终 PR/正式 tag、无业务层修改，以及任何失败都阻止发布。

## 实施后填写

### 知识同步三态

| 资产 | 结果 | 证据/理由 |
|---|---|---|
| `AGENTS.md` / copilot instructions | updated | 新增 Task/Brain/Risk、task-bound Gate、typed evidence 与恢复流程 |
| PRD Skill | updated | PRD 实施与收尾改为 task → knowledge/evidence → finish；testing Skill 已评估，无测试框架变化 |
| 总体方案 / Harness 路线图 | updated | 标记 Phase 0–6 完成并登记 v5.0 实施记录 |
| Harness README/docs/examples/migration | updated | 独立包已补生命周期、迁移、命令、配置、插件协议和单项目示例 |
| Standards / risk packs / scenarios | updated | 增加 DB/API/Security/UI/Interaction/A11y/Knowledge 标准及 GS-022~024 |
| API / DB / UI 业务文档 | not-applicable | 未修改六层业务代码、接口、数据库或 UI |

### 最终验证

| 范围 | 命令/证据 | 结果 |
|---|---|---|
| 独立包合同与 E2E | `npm test` | 1.0.0：66/66；1.0.1/1.0.2：68/68；1.0.3：70/70 通过 |
| 包内容 | `npm pack --dry-run` | 89 个预期文件，0 漏洞 |
| 自监管 | `harness supervise diff` | 独立包与 PallasTrade 最终 diff 均为 0 findings / 0 blocking |
| 跨平台 CI | GitHub Actions matrix | 1.0.0–1.0.3 的 PR/push 两事件矩阵均为 12/12 jobs 全绿 |
| npm 发布 | tag workflow + registry/provenance | `v1.0.0`–`v1.0.3` 均经 OIDC 发布成功，registry 返回 SLSA v1 provenance |
| PallasTrade dogfood | quick/full + generated/docs/eval + lifecycle E2E | quick、generated、docs、24/24 场景、25/25 Skill freshness、doc-impact 与生产依赖审计通过；full 中委派项由 GitHub CI 执行 |
| PallasTrade 发布 | dev CI + dev→main | 本地发布门通过；提交后等待 dev CI 全绿再合并 main，任何失败均阻止发布 |
