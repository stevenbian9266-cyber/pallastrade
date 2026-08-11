# PallasTrade Harness 总体升级方案（整合版）

> 实施状态：✅ Phase 0–6 已于 2026-08-12 完成；独立包 `pallastrade-harness@1.0.3` 已通过
> Windows/macOS/Ubuntu × Node 22/24 CI、npm OIDC 发布与 SLSA provenance 验证；PallasTrade dogfood
> 发现的上下文精度、状态迁移幂等性和生成物基线误报由兼容补丁 `1.0.1`–`1.0.3` 修正。本文件继续作为产品与架构蓝图。

## 一、产品定位

更准确的定位应该是：

> 面向独立开发者的 AI 原生工程操作系统：让 AI 持续理解项目、按工程规范实施、主动规避风险、提供验证证据，并在任务结束后更新项目知识。

它不只是 Gate，也不是代码扫描器，而是贯穿完整开发生命周期：

```text
理解项目
→ 接收任务
→ 准备上下文
→ 判断风险
→ 选择适用规范
→ 制订实施方案
→ 监管实际编码
→ 验证结果
→ 保存证据
→ 更新知识
→ 支持恢复和续接
```

## 二、总体能力模型

下一阶段应形成七个相互配合的核心系统。

| 核心系统 | 解决的问题 |
|---|---|
| Project Brain | AI 是否真正理解当前项目 |
| Task Orchestrator | 任务如何开始、推进、暂停和结束 |
| Risk Engine | 当前任务应该采用多严格的流程 |
| Standards Registry | 项目到底有哪些规范，哪些能机器执行 |
| Development Supervisor | AI 实际写出的代码是否符合规范 |
| Evidence & Recovery | 如何证明结果正确，失败后如何恢复 |
| Knowledge Loop | 代码变化后，文档、Skill、决策如何回写 |

再通过 Agent Adapters 把这些能力提供给 Codex、Claude、Copilot、Cursor 等不同工具。

## 三、完整任务生命周期

目标流程应该是：

```text
1. Task Start
   接收需求并识别任务类型

2. Context Build
   搜索已有代码、历史 PRD、Skills、架构决策

3. Risk Assess
   判断代码、数据、支付、权限、API、部署等风险

4. Standards Select
   选择本次变更必须遵守的技术、数据库、样式、交互规范

5. Change Plan
   确定实现方式、允许修改的文件、测试和恢复方案

6. Supervised Implementation
   监管实际文件修改、架构边界、代码复杂度和范围偏移

7. Specialized Review
   执行架构、代码质量、数据库、UI、交互、安全专项检查

8. Verification
   自动运行测试、构建、浏览器、日志、数据库验证

9. Evidence Bundle
   保存测试、截图、日志、Diff、风险和未解决事项

10. Knowledge Sync
    更新 PRD、Skill、README、标准和架构决策

11. Task Finish
    输出交付报告、剩余风险和下一步建议
```

## 四、Project Brain：项目大脑

Harness 应建立统一的项目知识模型，而不是让 AI 每次重新阅读整个仓库。

建议定义以下核心对象：

```text
ProjectProfile
Task
ChangePlan
Standard
Decision
Risk
Finding
Evidence
KnowledgeAsset
AgentRun
```

### ProjectProfile

保存：

- 技术栈；
- 项目层次；
- 开发命令；
- 测试命令；
- 生成器；
- 核心依赖；
- 风险领域；
- 权威规范入口。

### KnowledgeAsset

覆盖：

- AGENTS；
- CLAUDE；
- Skills；
- README；
- API 文档；
- PRD；
- ADR；
- 数据模型说明；
- 样式规范；
- 交互规范。

每个知识资产记录：

- 权威来源；
- 关联代码；
- 适用领域；
- 最后验证时间；
- 来源文件 hash；
- 是否可能过期；
- 是否属于 AI 派生摘要。

### 自动上下文包

每次任务开始，根据任务生成最小上下文：

```text
相关代码层
相关模型和服务
相关 Skill
相关历史 PRD
相关技术决策
适用标准
已有测试
已知风险
建议修改位置
禁止修改位置
```

目标是让 AI 读取“当前任务真正需要的内容”，而不是吞入整个仓库。

## 五、Task Orchestrator：任务管理

建议支持完整任务状态：

```text
draft
→ planned
→ approved
→ implementing
→ reviewing
→ verifying
→ completed

任意阶段
→ paused / blocked / cancelled / superseded
```

建议提供这些能力：

```text
task start
task status
task checkpoint
task resume
task finish
task abandon
```

任务状态保存：

- 原始需求；
- 目标和非目标；
- 验收标准；
- 风险等级；
- 适用规范；
- 修改计划；
- 已完成步骤；
- 当前阻塞；
- 修改文件；
- 已执行测试；
- 关键决策；
- 下一步动作。

这样任务可以跨：

- 会话；
- 上下文压缩；
- 工作日；
- AI Agent；
- worktree；
- 临时中断。

## 六、Risk Engine：风险自适应流程

不要对所有任务执行同一套 Gate。

### Quick

适用：

- 文案；
- 注释；
- 明确的小型样式修改；
- 单文件低风险修复。

流程：

```text
自动搜索
→ 最小规范检查
→ 实施
→ 最小验证
```

### Standard

适用：

- 普通功能；
- 多文件 Bug；
- 一般 API 修改；
- 常规重构。

流程：

```text
任务说明
→ 验收标准
→ 影响分析
→ 标准选择
→ 实施监管
→ 自动验证
→ 知识评估
```

### Critical

适用：

- 数据库迁移；
- 支付；
- 权限认证；
- 删除数据；
- 公共 API；
- 部署；
- 密钥；
- 基础架构调整。

流程：

```text
完整 PRD/REQ
→ 技术设计
→ 风险和恢复方案
→ 明确确认
→ 监管实施
→ 全量验证
→ 交付证据
```

风险由三部分决定：

```text
最终风险 = max(
  用户声明风险,
  文件路径风险,
  代码语义风险
)
```

例如即使任务描述是“简单优化”，只要出现 migration、权限代码或支付文件，就应自动升级为 Critical。

## 七、Standards Registry：规范注册中心

这是实际开发监管的基础。

当前自然语言规范需要转成机器可索引的标准对象。

示例：

```yaml
id: STD-DB-003
category: database
title: 数据回填不得放入 migration

authority:
  file: platform/CLAUDE.md
  section: Migrations

scope:
  - backend/**/db/migrate/**/*.rb

severity: error

enforcement:
  type: ast
  verifier: migration-safety

evidence:
  - migration-analysis
  - rollback-plan

exception:
  allowed: true
  requiresReason: true
```

每条规范必须明确：

- ID；
- 类型；
- 权威来源；
- 适用范围；
- 严重程度；
- 检查方式；
- 验证证据；
- 修复建议；
- 允许的例外；
- 触发的知识回写。

### 规范类别

至少包括：

```text
architecture
technology-selection
code-quality
database
api
security
ui-style
interaction
accessibility
testing
documentation
knowledge
deployment
```

### 执行等级

不是所有规范都应该阻塞：

```text
documented     只存在于文档
advisory       AI 或工具给出建议
review-required 必须完成专项 Review
verified       有自动 verifier
blocking       失败时禁止完成任务
critical       失败时禁止合并或发布
```

## 八、规范覆盖率

新增一个核心指标：

> Standards Enforcement Coverage

例如：

| 领域 | 规范数 | 自动检查 | AI Review | 仅文档 |
|---|---:|---:|---:|---:|
| 架构 | 20 | 4 | 10 | 6 |
| 代码质量 | 25 | 8 | 10 | 7 |
| 数据库 | 15 | 5 | 7 | 3 |
| 样式 | 12 | 4 | 5 | 3 |
| 交互 | 18 | 2 | 7 | 9 |
| 知识回写 | 10 | 4 | 4 | 2 |

Harness 应能报告：

```text
规范总数：100
机器执行：23
专项 Review：43
仅文档：34

主要缺口：
- 交互规范机器覆盖率过低
- 数据库恢复规范未执行
- 后端复杂度规范未接入 CI
```

这能避免“规范很多，但没有真正执行”的假象。

## 九、Development Supervisor：开发监督器

这是下一阶段最重要的新主轴。

它不只检查最终结果，而要覆盖实施前、实施中和实施后。

## 实施前监督

检查：

- 是否已有相同能力；
- 是否使用正确扩展方式；
- 是否引入不必要依赖；
- 修改计划是否完整；
- 是否触及高风险文件；
- 是否有测试方案；
- 是否有恢复方案；
- 是否选择了正确标准。

输出 Change Plan：

```text
允许修改：
- backend/app/subscribers/...
- spec/subscribers/...

禁止修改：
- 历史 migration
- schema.rb
- generated types

必须遵守：
- STD-EVENT-001
- STD-STORE-002
- STD-TEST-004
```

## 实施中监督

持续检查：

- 修改文件是否超出范围；
- 是否创建与已有能力重复的文件；
- 是否违反架构层次；
- 是否出现新的高风险操作；
- 是否新增不必要依赖；
- 是否产生明显复杂代码；
- 是否出现循环依赖；
- 是否绕过 SDK、设计系统或数据隔离；
- 增量 lint/typecheck 是否失败。

如果修改范围发生重大变化：

```text
原计划只修改 Storefront
现在开始修改 API 和数据库
→ 重新评估风险
→ 重新选择规范
→ 要求更新 Change Plan
```

## 实施后监督

对 Diff 执行专项 Review：

```text
Architecture Review
Technology Choice Review
Code Quality Review
Database Review
API Review
UI Style Review
Interaction Review
Accessibility Review
Security Review
Knowledge Review
```

每个 Finding 必须包含：

```text
规范 ID
文件和行号
问题描述
风险
修复建议
置信度
是否阻塞
```

LLM Review 不能只说“代码质量不错”，必须引用具体规范和代码。

## 十、专项 Supervisor

## 1. Architecture Supervisor

监管：

- 层次依赖；
- 模块边界；
- 依赖方向；
- 事件与 Service 的职责；
- DI、Decorator、Subscriber 的选择；
- 循环依赖；
- 领域逻辑放置位置；
- API 与业务层耦合。

## 2. Technology Choice Supervisor

当出现以下情况自动触发：

- 新增 npm/gem；
- 新状态管理库；
- 新数据库或缓存；
- 新消息系统；
- 新外部 SaaS；
- 新顶层架构目录；
- 新认证方案。

要求轻量 ADR：

```text
问题
现有方案为什么不够
候选方案
选择理由
维护成本
安全风险
退出成本
为什么不复用现有技术
```

## 3. Code Quality Supervisor

检查：

- 重复代码；
- 方法复杂度；
- 文件、类、模块长度；
- 嵌套深度；
- 参数数量；
- God Object；
- 巨型 Controller/Service；
- 无用代码；
- 相似逻辑分散；
- 命名一致性；
- 可测试性；
- 测试是否验证行为。

采用“新代码基线”，避免历史技术债务一次阻断所有开发。

## 4. Database Supervisor

检查：

- migration 是否可逆；
- 数据回填是否放在 migration；
- 大表锁风险；
- 索引；
- 外键；
- null/default 变更；
- 多租户隔离；
- schema drift；
- N+1；
- 数据完整性；
- 回滚方案；
- 验证 SQL。

高风险数据修改要求：

```text
备份提示
执行前查询
执行后查询
回滚方式
停止条件
```

## 5. UI Style Supervisor

检查：

- 是否复用设计系统组件；
- 颜色、字号、间距是否使用 token；
- 是否创建重复组件；
- 响应式布局；
- 组件 variants；
- 图标和 Logo；
- 暗色模式；
- 视觉一致性。

## 6. Interaction Supervisor

每个页面或交互组件检查状态矩阵：

```text
正常
加载
空数据
错误
降级
无权限
禁用
提交中
成功
移动端
键盘
焦点恢复
屏幕阅读器
```

重点监管：

- 重复提交；
- destructive confirmation；
- modal/drawer 关闭；
- loading 与 disabled；
- inline error 与 toast；
- optimistic update；
- retry；
- fallback；
- self-redirect；
- 键盘和焦点。

验证方式：

- 组件测试；
- axe/a11y；
- DOM snapshot；
- 浏览器截图；
- 视觉回归；
- AI 对照规范 Review。

## 7. Knowledge Supervisor

检查：

- 代码事实与文档是否一致；
- Skill 是否过期；
- 文档是否引用不存在的文件或章节；
- PRD 与最终实现是否一致；
- API 示例是否仍然正确；
- 多份规范是否冲突；
- 是否产生了新的架构决策。

## 十一、Evidence：证据系统

证据对独立开发者的意义不是合规，而是回答：

> 我怎么知道 AI 真的做对了？

证据类型：

```text
CommandEvidence
TestEvidence
BuildEvidence
ScreenshotEvidence
DomEvidence
LogEvidence
DatabaseEvidence
ReviewEvidence
ApprovalEvidence
KnowledgeEvidence
```

每条证据至少绑定：

- Task；
- Commit/工作区状态；
- 命令；
- 时间；
- 退出码；
- 工具版本；
- 文件 hash；
- 结果摘要。

最终生成交付报告：

```text
任务：新增分类管理
修改：8 个文件

规范检查：
  ✓ Architecture
  ✓ Database
  ✓ Code Quality
  ✓ UI Style
  ⚠ Interaction：未验证移动端键盘操作

验证：
  ✓ RSpec
  ✓ Typecheck
  ✓ E2E
  ✓ DB before/after query
  ✓ Screenshot

知识：
  ✓ PRD 已更新
  ✓ Storefront Skill 已更新
  ✓ API 文档无需修改

剩余风险：
  - 大分类树性能仅使用测试数据验证
```

`verify-test` 应由有效证据自动满足，不再手工 clear。

## 十二、Recovery：恢复系统

高风险任务开始前生成恢复检查点：

- branch 和 HEAD；
- 当前 Diff；
- 未跟踪文件；
- 数据库状态；
- migration 状态；
- 配置摘要；
- 必要的备份提示；
- 恢复步骤。

Critical 任务要求：

```text
失败判断标准
停止条件
恢复方案
数据回滚方案
代码回滚方案
验证恢复成功的方法
```

重点不是完全禁止 AI 犯错，而是确保错误可发现、可停止、可恢复。

## 十三、Knowledge Loop：知识闭环

文档同步不应只检查文件有没有修改，而应允许三种正式结果：

```text
updated
reviewed-no-change
not-applicable
```

完整流程：

```text
代码变更
→ 定位受影响知识资产
→ 提取变更事实
→ 对比现有文档
→ 生成候选更新
→ 验证示例和引用
→ 保存评估结论
```

AI 可以生成候选文档，但必须提供：

- 受影响代码；
- 原知识段落；
- 变化事实；
- 修改理由；
- 来源引用。

最终形成：

```text
需求
→ 决策
→ 代码
→ 测试
→ 证据
→ 文档
→ Skill
```

## 十四、Agent Adapters

Harness 应成为唯一策略源，再生成不同 Agent 的适配：

```text
Harness Policy
  ├─ AGENTS.md
  ├─ CLAUDE.md
  ├─ Copilot Instructions
  ├─ Cursor Rules
  └─ Generic CLI
```

长期可以提供本地 MCP 接口：

```text
get_project_context
start_task
resume_task
get_applicable_standards
get_change_plan
risk_check
record_decision
record_evidence
review_diff
finish_task
```

不同 AI 可以共享同一任务、上下文和证据。

## 十五、运行模式

### Assist

- 只提示；
- 不阻塞；
- 自动上下文；
- 自动建议；
- 适合初次接入。

### Guard

- 默认模式；
- 低风险自动通过；
- 中高风险强制规范检查；
- 自动证据；
- 关键问题阻塞。

### Strict

- 完整 PRD；
- 全量 Supervisor；
- 完整证据；
- 恢复计划；
- 可选服务端 Required Checks；
- 适合支付、数据库、权限和发布。

模式可以按任务自动升降级。

## 十六、技术架构建议

```text
CLI / TUI / MCP
        │
        ▼
Task Orchestrator
        │
        ├── Project Brain
        ├── Risk Engine
        ├── Standards Registry
        ├── Development Supervisor
        ├── Evidence Engine
        ├── Recovery Engine
        └── Knowledge Engine
        │
        ▼
Adapters
  ├── Git
  ├── Agent
  ├── Stack
  ├── Linter
  ├── Test
  ├── Browser
  ├── Database
  └── CI
```

核心保持：

- 本地优先；
- Git-native；
- 隐私友好；
- 可离线；
- 不依赖中央 SaaS；
- 确定性检查优先；
- LLM 用于语义 Review 和建议；
- LLM 不能成为唯一安全边界。

## 十七、升级路线

以下 Phase 0–6 均已在 1.0.0 实现；具体合同、命令和迁移说明以独立仓库 README/docs 为准。

## Phase 0：可靠性基线，目标 0.3

修复：

- `init` Gate 配置结构；
- starter rules 初始化；
- Windows 参数和测试；
- `eval-llm`；
- `report` 计数；
- generated-check fail-open；
- 插件加载 fail-open；
- Git 错误处理；
- CLI 退出码契约。

同时定义统一数据对象：

```text
Task
Standard
Risk
Finding
Evidence
KnowledgeAsset
AgentRun
```

验收：

- Windows/Linux/macOS；
- 所有命令成功/失败测试；
- init→task→gate→verify→finish E2E；
- Harness 自身使用自己的 CI。

## Phase 1：规范机器化与 Supervisor MVP，目标 0.4

实现能力：

- Standards Registry；
- 规范 ID；
- 规范覆盖率；
- Diff 标准选择；
- 修改范围检查；
- Code Quality Supervisor；
- Architecture Supervisor；
- Technology Choice Gate；
- 新代码复杂度和重复度基线。

验收：

- 每条规范都有执行级别；
- 每个 Finding 引用规范 ID；
- 可以报告哪些规范仅停留在文档；
- 新依赖和架构变更自动触发 Review。

## Phase 2：任务系统与项目大脑，目标 0.5

实现能力：

- task start/status/checkpoint/resume/finish；
- 项目知识索引；
- 自动上下文包；
- 历史决策；
- 多会话续接；
- Agent 交接包；
- Quick/Standard/Critical。

验收：

- 新 Agent 能根据交接包继续任务；
- 无需重新解释项目；
- 不重复读取无关文档；
- 修改范围和剩余步骤明确。

## Phase 3：领域 Supervisor，目标 0.6

实现能力：

- Database Supervisor；
- UI Style Supervisor；
- Interaction Supervisor；
- Accessibility；
- API/Security Review；
- Knowledge Supervisor。

验收：

- 数据库变更有安全与恢复检查；
- UI 有完整状态矩阵；
- 交互有截图/DOM/a11y 证据；
- 文档回写支持三种评估结果。

## Phase 4：证据与恢复闭环，目标 0.7

实现能力：

- Typed Evidence；
- 自动验证；
- 浏览器截图；
- 日志和 DB 查询；
- checkpoint；
- 恢复计划；
- 自动交付报告；
- `verify-test` 自动完成。

验收：

- 每个完成任务都有证据包；
- 高风险任务有恢复方案；
- 证据绑定当前代码状态；
- 任务报告包含剩余风险。

## Phase 5：Agent 生态与体验，目标 0.8

实现能力：

- Agent adapters；
- MCP；
- TUI；
- 技术栈 presets；
- 风险包；
- 规范包；
- “下一步动作”；
- 自动修复建议。

验收：

- Codex/Claude/Copilot 使用同一策略；
- 任务可跨 Agent 续接；
- 大部分检查自动完成；
- 阻塞都有明确原因和下一步。

## Phase 6：稳定版本，目标 1.0

重点：

- 插件稳定协议；
- 配置迁移；
- 性能和缓存；
- 大型 monorepo；
- worktree/并发任务；
- 可选 GitHub Required Checks；
- 长期兼容；
- 完整文档和样例项目。

企业能力如中央 SaaS、复杂 RBAC、OPA、组织级策略和供应链签名可以放到 1.0 之后，不应抢占独立开发者主线。

## 十八、核心指标

不要只看 Gate 通过率。

更有价值的指标：

- 规范机器执行覆盖率；
- 自动完成检查比例；
- AI 重复实现次数；
- 修改范围偏移次数；
- 提交前发现问题数；
- 任务跨会话恢复成功率；
- 返工率；
- 文档过期时间；
- 高风险操作恢复成功率；
- Harness 引入的等待时间；
- 从需求到可信交付的人工干预次数。

北极星指标：

> 独立开发者从提出需求到获得可信、可恢复、知识已同步的交付结果，需要多少时间、返工和人工干预。

## 十九、暂时不要优先做

- 不要强制所有任务写完整 PRD；
- 不要增加更多人工 `gate:clear`；
- 不要自研完整 Sonar/Semgrep；
- 不要全面引入 OPA；
- 不要先建设中央 SaaS；
- 不要先做企业 RBAC；
- 不要让 LLM Review 单独决定阻塞；
- 不要把 AI 总结直接作为权威知识；
- 不要为了规范而强迫无意义文档修改；
- 不要让历史技术债务阻断所有新开发。

## 最终结构

整合之后，Harness 应有四根主轴：

```text
第一根：项目记忆与任务治理
让 AI 理解项目、管理任务、跨会话续接

第二根：实际开发质量监督
让 AI 按技术、架构、代码、数据库、样式和交互规范实施

第三根：风险、证据与恢复
让开发者知道结果是否可信，失败后如何恢复

第四根：知识闭环
让代码、测试、文档、PRD、决策和 Skill 持续同步
```

最终产品不再只是：

> AI 必须遵守哪些规则。

而是：

> Harness 让 AI 理解该做什么、知道应该怎么做、在实施中遵守规范、完成后证明做对了，并把经验重新沉淀回项目。

以上仅为整合方案，没有实施或修改任何文件。
