# 需求文档：移除上游升级审计逻辑

> 日期：2026-08-07
> Gate：GATE-2026-08-07T00-47-53
> 类型：feature（删除类改造）
> 决策人：Steven Bian（已确认删除范围）

---

## 背景

PallasTrade 已完成私有化（源码层零 Spree 残留，已全仓核实）。用户决策：

1. **删除 Spree 官方文档 MCP 连接**（VS Code 用户级配置，用户自行在 MCP 设置界面移除，不涉及本仓库）
2. **删除 harness 升级审计套件**（`upgrade:*` 命令、版本目录、CI workflow、baseline、场景、文档引用）
3. **删除 `ai/commands/audit-upgrade.md`**（Claude 插件 slash command）

---

## Step 0：跨层搜索（已全部执行）

| 层 | 搜索路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | upgrade:audit / pallastrade:upgrade / upgrade-readiness | 无 | ✅ 无依赖 |
| Core | `pallastrade_core/` | 同上 | `db/migrate/*.rb` 引用 `pallastrade:upgrade:populate_*` 数据回填 rake task | ⚠️ rake task **保留**（见边界） |
| API | `pallastrade_api/` | 同上 | 无 | ✅ 无依赖 |
| Admin | `pallastrade_admin/` | 同上 | 无 | ✅ 无依赖 |
| Storefront | `storefront/src/` | 同上 | 无 | ✅ 无依赖 |
| Platform | `platform/packages/` | 同上 | `cli/src/commands/upgrade.ts` + tests + CHANGELOG（`pallastrade upgrade` CLI） | ⚠️ CLI 命令**保留**（见边界） |
| AI 资产 | `ai/` | audit-upgrade | `commands/audit-upgrade.md`、README、AGENTS.md、`.claude-plugin/*.json`、`scripts/ci/plugin-structure-check.mjs`、3 个 skill 引用 | ❌ **本次删除对象** |

### 搜索结论

- 升级审计逻辑（本次删除目标）**只存在于顶层 harness + ai/ 层**，六层业务代码均无运行依赖。
- 发现两个**非审计**的框架升级机制，与"审计"是不同概念，**明确保留**：
  1. `pallastrade:upgrade` rake task（pallastrade_core）—— 生产部署 release-phase 的数据回填机制（Heroku/Render/K8s 部署均调用），幂等，删除会破坏生产部署
  2. `pallastrade upgrade` CLI 命令（platform/packages/cli）—— 上述 rake task 的本地封装

---

## Step 1：Skill 文件咨询

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树确认：本任务是"删除顶层工具"，不涉及框架定制模式；无 decorator/subscriber/gem 修改 |
| `ai/skills/pallastrade-deployment/SKILL.md` | ✅ 已读 | §release-phase：`pallastrade:upgrade` 是生产部署必需（Heroku/Render/K8s 全部调用），**必须保留**；其中 `/pallastrade:audit-upgrade` 引用需移除 |

**按需 Skill：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-project` | ✅（引用 audit-upgrade） | ✅ 已查 | L27/L127 提到 upgrade 流程，仅移除 audit-upgrade 引用，`pallastrade upgrade` 命令行保留 |
| `pallastrade-catalog` | ✅（引用 audit-upgrade） | ✅ 已查 | L145 提到 `/pallastrade:audit-upgrade`，仅移除该句引用 |
| `pallastrade-testing` | ⬜ | ⬜ | 本次为删除操作，无测试模式变更 |

---

## 需求内容

### 删除清单（A 组：harness 升级套件，12 项）

| # | 路径 | 动作 |
|---|---|---|
| A1 | `scripts/harness/upgrade-audit.mjs` | 删除文件 |
| A2 | `scripts/harness/upgrade-rollback.mjs` | 删除文件（含危险 `git reset --hard`） |
| A3 | `scripts/harness/upgrade-verify.mjs` | 删除文件 |
| A4 | `harness/versions/`（v5.6） | 删除目录 |
| A5 | `harness/baselines/` | 删除目录 |
| A6 | `harness/config.json` | 移除 `upgrade` profile |
| A7 | `.github/workflows/harness-upgrade.yml` | 删除文件 |
| A8 | `scripts/harness/cli.mjs` | 移除 5 个 `upgrade:*` 命令 handler + help 文本 |
| A9 | `harness/scenarios/scenarios.json` | 移除 GS-010（升级审计场景） |
| A10 | `artifacts/upgrade-evidence/` | 删除目录 |
| A11 | `AGENTS.md` §6 | 移除"Framework version upgrade"行 |
| A12 | `.github/copilot-instructions.md` | 同步移除该行 |

### 删除清单（B 组：ai audit-upgrade 命令及引用，9 项）

| # | 路径 | 动作 |
|---|---|---|
| B1 | `ai/commands/audit-upgrade.md` | 删除文件 |
| B2 | `ai/README.md` | 移除 `/pallastrade:audit-upgrade` 行 |
| B3 | `ai/AGENTS.md` | 移除 audit-upgrade 引用（L135） |
| B4 | `ai/.claude-plugin/marketplace.json` | 从 description 移除 audit-upgrade |
| B5 | `ai/.claude-plugin/plugin.json` | 从 description 移除 audit-upgrade |
| B6 | `ai/scripts/ci/plugin-structure-check.mjs` | **关键**：硬编码断言 `['audit-upgrade.md','doctor.md']` → 改为 `['doctor.md']`，否则 CI 挂 |
| B7 | `ai/skills/pallastrade-catalog/SKILL.md` | 移除 L145 audit-upgrade 引用 |
| B8 | `ai/skills/pallastrade-deployment/SKILL.md` | 移除 L154/L269 audit-upgrade 引用 |
| B9 | `ai/skills/pallastrade-project/SKILL.md` | 移除 L127 audit-upgrade 引用 |

### 明确保留（边界）

- ❌ **不删** `pallastrade:upgrade` rake task（pallastrade_core）—— 生产部署数据回填，release-phase 必需
- ❌ **不删** `pallastrade upgrade` CLI 命令（platform/packages/cli）—— 上述 rake task 的封装
- ❌ **不删** `PallasTrade Harness机制建设方案.md` —— 历史设计文档
- ❌ **不删** `harness/requirements/` 中历史 REQ 文档

> 若需将 rake task / CLI 命令也一并删除，请在确认时明确说明（会导致生产部署 release-phase 失效，需另行评估）。

---

## 设计

- **性质**：纯删除 + 引用清理，无新增逻辑
- **依据决策树**：不涉及 Settings/Events/DI/Admin/Generator/Decorator/Extension/Gem 修改——仅删除顶层工具脚本
- **关键依赖**：B6（plugin-structure-check.mjs）必须先改，否则 `ai-ci` 会挂；A11/A12 是治理文档同步

## 反模式自查

- [x] AP-001~009：不适用（无新增代码）
- [x] 不新建文件替代删除（删除即删除，不重建）
- [x] 不误删框架升级执行机制（rake task / CLI 保留）

---

## 验证计划

| 检查 | 命令 | 预期 |
|---|---|---|
| harness 仍健康 | `node scripts/harness/cli.mjs doctor` | healthy |
| gate 生命周期 | `node scripts/harness/cli.mjs gate:status` | 有效 |
| 无残留引用 | grep `upgrade:audit\|upgrade:rollback\|upgrade:evidence\|audit-upgrade`（排除本 REQ 文档与建设方案档案） | 0 命中 |
| ai 插件结构 | `node ai/scripts/ci/plugin-structure-check.mjs` | 通过（仅 doctor.md） |
| config 合法 | `node -e "JSON.parse(fs.readFileSync('harness/config.json'))"` | 合法 JSON |
| scenarios 合法 | 同上 | 合法 JSON |

> 说明：本任务为删除类，无业务逻辑变更，验证以"无残留引用 + harness 健康"为准，符合 R6「删除/文档类无需新增测试」的例外。
