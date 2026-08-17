# REQ-20260817-upgrade-harness-113 — 升级 pallastrade-harness 1.1.3（glob@13，消除弃用 glob@11）

> 关联任务：TASK-20260817100902-2be8a157
> 类型：功能优化（依赖升级，用户 2026-08-17 "登录成功，继续执行" 确认）

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 关键词 | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App | `backend/app/` | harness | 无 | 不涉及（纯工具链依赖） |
| Core | `pallastrade_core/app/` | harness | 无 | 不涉及 |
| API | `pallastrade_api/app/` | harness | 无 | 不涉及 |
| Admin | `pallastrade_admin/app/` | harness | 无 | 不涉及 |
| Storefront | `storefront/src/` | harness | 无 | 不涉及 |
| Platform | `platform/packages/` | harness | 无 | 不涉及 |

**结论**：harness 是根目录开发工具链（`devDependencies`），无任何业务层引用。本次仅升级依赖版本，6 层零影响。

## Step 1：Skill 文件咨询

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `pallastrade-prd/SKILL.md` | ✅ 已读 | §8 知识同步门（package.json 变更命中 doc-impact anyOf：AGENTS.md / prd SKILL / scenarios.json） |
| `pallastrade-customization/SKILL.md` | ✅ 已读 | 非业务定制，纯依赖升级 |

---

## 需求标题

升级根 `package.json` 的 `pallastrade-harness` 到 `^1.1.3`（上游已发布：glob^11→^13，消除弃用依赖），同步锁文件。

## 任务类型

功能优化（依赖升级）

## 需求描述

1. `package.json`：`pallastrade-harness` `^1.1.2` → `^1.1.3`（已通过 `pnpm add pallastrade-harness@1.1.3` 完成）。
2. `pnpm-lock.yaml`：harness 升级 1.1.3，其内部 glob@13.0.6 替代 glob@11.1.0（弃用版本消除）。
3. 验证 harness 引擎可用（`gate:status` / `check --profile quick`）+ `pnpm install --frozen-lockfile` 一致。

## 影响范围

- `package.json`（1 行）+ `pnpm-lock.yaml`（41 行）。无业务组件影响。

## 技术方案

- 已执行 `pnpm add pallastrade-harness@1.1.3`；锁文件 glob@11.1.0 引用 = 0。
- 上游改动：`pallastradeharness` 仓库（D:\pallastrade-harness）commit e2d523f + tag v1.1.3，npm 已发布（latest=1.1.3）。

## 风险点

- 低：引擎已实测可用（gate:status 正常）；回滚 = revert package.json + pnpm-lock.yaml。
- 风险引擎判定 critical（package.json 关键路径）→ 需 approval 证据 + 恢复计划。

## 决策节点

> 用户 2026-08-17 "登录成功，继续执行" 明确确认继续（跨仓库升级任务的一部分）。

---

## 阶段③：实施后验证（不可跳过）

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| 依赖清单 | `package.json` | 含 `^1.1.3` | 待执行 | ⬜ |
| 锁文件 | `pnpm-lock.yaml` | `glob@11.1.0` 引用 = 0 + frozen-lockfile 通过 | 待执行 | ⬜ |
| 引擎可用 | 根 | `npx harness gate:status` 正常 | 待执行 | ⬜ |
| 质量门 | 根 | `harness check --profile quick` | 待执行 | ⬜ |
| 知识同步 | 文档 | `doc-impact --base origin/main` | 待执行 | ⬜ |

### 验证结论

待实施后填写。
