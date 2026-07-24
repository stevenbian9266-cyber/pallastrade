# PallasTrade Harness 工程化能力审查

## 1. 审查信息

- 审查日期：2026-07-24
- 仓库：`github.com/stevenbian9266-cyber/pallastrade`
- 基线提交：`7403c3284826ae72d00c72eaa650908d2ba93ed3`
- 审查范围：根仓库以及 `backend/`、`platform/`、`storefront/`、`ai/`、根级 CI、发布脚本、开发环境、测试资产和工程指令
- 审查方式：本地仓库静态证据审查，结合现有命令和 CI 配置判断闭环完整性
- 范围边界：GitHub 分支保护、Tag 保护、环境 Secret、仓库规则集等远端设置未在本次本地审查中验证
- 工作区说明：审查开始前已经存在 `backend/pallastrade_gems/pallastrade_core/lib/pallastrade/core.rb` 的未提交修改，本报告未修改、未暂存该文件

## 2. 本报告对 Harness Engineering 的定义

本报告中的 Harness Engineering，不仅指“有测试脚本”或“有 CI”，而是指项目为人类开发者和 AI 编码代理提供一套稳定、可发现、可重复、可验证、可诊断、可审计的执行外壳。

极致 Harness 至少需要形成以下闭环：

1. **理解闭环**：进入仓库后，能够快速获得正确的架构、边界、约束和改动规则。
2. **环境闭环**：能够用固定工具链和声明式配置复现开发、测试、构建环境。
3. **任务闭环**：所有常用操作都有统一、可发现、跨平台的根级入口。
4. **反馈闭环**：改动后可以从快速检查逐级升级到全量、集成、端到端和发布检查。
5. **诊断闭环**：失败时能够留下结构化日志、测试报告、环境快照和明确修复建议。
6. **安全闭环**：危险命令、Secret、依赖风险、权限、制品供应链均有自动门禁。
7. **发布闭环**：源码、测试证据、包版本、构建制品、签名和部署结果可以相互追溯。
8. **AI 闭环**：AI 指令、技能、工具调用和安全钩子本身也有可重复的场景评测和回归门禁。

理想状态不是堆积更多脚本，而是让任何执行者都能回答：

- 我应该运行什么？
- 它会修改什么？
- 它依赖什么？
- 它验证了什么？
- 失败证据在哪里？
- 如何确定结果对应当前 Commit？
- 如何安全恢复或继续？

## 3. 总体结论

### 3.1 成熟度结论

当前项目属于 **L2“组件自动化较强”向 L3“单仓库闭环 Harness”过渡阶段**，综合成熟度约为 **2.7 / 5**。

项目已经不是“缺少工程化”的状态。Backend、Platform、Storefront、AI 四个组件均存在开发说明、测试资产或 CI，根仓库也已经具备单仓契约、API V3 契约、品牌归属审计、统一 Tag 和 release manifest。

当前主要问题不是能力完全不存在，而是：

- 能力分散在不同目录，没有根级统一入口；
- 一部分高价值测试和发布工作流仍放在组件内部 `.github/`，在当前单仓库中不会自动注册为 GitHub 工作流；
- 工程说明、VS Code 任务和实际目录模型之间已经产生明显漂移；
- 快速检查、全量检查、E2E、发布门禁之间没有形成同一套可复用的 Harness 配置；
- CI 结果有“通过/失败”，但缺少覆盖率阈值、结构化证据、失败诊断包和制品级可追溯性；
- AI 资产已有技能和安全钩子，但没有场景评测、误报测试、提示词回归和跨工具一致性验证。

### 3.2 当前最强的五项能力

1. 单仓库目录、唯一 `main` 分支、统一 Tag 和固定 Gem 目录已经形成明确契约。
2. 根级 CI 能按组件路径触发 Backend、Platform、Storefront、AI 检查。
3. Backend Docker 环境覆盖 PostgreSQL、Redis、Meilisearch、Mailpit、Web、Worker，并配置健康检查。
4. API V3 已有运行时契约、文档策略、OpenAPI 文件、SDK 和生成类型基础。
5. 发布脚本能够绑定根 Commit、四个组件目录摘要、Gem/npm 版本和测试证据。

### 3.3 阻止达到“极致 Harness”的七项核心缺口

1. 缺少根级统一 Harness 命令和机器可读配置。
2. 高价值测试资产没有全部接入根级 CI 和发布门禁。
3. 组件内部 GitHub 工作流、Dependabot 和安全配置在单仓模型中处于未接通状态。
4. Node、包管理器、锁文件、Docker 镜像和 GitHub Action 缺少统一确定性。
5. 工程说明与实际目录、API 和任务入口发生漂移。
6. 缺少覆盖率阈值、测试报告、失败诊断包、性能预算和不稳定测试治理。
7. AI 技能和安全钩子没有真正的 Eval Harness。

## 4. 能力成熟度评分

| 维度 | 评分 | 当前判断 |
|---|---:|---|
| 单仓结构与边界契约 | 4.0 / 5 | 固定目录、唯一 Git 根、统一 Tag、目录防回退门禁已经建立 |
| 开发环境可复现性 | 3.0 / 5 | Backend Docker 较完整，但全仓工具链和前端环境未统一 |
| 根级任务编排 | 1.5 / 5 | 组件脚本较多，但根目录没有统一任务入口 |
| 快速反馈与增量验证 | 2.5 / 5 | 有路径过滤和 Turbo，但没有统一 affected 计算与本地/CI 同构 |
| 测试金字塔 | 2.5 / 5 | 测试资产丰富，但多类测试未进入当前根级 CI |
| API 与生成物契约 | 3.5 / 5 | V3、OpenAPI、SDK、生成类型基础较强，但缺少双向漂移门禁 |
| 安全 Harness | 2.5 / 5 | Ruby 安全扫描和 AI 钩子存在，TS、Secret、制品供应链仍不完整 |
| 可观测性与诊断 | 2.5 / 5 | 有 Sentry、健康检查、日志和 Mailpit，缺少统一 Trace/Metric/诊断包 |
| 发布与证据链 | 3.5 / 5 | Tag 和源码 manifest 较强，构建制品、SBOM、签名和证据真实性不足 |
| AI Agent Harness | 2.5 / 5 | 24 个技能、2 个命令、1 个专家代理和 2 个钩子，但没有行为评测 |
| 依赖与供应链维护 | 1.5 / 5 | 锁文件存在，但依赖更新配置位置、镜像和 Action 固定方式存在缺口 |
| 文档与事实一致性 | 1.5 / 5 | 文档量大，但部分关键路径、治理文件和 VS Code 任务已失真 |

## 5. 当前已经具备的 Harness 能力

## 5.1 单仓库结构和目录约束

已具备：

- 根仓库是唯一 Git 工作树。
- 固定组件目录为 `backend/`、`platform/`、`storefront/`、`ai/`。
- 根级 `scripts/ci/monorepo-contract-check.mjs` 检查：
  - Git 根目录；
  - 四个固定组件目录；
  - 组件内部嵌套 `.git`；
  - 当前分支；
  - canonical `origin`；
  - Backend Gem 目录不得出现版本后缀。
- 统一 Tag 创建脚本会检查：
  - 必须位于 `main`；
  - 工作区必须干净；
  - 四个组件目录存在；
  - 不允许嵌套 Git；
  - 本地和远端 Tag 不得已存在。

价值：

- AI 或开发者不容易把四个组件误当成四个独立仓库。
- 组件路径稳定后，脚本、CI、Gemfile、文档和源码链接有固定锚点。
- 发布可以绑定同一根 Commit，而不是依赖四个漂移的分支。

当前限制：

- 契约只验证结构是否存在，没有验证组件依赖图、同步规则和影响范围。
- 分支和 Tag 的远端保护仍依赖 GitHub 设置，仓库内没有可验证的 ruleset 声明或审计脚本。

## 5.2 Backend 开发环境

已具备：

- Ruby 版本通过 `backend/.ruby-version` 固定为 `4.0.1`。
- `backend/Dockerfile` 使用多阶段构建，区分 build、dev 和生产阶段。
- `backend/docker-compose.dev.yml` 提供：
  - PostgreSQL；
  - Redis；
  - Meilisearch；
  - Mailpit；
  - Rails Web；
  - Sidekiq Worker；
  - Admin CSS watcher。
- PostgreSQL、Redis、Meilisearch 和 Web 均有健康检查。
- 危险的无密码开发端口尽量绑定到 `127.0.0.1`。
- 开发 compose 将 Rails 临时缓存和预编译资产与宿主源码隔离。
- `backend/.env.example`、数据库配置、Sidekiq 配置和 Procfile 已存在。
- Backend CI 会执行：
  - Compose 环境契约；
  - 数据库准备；
  - 资产预编译；
  - RSpec；
  - Brakeman；
  - bundle-audit。

价值：

- Backend 的依赖服务不需要开发者手工安装。
- 邮件、搜索、队列和数据库均有本地可运行替身。
- 资产预编译进入 CI，能够捕获仅在生产构建中出现的加载问题。

当前限制：

- 根目录没有命令统一启动 Backend、Platform 和 Storefront。
- Compose 使用 `getmeili/meilisearch:latest`、`axllent/mailpit:latest`，环境随时间漂移。
- Backend 自带 Docker 闭环，但全仓没有统一 devcontainer、mise/asdf 或等价工具链声明。

## 5.3 Platform 包工作区

已具备：

- `platform/package.json` 固定 `pnpm@11.1.1`，Node 要求 `>=22`。
- `platform/.node-version` 固定 Node 22。
- `pnpm-workspace.yaml` 管理多个包。
- Turbo 统一执行 `dev`、`build`、`test`、`lint`、`typecheck` 和 `clean`。
- 多数包都具备独立的 build、test、lint 和 typecheck 脚本。
- SDK、Admin SDK、CLI、Dashboard、Dashboard Core、Docs、脚手架均有测试资产。
- Dashboard 已具备 Playwright E2E 测试。
- SDK 已具备独立 integration 测试配置。
- `platform/scripts/ci/api-v3-docs-check.mjs` 维护 V3 文档策略。

价值：

- TypeScript 包之间已经有基本依赖拓扑。
- Turbo 可以避免完全串行地重复构建。
- 包级脚本为未来统一 Harness 提供了可复用执行单元。

当前限制：

- Turbo 的 task 定义非常基础，没有统一环境变量声明、输入范围、日志产物和测试输出。
- 根级 Platform CI 只执行默认 `pnpm test`，不会自动执行 Dashboard E2E 和 SDK integration profile。

## 5.4 Storefront 工程能力

已具备：

- Next.js 的 dev、build、start、Biome、TypeScript、Vitest 和 Playwright 命令均已定义。
- 有 Storefront E2E Backend compose。
- 有 E2E bootstrap 和环境脚本。
- 有 12 个前端单元测试文件和 1 个结账 E2E 文件。
- Dockerfile 支持 Sentry Source Map 上传，并使用 BuildKit Secret 传入 Sentry Token。
- `.env.example` 和 `.env.local.example` 覆盖 API、站点、支付、邮件、分析和 Sentry 配置。

价值：

- 已经具备从单元测试到真实结账流程的测试路径。
- Sentry 的构建期 Secret 处理方式避免把 Token 固化到镜像层。

当前限制：

- 根级 Storefront CI 不执行 `npm run build`、locale parity 和 Playwright E2E。
- Storefront 同时提交 `package-lock.json` 和 `pnpm-lock.yaml`，但根 CI 使用 npm，目录又存在 `pnpm-workspace.yaml`，包管理事实源不唯一。
- `package.json` 没有 `packageManager` 和明确 Node 版本约束。

## 5.5 测试资产

仓库当前存在的主要测试资产：

| 测试域 | 文件数量 | 当前根级 CI 是否完整执行 |
|---|---:|---|
| Backend 根应用 RSpec | 4 | 是，`bundle exec rspec` |
| Backend 本地 Gem RSpec | 9 | 否，默认根应用 RSpec 不会自动进入各 Gem 的 `spec/` |
| Platform 支付 Gem RSpec | 71 | 否 |
| Platform TS 测试文件总量 | 121 | 只执行各包默认 `test` |
| Dashboard Playwright E2E | 34 | 否 |
| SDK integration 测试 | 5 | 否 |
| Storefront 单元测试 | 12 | 是 |
| Storefront Playwright E2E | 1 | 否 |
| AI 场景 Eval | 0 | 否 |

已具备：

- Ruby 使用 RSpec、Factory Bot、Capybara 和 SimpleCov 基础。
- TypeScript 使用 Vitest。
- Dashboard 和 Storefront 使用 Playwright。
- 支付模块包含大量 VCR 录制数据。
- RSpec feature 测试具备 retry 配置。

当前限制：

- 测试“存在”与测试“进入当前根 CI”不是同一件事。
- SimpleCov 没有最低覆盖率门禁。
- 根级 CI 不上传 RSpec JUnit、Cobertura、Vitest、Playwright 或失败截图。
- RSpec 的随机顺序和慢测试分析仍处于注释状态。
- Retry 没有形成不稳定测试计数和隔离机制，可能隐藏偶发失败。

## 5.6 API V3 和生成物契约

已具备：

- `scripts/ci/api-version-contract-check.mjs` 检查运行时旧 API 路径和命名空间回流。
- `platform/scripts/ci/api-v3-docs-check.mjs` 检查文档导航、OpenAPI 版本和路径前缀。
- Backend 有 Store/Admin V3 路由。
- Platform 有 `store.yaml` 和 `admin.yaml`。
- Store SDK 和 Admin SDK 固定使用 V3 Base Path。
- SDK 中存在自动生成 TypeScript 类型和 Zod 结构。
- CLI 内置 Admin OpenAPI 快照用于离线端点和 Schema 查询。

价值：

- API、文档和 SDK 已经有共同版本基线。
- 静态契约可以阻止明显的旧路径回流。
- CLI 和 SDK 为自动化代理提供结构化 API 使用方式。

当前限制：

- 文档检查主要是字符串和文件存在性检查，不是完整 OpenAPI Schema 校验。
- 没有在 CI 中启动 Backend，并将真实路由/响应与 OpenAPI 做双向差异检测。
- CLI 的 `admin-spec.json` 在 build 时会被重新生成，但根 CI 没有执行“生成后工作区必须无差异”检查。
- Typelizer、Zod、OpenAPI、SDK 类型之间没有一个根级 `generated:check`。
- Platform Lefthook 仍监听不存在的 `pallastrade/api/...` 路径，因此生成物自动更新描述与当前目录结构不一致。

## 5.7 根级 CI

已具备 6 个根级工作流：

- `monorepo-contract.yml`
- `backend-ci.yml`
- `platform-ci.yml`
- `storefront-ci.yml`
- `ai-ci.yml`
- `release-manifest.yml`

优点：

- 使用组件路径过滤减少无关任务。
- 默认权限主要为 `contents: read`。
- checkout 多数设置 `persist-credentials: false`。
- 发布工作流通过 reusable workflow 复用四个组件检查。
- 正式 Tag 不允许取消正在运行的发布任务。

当前限制：

- 普通 CI 没有 `concurrency` 和 `cancel-in-progress`。
- 所有根工作流都没有 `timeout-minutes`。
- 根工作流的 15 个外部 Action 引用均使用移动版本标签，没有固定到完整 Commit SHA。
- 除发布 manifest 外，根工作流不上传测试报告、覆盖率、失败日志或诊断包。
- `docs/**`、根 README、`.vscode/**` 等治理入口没有进入单仓契约触发范围。

## 5.8 安全能力

已具备：

- Backend CI 执行 Brakeman 和 bundle-audit。
- API Key、JWT、Webhook HMAC、权限 Scope 和多店隔离规则在工程指令中有明确约束。
- AI 插件提供：
  - 破坏性数据库命令阻断；
  - 主分支强推阻断；
  - 常见 Secret 形状提示。
- Docker 开发端口对数据库、Meilisearch 和 Mailpit 使用 Loopback 限制。
- GitHub Actions 默认权限相对克制。

当前限制：

- AI 安全钩子只覆盖特定 Claude Code 工具调用，不是仓库级 CI 门禁。
- Secret 检查是编辑后警告，不是提交和 CI 阻断。
- Platform 和 Storefront 根级 CI 没有依赖审计、SAST 或 Secret 扫描。
- 根 `.github/dependabot.yml` 不存在；组件内部 Dependabot 文件不会作为单仓库的 Dependabot 配置生效。
- 没有 SBOM、制品签名、SLSA provenance、容器扫描或依赖许可证策略。
- 外部 Action 和容器镜像没有按不可变摘要固定。

## 5.9 可观测性和本地诊断

已具备：

- Backend 使用 Sentry、Lograge、Rails 健康检查和 Sidekiq。
- Storefront 集成 Sentry，并支持 Source Map 上传。
- Docker 服务有健康检查。
- Mailpit 可以捕获邮件。
- AI 插件包含 `/pallastrade:doctor` 诊断命令。
- CLI 提供 logs、console、routes、migrate、api status 等诊断入口。

当前限制：

- `/up` 只表示 Rails 进程存活，不验证数据库、Redis、队列和关键依赖，不是完整 readiness。
- 没有统一 OpenTelemetry Trace、Metric 和跨 Backend/Storefront 的关联 ID 策略。
- 没有错误预算、核心交易 SLI、队列积压阈值和性能预算。
- 没有一键生成脱敏诊断包。
- `/pallastrade:doctor` 的项目识别仍假设 compose 位于根目录，和当前 `backend/docker-compose*.yml` 布局不一致。

## 5.10 AI 开发能力

已具备：

- 24 个领域技能。
- 2 个命令：doctor、audit-upgrade。
- 1 个专家代理。
- 2 个安全钩子。
- AI CI 能检查技能、命令、代理、钩子数量以及插件元数据。
- 技能覆盖 API、数据模型、结账、支付、测试、安全、性能、部署等主要域。

价值：

- AI 不必只依赖模型记忆，可以读取项目内领域规则。
- 专家代理适合长链路审计。
- 安全钩子能减少误执行高风险命令。

当前限制：

- AI CI 只验证结构和少量文本规则，不验证建议是否正确。
- 没有 Golden Scenario、期望文件、误报/漏报测试和评分器。
- 两个 Shell 安全钩子没有自动测试。
- 没有验证技能中的文件路径、命令和 API 是否仍真实存在。
- 没有跨 Claude Code、Codex、Cursor 等目标工具的安装和解析烟雾测试。
- 根目录没有 canonical `AGENTS.md`，从根仓库启动的代理无法先获得统一单仓规则。

## 5.11 发布与 release manifest

已具备：

- Tag 格式和不可移动策略。
- Tag 必须创建在干净 `main` 工作区。
- manifest 记录：
  - 根 Commit；
  - Commit 时间；
  - 四个组件 Git Tree；
  - 四个组件确定性 SHA-256；
  - 文件数量；
  - Gem/npm 包名、版本和路径；
  - 测试状态和 CI URL。
- 同名 GitHub Release 资产禁止覆盖。

价值：

- 发布版本能够绑定四个组件的同一个源码状态。
- 源码目录和包版本之间已经具备基础追溯能力。

当前限制：

- `ci-evidence.mjs` 根据发布工作流依赖成功而生成概括性“passed”记录，没有采集每个 Job、命令、测试数量、持续时间和报告摘要。
- `manifest.schema.json` 存在，但 `manifest.mjs verify` 没有真正调用 JSON Schema Validator。
- manifest 绑定的是源码 Tree，不是实际 Docker/npm/Gem 构建制品摘要。
- 根级 Tag 工作流只生成 manifest 和 GitHub Release；组件内部的 Docker、npm、Gem 发布工作流在单仓模式下不会自动执行。
- Tag 是 annotated tag，但没有签名。
- 没有 SBOM、provenance、容器摘要和部署环境状态。

## 6. 已确认的关键工程漂移

## 6.1 组件内部 `.github` 能力未接入根仓库

以下目录中存在更丰富的工作流：

- `backend/.github/workflows/`
- `platform/.github/workflows/`
- `storefront/.github/workflows/`
- `ai/.github/workflows/`

这些文件在当前单仓库中只是普通源码文件。GitHub 只会自动注册根目录 `.github/workflows/` 下的工作流。

因此以下能力虽然“文件存在”，但不等于“当前根仓库已经执行”：

- Platform PostgreSQL/MySQL Ruby 矩阵测试；
- Platform Ruby 覆盖率和 JUnit 上传；
- Platform 支付模块 RSpec；
- SDK integration；
- Dashboard Playwright E2E；
- Platform 定时依赖安全修复；
- Storefront Playwright E2E 和失败日志上传；
- Backend Stripe Sandbox 安全门禁；
- Docker 多架构镜像发布；
- npm、Gem 发布链。

同理：

- `backend/.github/dependabot.yml`
- `platform/.github/dependabot.yml`
- `storefront/.github/dependabot.yml`

不会替代根 `.github/dependabot.yml`。

## 6.2 VS Code 任务已经成为非确定性入口

`.vscode/tasks.json` 当前共有：

- 119 个任务；
- 44 处 `D:\pallastrade` 本机绝对路径；
- 40 个不存在的脚本或诊断文件引用；
- 9 个明确使用旧 API 路径或旧 API 命名的任务；
- 多个直接修数据、清缓存、配置支付、执行品牌改名或批量修复的变更型任务。

影响：

- 换一台机器或换一个工作目录会失效。
- AI 和开发者可能把历史一次性操作误认为正式工程入口。
- 一些任务会绕过当前 API V3 和固定目录契约。
- 变更型任务没有 dry-run、前置备份、确认或结构化结果。

## 6.3 工程指令与当前目录模型不一致

已确认的例子：

- `platform/AGENTS.md` 引用的以下治理文件当前不存在：
  - `docs/governance/rename-map.yml`
  - `docs/governance/OBLIGATIONS.md`
  - `docs/governance/IMPACT_MAP.md`
  - `docs/governance/PAYMENT_SECURITY_GATE.md`
  - `docs/adr/`
- `platform/CLAUDE.md` 仍大量使用 `pallastrade/core`、`pallastrade/api` 和 `server/` 目录模型。
- 当前真实 Ruby 源码位于 `backend/pallastrade_gems/...`。
- Platform Lefthook 仍监听 `pallastrade/api/app/serializers/**/*.rb`。
- `backend/CLAUDE.md` 要求“不要修改 Gem 源码”，但当前仓库的本地 Gem 已经是正式自有源码。
- `/pallastrade:doctor` 的项目探测优先寻找根 `docker-compose.yml`，当前 compose 位于 `backend/`。

影响：

- AI 会遵循错误路径或错误改动边界。
- 自动生成钩子可能永远不触发。
- 文档成为“高置信度错误信息”，风险高于完全没有文档。

## 6.4 工具链事实源不唯一

已确认：

- Platform Node 版本为 22。
- Platform Docs `.nvmrc` 为 20。
- Storefront 没有明确 `packageManager`，同时提交 npm 和 pnpm 两套锁文件。
- 根 Storefront CI 使用 npm。
- Platform 使用 pnpm 11.1.1。
- Docker 使用 `latest` 镜像。
- 根级外部 GitHub Action 没有固定到 Commit SHA。

影响：

- 本地、CI、文档构建和未来 Agent 执行可能得到不同依赖树。
- 同一个 Commit 不能完全保证同一环境结果。

## 6.5 支付源码存在双目录但没有同步 Harness

以下支付模块同时存在于：

- `backend/pallastrade_gems/`
- `platform/payments/`

文件规模分别为：

| 模块 | Backend 文件 | Platform 文件 |
|---|---:|---:|
| Adyen | 120 | 212 |
| PayPal Checkout | 32 | 57 |
| Stripe | 100 | 195 |

当前只发现 API 旧版本扫描同时检查两套目录，没有发现：

- canonical 源码归属声明；
- 单向生成/同步命令；
- 内容差异白名单；
- 双目录漂移 CI；
- 两套测试结果绑定。

这会让修复可能只落在一套目录中。

## 7. 欠缺能力明细

## 7.1 P0：必须先补齐的闭环

### H-P0-01：根级统一 Harness 命令

问题：

- 根目录没有 `package.json`、Taskfile、Makefile、justfile 或统一 CLI。
- 常用命令分散在 Bundler、pnpm、npm、Docker、PowerShell、Shell 和 VS Code Tasks 中。

建议：

- 使用 Node 22 编写跨平台 `scripts/harness/*.mjs`。
- 根级提供单一命令 `pallastrade-harness`，或根 `package.json` 脚本。
- 所有任务必须支持：
  - `--help`
  - `--dry-run`
  - `--format human|json`
  - 明确退出码
  - 执行时长
  - 结果文件位置

验收：

- 新机器在根目录只需查阅一个帮助入口。
- 本地和 CI 调用同一命令，而不是复制两套 Shell 步骤。

### H-P0-02：把现有高价值测试接入根级 CI

必须接通：

- Backend 9 个本地 Gem spec；
- Platform 71 个支付 Gem spec；
- SDK integration；
- Dashboard 34 个 E2E；
- Storefront E2E；
- Stripe Sandbox 安全门禁。

建议执行层级：

- PR quick：受影响单元测试、静态检查、契约。
- PR full：受影响集成测试。
- `main`：全部单元和关键集成测试。
- Nightly：所有支付矩阵、E2E、浏览器和数据库矩阵。
- Tag：全部 release profile，不允许跳过。

验收：

- release manifest 中每个“passed”都有真实测试报告支持。
- 任何支付模块变更都会至少触发对应 Gem spec 和支付安全门禁。

### H-P0-03：迁移组件内部 GitHub 配置

问题：

- 多个高价值工作流和 Dependabot 配置当前不会在单仓库自动生效。

建议：

- 将有效 workflow 迁移到根 `.github/workflows/`。
- 公共步骤提取为 reusable workflow 或 composite action。
- 创建根 `.github/dependabot.yml`。
- 迁移后删除或归档组件内部失效配置，避免双重事实源。

验收：

- GitHub Actions 页面能看到所有设计中的检查。
- 根配置能覆盖 Bundler、pnpm、npm、Docker 和 GitHub Actions 依赖。

### H-P0-04：统一工具链和依赖事实源

建议决策：

- Node：全仓统一 Node 22 的精确小版本或镜像摘要。
- Platform：继续使用 pnpm 11.1.1。
- Storefront：在 npm 和 pnpm 中选择一个，删除另一套锁文件。
- Storefront 增加 `packageManager` 和 `engines.node`。
- Ruby：保持 `.ruby-version`，CI 和 Docker从同一声明读取。
- Docker：移除 `latest`，固定版本和摘要。
- GitHub Action：固定完整 Commit SHA，并由依赖机器人维护。

验收：

- `harness doctor` 能验证全部版本。
- CI 对锁文件冲突和未固定镜像直接失败。
- 同一 Commit 在两台干净机器上解析出相同依赖树。

### H-P0-05：清理错误工程入口

必须处理：

- `.vscode/tasks.json` 的绝对路径；
- 40 个不存在目标；
- 9 个旧 API 任务；
- 一次性改名、修数据和修路径任务；
- 过时的 Platform/Backend/AI 指令路径；
- 不存在的治理文档引用；
- 失效的 Lefthook glob。

建议：

- VS Code Tasks 只调用根 Harness，不直接包含业务命令。
- 变更型维护任务移入 `scripts/maintenance/`，增加 dry-run、确认、备份和审计。
- 建立 `harness docs:check`，校验文档和任务中引用的本地路径是否存在。

验收：

- VS Code Tasks 不包含绝对盘符。
- 所有命令目标存在。
- 文档内本地路径检查为零错误。

### H-P0-06：建立真实测试证据和覆盖率门禁

建议：

- Ruby：SimpleCov + Cobertura + 最低行/分支覆盖率。
- Vitest：统一 coverage provider 和包级阈值。
- Playwright：上传 HTML、trace、video、screenshot。
- RSpec：输出 JUnit，记录 seed、retry 次数和最慢示例。
- 每次 CI 生成统一 `harness-evidence.json`。

验收：

- 失败任务可以下载完整诊断证据。
- 覆盖率下降超过阈值时 PR 失败。
- Retry 后通过的测试仍标记为 flaky，而不是普通通过。

### H-P0-07：打通正式发布制品链

问题：

- 根 Tag 工作流只生成 manifest。
- Docker/npm/Gem 发布工作流仍留在组件内部路径。

建议：

- 根发布编排顺序：
  1. release profile 验证；
  2. 构建 Gem/npm/Docker；
  3. 生成 SBOM；
  4. 生成 provenance；
  5. 签名；
  6. 发布；
  7. 验证远端制品摘要；
  8. 生成最终 manifest；
  9. 附加 GitHub Release。

验收：

- manifest 记录实际发布制品摘要，而不只记录源码 Tree。
- 任一包或镜像发布失败时，不生成“完整发布”状态。

### H-P0-08：确定支付模块 canonical 来源

建议二选一：

1. 只保留一套支付源码，另一处通过构建/发布使用；或
2. 明确单向同步源和生成目标，并增加内容摘要和允许差异清单。

验收：

- 修改任一支付模块时，Harness 能明确提示 canonical 路径。
- 双目录漂移无法进入 `main`。

## 7.2 P1：形成稳定高效反馈环

### H-P1-01：根级 canonical `AGENTS.md`

应包含：

- 四组件真实目录；
- 自有源码可修改边界；
- API V3 规则；
- 固定 Gem 目录；
- 统一 Harness 命令；
- 危险操作策略；
- 哪些生成物不可手改；
- 每类变更最小验证集。

验收：

- 从仓库根启动任何支持 AGENTS.md 的代理，都能得到一致规则。

### H-P1-02：机器可读的影响图

建议创建 `harness/impact-map.json`：

- 文件 Glob；
- 所属组件；
- 依赖组件；
- 需要运行的 quick/full/release 任务；
- 需要重建的包；
- 是否触发安全和 E2E 门禁。

验收：

- `harness affected --base origin/main` 能输出确定任务列表。
- 本地和 CI 使用同一影响图。

### H-P1-03：生成物漂移检查

统一命令：

```text
harness generated:check
```

覆盖：

- Typelizer TypeScript 类型；
- Zod Schema；
- OpenAPI；
- CLI Admin Spec；
- SDK 导出；
- 文档包产物；
- 数据库 Schema。

验收：

- 重新生成后 `git diff --exit-code`。
- 生成命令在干净容器中可重复。

### H-P1-04：OpenAPI 真实契约测试

建议：

- 使用 OpenAPI Validator 校验 Schema。
- 启动 Backend 后对关键端点执行 Schema Conformance。
- 比较 Rails 路由与 OpenAPI Path。
- 检查权限 Scope、错误 Envelope、分页和 prefixed ID。
- 对 SDK 请求建立 Consumer Contract。

验收：

- 后端新增/删除字段而未同步 OpenAPI 和 SDK 时 CI 失败。

### H-P1-05：统一 Doctor

建议：

```text
harness doctor
harness doctor --format json
harness doctor --fix-safe
```

检查：

- Git 状态；
- 工具版本；
- Docker daemon；
- Compose 配置；
- 端口占用；
- 环境变量完整性；
- 数据库和 Redis；
- Migration；
- Sidekiq；
- API V3；
- Platform/Storefront 依赖；
- 生成物漂移；
- 当前包版本。

`--fix-safe` 只允许修复无损事项，例如创建缺失缓存目录，不执行数据库重置。

### H-P1-06：结构化失败诊断包

建议产物：

```text
artifacts/diagnostics/<run-id>/
├── summary.json
├── environment.json
├── git.json
├── commands.jsonl
├── docker-compose.txt
├── container-logs/
├── test-results/
├── screenshots/
└── redaction-report.json
```

验收：

- CI 失败时自动上传。
- 本地可用一条命令生成。
- Secret 和个人信息经过脱敏。

### H-P1-07：CI 稳定性控制

建议：

- 普通 PR CI 增加 concurrency 和 cancel-in-progress。
- 每个 Job 增加 timeout。
- 对网络依赖设置显式 retry，但测试逻辑失败不得自动重跑掩盖。
- 记录缓存命中率。
- 对服务启动使用 readiness，而不是固定 sleep。

### H-P1-08：不稳定测试治理

建议：

- Retry 次数写入报告。
- Flaky 测试有 owner、首次出现时间和过期时间。
- Nightly 重复执行高风险场景。
- 超过阈值自动失败，而不是无限隔离。

### H-P1-09：仓库级安全门禁

建议接入：

- Secret 扫描；
- Ruby/JS SAST；
- 依赖审计；
- GitHub dependency review；
- Dockerfile 和容器扫描；
- IaC/Compose 扫描；
- Actions 固定 SHA 检查；
- 权限最小化检查。

### H-P1-10：Readiness 与可观测性

建议：

- `/health/live`：进程存活。
- `/health/ready`：数据库、Redis、关键配置可用。
- `/health/dependencies`：受保护的依赖状态详情。
- 请求、Job、Webhook 和 Storefront 调用共享 correlation ID。
- 统一 OpenTelemetry Trace。
- 为结账、支付、Webhook、库存和队列定义 SLI。

### H-P1-11：数据与夹具生命周期

建议：

- 建立固定最小数据集；
- E2E 测试使用命名空间和可重复 Seed；
- 记录 Seed 版本；
- 测试结束自动清理；
- 支付 Sandbox 与本地 Mock 分层；
- 时间、随机数、外部响应可固定。

### H-P1-12：真正的 AI Eval Harness

至少建立以下场景：

- API V3 端点新增；
- Backend Service 替换；
- 支付集成修改；
- Storefront SDK 调用；
- 数据库危险命令；
- Secret 写入；
- 旧 API 建议；
- 错误路径引用；
- Doctor 诊断；
- 升级审计。

每个场景记录：

- 输入任务；
- 仓库 Fixture；
- 允许工具；
- 期望读取文件；
- 期望计划；
- 必须/禁止动作；
- 期望补丁；
- 评分规则；
- Token、耗时和重试次数。

验收：

- AI 技能或钩子修改必须运行 Eval。
- 结构检查通过但行为退化时 CI 能失败。

## 7.3 P2：向极致 Harness 演进

### H-P2-01：性能预算

- Backend API p95；
- SQL 数量和 N+1；
- Sidekiq 延迟；
- Dashboard Bundle 大小；
- Storefront Core Web Vitals；
- SDK 包体积；
- Docker 镜像大小和启动时间。

### H-P2-02：Mutation 和属性测试

- 对支付金额、库存、促销、退款和状态机使用 Mutation Test。
- 对 SDK 参数序列化、金额和 ID 使用 Property-based Test。

### H-P2-03：故障注入

- Redis 短暂不可用；
- PostgreSQL 连接耗尽；
- 支付超时和重复回调；
- Webhook 重放；
- Meilisearch 不可用；
- Sidekiq Job 重试；
- Storefront API 429/5xx。

### H-P2-04：预览环境

- 每个 PR 可选启动 Backend + Dashboard + Storefront。
- 自动 Seed。
- 自动分配 URL。
- 自动清理。
- 预览环境结果写入 CI evidence。

### H-P2-05：远程缓存和构建可重复性

- Turbo Remote Cache；
- Bundler、pnpm、Playwright 和 Docker BuildKit 缓存策略；
- 缓存 Key 包含工具链和锁文件；
- 定期无缓存构建验证。

### H-P2-06：自动二分和最小复现

- 对确定性回归生成 `git bisect run` 入口。
- 测试失败可输出最小命令和 Fixture。
- E2E 失败自动保存 Trace 和请求录制。

### H-P2-07：策略即代码

- 分支、Tag、发布、权限、制品、危险命令和依赖策略机器可读。
- 增加 `harness policy:check`。
- 定期审计远端设置与仓库策略是否一致。

### H-P2-08：Harness 自身测试

- 每个 Harness 命令有单元测试。
- 使用 Fixture 仓库验证 affected 计算。
- 对 Windows/Linux 路径分别测试。
- 对中断、超时、失败清理和并发执行进行测试。

## 8. 建议的目标 Harness 架构

```text
pallastrade/
├── AGENTS.md
├── package.json
├── harness/
│   ├── config.json
│   ├── impact-map.json
│   ├── capabilities.json
│   ├── policies/
│   │   ├── destructive-actions.json
│   │   ├── generated-files.json
│   │   ├── release.json
│   │   └── toolchain.json
│   ├── schemas/
│   │   ├── evidence.schema.json
│   │   └── diagnostics.schema.json
│   ├── fixtures/
│   ├── scenarios/
│   └── evals/
├── scripts/
│   ├── harness/
│   │   ├── cli.mjs
│   │   ├── doctor.mjs
│   │   ├── affected.mjs
│   │   ├── run.mjs
│   │   ├── evidence.mjs
│   │   ├── diagnostics.mjs
│   │   └── policy-check.mjs
│   ├── ci/
│   ├── maintenance/
│   └── release/
├── artifacts/
│   └── .gitkeep
└── .github/
    ├── dependabot.yml
    ├── actions/
    │   └── setup-harness/
    └── workflows/
        ├── harness-quick.yml
        ├── harness-full.yml
        ├── harness-nightly.yml
        └── harness-release.yml
```

说明：

- 建议用 Node 22 实现根 Harness，因为根级契约和发布脚本已经使用 `.mjs`，并且 Node 可同时编排 Ruby、Docker、pnpm 和 npm。
- Backend 业务测试仍在 Ruby/RSpec 中执行；Harness 只负责编排、证据和策略。
- VS Code、CI 和 AI 技能只调用 Harness，不再各自复制命令。

## 9. 建议的统一命令契约

```text
# 环境
harness doctor
harness bootstrap
harness env:print --redacted

# 影响分析
harness affected --base origin/main
harness plan --profile quick

# 质量
harness check --profile quick
harness check --profile standard
harness check --profile full
harness check --profile release

# 单组件
harness test backend
harness test platform
harness test storefront
harness test ai

# 专项
harness contract
harness generated:check
harness security
harness e2e dashboard
harness e2e storefront
harness eval ai

# 证据与诊断
harness evidence collect
harness diagnostics collect

# 发布
harness release plan --tag pallastrade-v1.0.0-rc.1
harness release verify --tag pallastrade-v1.0.0-rc.1
```

所有命令应保证：

- 根目录和子目录调用行为一致；
- Windows 和 Linux 行为一致；
- 不依赖固定盘符；
- 默认不执行破坏性操作；
- 支持 Ctrl+C 后清理临时容器和文件；
- JSON 输出稳定并有 Schema；
- 退出码可供 CI 判断；
- 输出本次使用的 Commit 和 dirty 状态。

## 10. 建议的检查 Profile

| Profile | 目标 | 建议内容 | 目标时长 |
|---|---|---|---:|
| quick | 编辑后高频反馈 | 格式、lint、类型、静态契约、受影响单测 | 5 分钟内 |
| standard | PR 默认门禁 | quick + Backend RSpec + Build + 安全基础检查 | 15 分钟内 |
| full | `main` 完整验证 | standard + integration + 支付测试 +关键 E2E | 45 分钟内 |
| nightly | 重型回归 | DB/浏览器矩阵、全部 E2E、flaky 重跑、性能与安全 | 可放宽 |
| release | 正式发布 | full + Sandbox、安全、制品、SBOM、签名、manifest | 不设跳过 |

时长目标必须通过真实数据调整，但每个 Profile 必须有稳定定义，不能由不同工作流复制出不同版本。

## 11. 统一证据模型

建议每次 Harness 执行生成：

```json
{
  "schemaVersion": 1,
  "runId": "uuid",
  "profile": "full",
  "commit": "full-sha",
  "dirty": false,
  "toolchain": {},
  "environment": {},
  "affectedComponents": [],
  "commands": [],
  "tests": [],
  "coverage": [],
  "artifacts": [],
  "retries": [],
  "security": [],
  "startedAt": "ISO-8601",
  "finishedAt": "ISO-8601",
  "status": "passed"
}
```

关键原则：

- 不允许只写概括性“测试通过”。
- 每个结果必须包含命令、退出码、持续时间和报告摘要。
- 证据中的 Commit 必须与被验证 Commit 完全一致。
- dirty 工作区证据必须记录 diff 摘要，不能伪装成 Commit 证据。
- 发布证据应引用不可变制品摘要。
- 所有日志在上传前执行 Secret 脱敏。

## 12. 分阶段实施建议

## 阶段 A：事实源收敛

目标：先让项目只存在一套正确入口。

任务：

1. 创建根 `AGENTS.md`。
2. 创建根 Harness CLI 骨架。
3. 删除或改造失效 VS Code Tasks。
4. 修正文档和 Agent 指令路径。
5. 统一 Node/Storefront 包管理器。
6. 修复 Lefthook 路径或迁移为根 Hook。
7. 明确支付模块 canonical 路径。

完成标准：

- 路径引用检查零错误。
- 根 `harness doctor` 可运行。
- 新机器不依赖 `D:\pallastrade`。

## 阶段 B：验证闭环

目标：让所有已有高价值测试真正进入根 CI。

任务：

1. 迁移组件内部有效工作流。
2. 接入支付 Gem spec。
3. 接入 SDK integration。
4. 接入 Dashboard/Storefront E2E。
5. 增加 coverage/JUnit/Playwright 产物。
6. 增加 generated drift 检查。
7. 增加 CI timeout 和 concurrency。

完成标准：

- quick/full/release Profile 都由同一 Harness 执行。
- Tag 检查不弱于 `main` 检查。
- 失败可以下载完整诊断证据。

## 阶段 C：安全和发布闭环

目标：从源码可追溯升级到制品可追溯。

任务：

1. 根 Dependabot。
2. Secret/SAST/Dependency/Container 扫描。
3. 固定 Action 和镜像摘要。
4. 迁移 npm/Gem/Docker 发布。
5. 生成 SBOM、provenance 和签名。
6. 强化 release manifest Schema 验证。

完成标准：

- 一个 Tag 对应确定的源码、测试、包、镜像、SBOM 和签名。
- 不允许覆盖同名制品。

## 阶段 D：AI 和自诊断闭环

目标：让 Harness 能评价 AI，也让 AI 能可靠使用 Harness。

任务：

1. AI Golden Scenario。
2. 安全钩子测试。
3. 跨工具安装烟雾测试。
4. Doctor JSON 和自动诊断包。
5. 性能、故障注入和不稳定测试治理。

完成标准：

- AI 指令变化有行为回归结果。
- Agent 可以根据 JSON 证据定位失败，而不是重新猜测环境。

## 13. 建议的量化指标

### 开发反馈

- quick Profile p50 / p95 时长；
- full Profile p50 / p95 时长；
- 缓存命中率；
- 首次失败定位时间；
- 本地通过但 CI 失败比例。

### 测试质量

- 行和分支覆盖率；
- 关键域 Mutation Score；
- flaky 率；
- retry 后通过次数；
- E2E 失败可复现率；
- 生成物漂移次数。

### 环境稳定性

- bootstrap 成功率；
- Doctor 通过率；
- 无缓存构建成功率；
- 不同 OS 结果一致率；
- 浮动依赖数量。

### 安全与发布

- 未固定 Action/镜像数量；
- 高危依赖修复时长；
- Secret 扫描告警数；
- 制品具备 SBOM/签名比例；
- manifest 与远端制品摘要一致率。

### AI Harness

- 场景通过率；
- 危险动作阻断率；
- 安全钩子误报/漏报率；
- 错误路径建议率；
- 首次补丁通过 quick Profile 的比例；
- 平均 Token 和平均迭代次数。

## 14. 极致 Harness 的最终验收定义

项目达到目标状态时，应同时满足：

1. 从根目录存在唯一、稳定、跨平台的任务入口。
2. 本地、VS Code、CI、AI 和发布调用同一 Harness。
3. 任意文件变更可以由机器计算出最小且充分的验证集。
4. 所有正式源码路径、文档引用和生成物均有漂移检查。
5. Backend、Platform、Storefront、AI 的单元、集成、E2E 和安全检查全部接入根级编排。
6. 测试结果包含覆盖率、报告、持续时间、Seed、Retry 和失败产物。
7. 环境工具、依赖、Action 和镜像均为不可变或受控更新。
8. 关键运行链路具备 readiness、Trace、Metric、日志和 correlation ID。
9. 正式发布能追溯到源码、测试、包、镜像、SBOM、签名和部署状态。
10. AI 技能、命令、代理和安全钩子有真实场景 Eval。
11. Harness 自身有测试，并能在 Windows/Linux 上稳定工作。
12. 新维护者或新 Agent 无需依赖个人记忆即可在 15 分钟内完成环境诊断和首次 quick 验证。

## 15. 最终判断

PallasTrade 当前已经拥有构建极致 Harness 所需的大部分“零件”：单仓契约、Docker、组件脚本、丰富测试、API V3、OpenAPI、SDK、发布 manifest、AI 技能和安全钩子。

真正欠缺的是把这些零件收敛为同一套根级事实源，并让每项能力都进入可执行、可观察、可验证、可追溯的闭环。

因此最优推进顺序不是继续增加更多独立脚本，而是：

1. 先统一根入口和事实源；
2. 再接通已经存在但未生效的测试、工作流和发布能力；
3. 然后补齐证据、覆盖率、安全和可观测性；
4. 最后建立 AI Eval、性能和故障注入等高级 Harness。

完成 P0 后，项目可达到稳定的 L3 单仓闭环；完成 P1 后可达到 L4 自诊断工程系统；完成 P2 后才接近“极致 Harness Engineering”。
