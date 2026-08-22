# 需求文档 REQ-20260822-upgrade-harness-170

> Task: TASK-20260822180507-2be9784e / Gate: GATE-2026-08-22T18-05-20
> 类型：功能优化（版本升级）

---

## Step 0：跨层搜索（6 层强制）

> 本次为**依赖版本升级**（`pallastrade-harness` ^1.6.0 → 1.7.0），不涉及业务代码变更；6 层搜索确认无业务代码依赖旧版 harness 内部 API。

| 层 | 搜索路径 | 关键词 | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App | `backend/app/` | harness, gate, evidence | 无直接引用 | ✅ 业务层不直接 import harness |
| Core Gem | `backend/pallastrade_gems/pallastrade_core/app/` | harness | 无 | ✅ |
| API Gem | `backend/pallastrade_gems/pallastrade_api/app/` | harness | 无 | ✅ |
| Admin Gem | `backend/pallastrade_gems/pallastrade_admin/app/` | harness | 无 | ✅ |
| Storefront | `storefront/src/` | harness | 无 | ✅ |
| Platform | `platform/packages/` | harness | 无 | ✅ |
| 根 | `package.json` | pallastrade-harness | `devDependencies: "pallastrade-harness": "^1.6.0"` | ⚠️ 需升级到 ^1.7.0 |
| 根 | `pnpm-lock.yaml` / `node_modules/pallastrade-harness` | — | 1.6.0 已安装 | ⚠️ 需更新到 1.7.0 |

### 搜索结论

- 6 层业务代码均不直接依赖 harness 内部模块 → 升级无代码破坏面
- 仅需：`pnpm add -D pallastrade-harness@latest`（更新 package.json + pnpm-lock.yaml + node_modules）
- 升级后验证：`harness doctor` / `harness version` 显示 1.7.0

---

## Step 1：Skill 文件咨询

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树：配置优先，最小侵入；升级依赖不新增业务代码 |
| `ai/skills/harness-standards-audit/SKILL.md`（域 skill） | ✅ 已读 | 升级后运行 `harness doctor` / `harness config:check` 验证配置兼容 |

---

## 需求标题

将主仓 `pallastrade-harness` 从 ^1.6.0 升级到最新版 1.7.0（Trust Kernel）。

## 任务类型

版本升级（devDependency）

## 需求描述

1. `pnpm add -D pallastrade-harness@latest` 升级到 1.7.0
2. 更新 `package.json` + `pnpm-lock.yaml` + `node_modules`
3. 验证新引擎可用：版本号、`harness doctor`、`harness config:check`
4. 若 1.7.0 引入新 gate checks（如 task 强绑定），确认主仓现有流程不受破坏

## 技术方案（初步）

- 包管理器：pnpm（主仓 pnpm-lock.yaml，D 盘 NTFS 支持 junction）
- 代理：若 registry 超时用 `http://127.0.0.1:7890`（见部署记忆）
- 验证命令：`node node_modules/pallastrade-harness/bin/harness.mjs version` / `harness doctor`

## 风险点

- 1.7.0 新引擎对旧 gate 文件的兼容（migrations 已处理状态迁移）
- pnpm 网络超时 → 代理重试

## 验收标准

- [ ] `package.json` 中 pallastrade-harness 升级到 ^1.7.0
- [ ] `node_modules/pallastrade-harness/package.json` version = 1.7.0
- [ ] `harness doctor` / `config:check` 通过
- [ ] 现有 Task/Gate 状态可读（migration 正常）
