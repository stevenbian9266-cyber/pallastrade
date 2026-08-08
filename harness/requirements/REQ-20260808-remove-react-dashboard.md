# REQ-20260808-remove-react-dashboard — 移除所有新一代管理后台（React Dashboard）相关逻辑

- 日期：2026-08-08
- 任务类型：feature（需求：移除新一代管理后台）
- Gate：GATE-2026-08-08T04-14-27
- 分支：main @ e916045f

## 1. 背景与目标

新一代管理后台（React Dashboard）为 **Developer Preview（0.x）**，与 Classic Admin（5.x 生产默认）并存。用户决定交付源码时**不含新一代后台的任何逻辑/代码/文件/触发机制**，避免影响客户使用。

**目标**：彻底移除 React Dashboard 技术栈，交付源码只保留 Classic Admin（Rails 服务端渲染）+ Storefront。

## 2. 跨层搜索结论（完整足迹清单）

### A. 平台包（7 个，全部删除）
| 包 | 说明 |
|---|---|
| `platform/packages/admin-sdk` | Admin API TS 客户端（新一代数据层，CLI 的 api/ping 也依赖） |
| `platform/packages/dashboard` | React Dashboard shell（Vite SPA，TanStack Router） |
| `platform/packages/dashboard-ai` | AI 集成扩展 |
| `platform/packages/dashboard-core` | 框架 + 扩展 API |
| `platform/packages/dashboard-plugin-example` | 示例插件 |
| `platform/packages/dashboard-starter` | 脚手架模板（CLI 内嵌） |
| `platform/packages/dashboard-ui` | 设计系统 |

### B. 后端 gem（1 个，删除）
- `backend/pallastrade_gems/pallastrade_dashboard` —— Rails 侧 `/dashboard` 服务挂载（app_controller + routes + engine）
- `backend/Gemfile` 中 `gem 'pallastrade_dashboard', path: ...`
- `backend/config/brakeman.ignore` 中的 dashboard 引用

### C. CLI（`platform/packages/cli`）——新一代触发机制，全部清除
| 文件 | 处理 |
|---|---|
| `src/api.ts`、`src/ping.ts` | 依赖 admin-sdk（createAdminClient）→ **删除命令** |
| `src/output.ts` | 引用 `@pallastrade/admin-sdk` 的 PallasTradeError → 改为本地错误类 |
| `src/add.ts` | 整个命令仅支持 `dashboard` → 删除 `add` 命令 |
| `src/dev.ts`、`src/init.ts` | 导入 DASHBOARD_PORT / 启动 dashboard dev server → 清理 |
| `src/open.ts` | "Open the admin dashboard" → 删除（或改为打开 Classic Admin `/admin`） |
| `src/build.ts`、`src/eject.ts`、`src/completion.ts`、`src/plugin.ts`、`src/template.ts` | dashboard 相关逻辑/注释 → 清理 |
| `src/constants.ts` | `DASHBOARD_PORT = 5173` → 删除 |
| `templates/dashboard-starter/` | 内嵌模板 → 删除 |
| `tests/add-dashboard.test.ts` | → 删除 |
| `scripts/sync-dashboard-starter.mjs` | → 删除（build 脚本引用一并移除） |
| `package.json` | 移除 admin-sdk 依赖 + build 脚本中的 sync-dashboard-starter |

### D. create-pallastrade-app（`platform/packages/create-pallastrade-app`）
- `package-json.ts`（dashboard phase/flag）、`readme.ts`（DASHBOARD_PORT）、`dependabot.ts`（hasDashboard）、`claude-md.ts`（React dashboard 提及）→ 清理 dashboard 相关

### E. Dockerfile（`backend/Dockerfile`）
- `ARG DASHBOARD_SOURCE` + dashboard build 注释块（已被注释禁用）→ 删除

### F. CI 工作流
- `platform/.github/workflows/packages.yml`：删除 `dashboard-e2e`、`release-admin-sdk`、`release-dashboard` job 及其 needs 依赖（release-cli needs release-dashboard → 解除）
- `platform/.github/workflows/tests.yml`：移除 dashboard 循环项
- 根 `.github/workflows/`：**无 dashboard 引用**（已确认）

### G. 平台配置与脚本
- `platform/package.json`：删除 `server:dashboard` 脚本
- `platform/scripts/sync-dashboard-starter.mjs`：删除
- `platform/pnpm-lock.yaml`：pnpm install 更新

### H. 确认无引用（不需要动）
- storefront：**无 dashboard 引用**（用 `@pallastrade/sdk` store SDK）
- backend docker-compose：仅 Meilisearch dashboard 注释（无关）
- 根 workflows：无引用
- turbo.json：无引用

## 3. Skill 咨询证据表（R2）

| Skill | 咨询结论 |
|---|---|
| pallastrade-customization | 移除动作属平台自有源码（platform/packages、backend gem），直接修改/删除，符合"gem 为自有产品可直接改"规则 |
| pallastrade-admin | Classic Admin（pallastrade_admin gem）为生产默认，保留不动；React Dashboard 属独立栈，删除不影响 Classic Admin |

## 4. 决策点（需用户确认）

| # | 决策 | 方案 |
|---|---|---|
| D1 | admin-sdk 一并删除？ | **是**——它是新一代数据层（0.x Developer Preview），且是"新一代相关代码/文件"，符合"全部移除"诉求 |
| D2 | CLI 的 `api`/`ping` 命令 | **删除**——它们完全依赖 admin-sdk；删除后失去 `pallastrade api get/post/...` 与 `pallastrade ping` 能力（开发工具功能，非后台 UI）。若需保留可改为原生 fetch，但会增加复杂度，默认按删除处理 |
| D3 | CLI `open` 命令 | 删除 dashboard 打开逻辑；保留命令但改为打开 Classic Admin（`/admin`） |
| D4 | 保留 `@pallastrade/sdk`（store SDK）？ | **是**——storefront 核心依赖，与新一代后台无关，必须保留 |

## 5. 涉及文件清单

**删除目录（9 个）**：
- `platform/packages/{admin-sdk,dashboard,dashboard-ai,dashboard-core,dashboard-plugin-example,dashboard-starter,dashboard-ui}`
- `backend/pallastrade_gems/pallastrade_dashboard`
- `platform/scripts/sync-dashboard-starter.mjs`

**修改**：
- `backend/Gemfile`、`backend/config/brakeman.ignore`、`backend/Dockerfile`
- `platform/packages/cli/`（src 多个文件、package.json、templates、tests）
- `platform/packages/create-pallastrade-app/`（src 多个文件）
- `platform/.github/workflows/packages.yml`、`tests.yml`
- `platform/package.json`
- `platform/pnpm-lock.yaml`（pnpm install 后）

## 6. 验证计划

| 变更 | 验证 |
|---|---|
| 平台包删除 | `pnpm install` 成功；`pnpm turbo build --filter=@pallastrade/cli` 通过 |
| CLI | `pallastrade --help` 正常；无 api/ping/add dashboard 命令残留；无 dashboard 引用（grep） |
| 后端 | `harness check --profile quick` 通过；Rails 启动正常；`/admin` Classic Admin 仍 200；`/dashboard` 404 |
| 全仓 | grep `dashboard`（排除 storefront/docs 允许项）无新一代残留 |
| storefront | 首页 200，功能不受影响 |

## 7. 范围外（不做）
- 不删除 Classic Admin（`pallastrade_admin` gem）
- 不删除 `@pallastrade/sdk`（store SDK，storefront 核心）
- 不删除 Admin API 后端接口（`/api/v3/admin/*` 是后端 API，Classic Admin/外部集成可能使用）
- 历史 git 提交不改动
