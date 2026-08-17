# REQ-20260817-remove-root-glob-dep — 移除根 package.json 无用的 glob 弃用依赖

> 关联 PRD：PRD-20260817-other-移除根-package-json-无用的-glob-弃用依赖
> 关联任务：TASK-20260817093314-91370eeb
> 类型：功能优化（`优化：`前缀，用户 2026-08-17 回复"优化"确认）

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词 | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App | `backend/app/` | glob | 无 | 不涉及 |
| Core | `pallastrade_gems/pallastrade_core/app/` | glob | 无 | 不涉及 |
| API | `pallastrade_gems/pallastrade_api/app/` | glob | 无 | 不涉及 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | glob | 无 | 不涉及 |
| Storefront | `storefront/src/` | glob | 无（storefront 独立工作区） | 不涉及 |
| Platform | `platform/packages/` | glob | 无（platform 独立工作区） | 不涉及 |

**搜索结论**：全仓库无代码引用根 `glob` 包（已用 grep 验证 `from 'glob'`/`require('glob')` 零命中）。根 `package.json` 的 `glob: ^11.0.0` 是唯一 dependencies 项且未被使用 → 可安全删除。glob@11.1.0 仍作为 `pallastrade-harness@1.1.2` 传递依赖保留（上游，本次不处理）。

## Step 1：Skill 文件咨询（功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 本次为仓库依赖清单清理，非业务定制；决策树无对应项 → 纯运维/工程变更。 |
| `ai/skills/pallastrade-prd/SKILL.md` | ✅ 已读 | §4：task+gate+REQ 流程；§8 知识同步门（package.json 变更命中 doc-impact anyOf：AGENTS.md / prd SKILL / scenarios.json）。 |
| `ai/skills/pallastrade-admin/SKILL.md` | ⬜ 不涉及 | 无 admin 改动 |

**按需 Skill：** 均不涉及（无业务/API/样式/安全/部署变更）。

> ✅ 必读 Skill 已读；按需 Skill 评估不涉及。

---

## 需求标题

移除根 `package.json` 中无用的 `glob: ^11.0.0` 弃用直接依赖，`pnpm install` 同步锁文件。

## 任务类型

功能优化（依赖清理）

## 需求描述

1. 根 `package.json` 删除 `dependencies.glob`（无代码引用，glob@11 已弃用）。
2. `pnpm install` 重新生成 `pnpm-lock.yaml`（importer `.` 段移除 glob specifier）。
3. 验证 `npx harness` / lefthook 正常可用。

## 影响范围（harness affected 输出）

- 根 `package.json` + `pnpm-lock.yaml`。无业务组件影响；`glob@11.1.0` 仍以 harness 传递依赖存在（预期）。

## 技术方案（初步）

- 编辑 `package.json` 删除 dependencies 块；运行 `pnpm install` 同步锁文件；`pnpm install --frozen-lockfile` 校验一致。
- 无代码行为变更。

## 风险点

- 低：glob 未被引用；回滚 = revert package.json + pnpm-lock.yaml。
- 风险引擎判定 critical（package.json 属标准/关键路径）→ 需 approval 证据 + 恢复计划。

## 决策节点

> 用户 2026-08-17 回复"优化"明确确认实施。PRD 已记录（FR-001~003 / AC-001~003，状态 approved）。

---

## 阶段③：实施后验证（不可跳过）

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| 依赖清单 | `package.json` | `pnpm install --frozen-lockfile` 通过 + grep 无 glob 声明 | 待执行 | ⬜ |
| 锁文件 | `pnpm-lock.yaml` | `pnpm install` 干净 + importer 无 glob | 待执行 | ⬜ |
| 引擎可用 | 根 | `npx harness --help` / `gate:status` 正常 | 待执行 | ⬜ |
| 质量门 | 根 | `harness check --profile quick` | 待执行 | ⬜ |
| 知识同步 | 文档 | `doc-impact --base origin/main` | 待执行 | ⬜ |

### 验证结论

待实施后填写。
