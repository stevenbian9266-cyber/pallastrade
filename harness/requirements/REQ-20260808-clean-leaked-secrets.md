# 需求文档 — 清理仓库中误提交的敏感文件

> 任务来源：用户在另一台设备部署时，将本地 `.env` 等敏感文件提交到了 GitHub 仓库，
> 要求从仓库中彻底清理，避免交付源码 / 公开仓库泄露密钥。

---

## Step 0：跨层搜索（Git 索引级全仓扫描）

> 本任务不涉及功能代码，跨层搜索以"Git 已跟踪文件中的敏感内容"为目标。

| 层 | 搜索路径 | 搜索关键词 | 找到的敏感文件 | 是否需清理？ |
|---|---|---|---|---|
| App 配置 | `backend/.env` | `SECRET_KEY_BASE`(64hex)、`PALLASTRADE_API_KEY` | ⚠️ **真实密钥**（`11b5...` 64 位、`pk_9...`） | ✅ 移除 |
| Storefront 配置 | `storefront/.env` | `PALLASTRADE_PUBLISHABLE_KEY` | ⚠️ **真实 key**（`pk_...` 27 位） | ✅ 移除 |
| Storefront e2e | `storefront/e2e-backend/.env` | 本地端口配置 | ⚠️ 本地配置（不该上传） | ✅ 移除 |
| Platform 本地设置 | `platform/.claude/settings.local.json` | Claude 本地权限 | ⚠️ 机器本地文件 | ✅ 移除 |
| 支付包本地设置 | `platform/payments/*/.claude/settings.local.json`（×3） | Claude 本地权限 | ⚠️ 机器本地文件 | ✅ 移除 |
| 配置模板 | `backend/.env.example` | `change-me` 占位符 | ✅ 安全模板 | 保留 |
| 配置模板 | `storefront/.env.example` / `.env.local.example` | `your_..._key` 占位符 | ✅ 安全模板 | 保留 |
| 数据库配置 | `backend/config/database.yml` | `ENV.fetch` 引用 | ✅ 无硬编码密码 | 保留 |
| 证书/密钥 | 全仓 `.pem/.key/.p12/.jks` | — | ✅ 无 | — |
| 真实密钥模式 | `git grep` `sk_live_/AKIA/ghp_/BEGIN PRIVATE` | 仅文档示例文本 | ✅ 无真实密钥 | — |
| 历史提交 | `git log` | 敏感文件出现次数 | `.env`×3 仅 HEAD 提交 `e916045f`；`.claude/settings.local.json`×4 自初始提交 `e9d248d8` | ✅ 需重写历史 |

### 搜索结论

- **需从 Git 跟踪移除（7 个文件）**：`backend/.env`、`storefront/.env`、`storefront/e2e-backend/.env`、
  `platform/.claude/settings.local.json`、`platform/payments/{adyen,paypal_checkout,stripe}/.claude/settings.local.json`
- **历史位置**：3 个 `.env` 仅在 HEAD 提交 `e916045f`（该提交**只含这 3 个文件**）→ 可安全重写；
  4 个 `.claude/settings.local.json` 存在于全部 24 个提交 → 需 `git filter-branch` 全历史重写
- **`.gitignore` 缺口**：`storefront/.gitignore` 未覆盖 `e2e-backend/.env`；`platform/.gitignore` 未覆盖 `.claude/settings.local.json`

---

## Step 1：Skill 文件咨询

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 本任务不涉及 PallasTrade 定制决策树，是仓库卫生/安全操作，走 security skill |
| `ai/skills/pallastrade-security/SKILL.md` | ✅ 已读 | "If a secret leaks into a commit (even on a private repo): **rotate immediately**, then rewrite history (`git filter-repo`, `bfg`). Rotation order: 1.Rotate key 2.Update env 3.Deploy 4.Clean history." |
| `ai/skills/pallastrade-deployment/SKILL.md` | ✅ 已读 | `SECRET_KEY_BASE` 用 `bin/rails secret` 生成（128-char hex），`PALLASTRADE_API_KEY` 需在后台轮换 |

---

## 需求标题

从 Git 跟踪与仓库历史中彻底清理误提交的 7 个敏感文件，强化 `.gitignore` 防止复发。

## 任务类型

需求（安全清理）

## 需求描述

1. 用户另一台设备部署时把本地 `.env`（含真实 `SECRET_KEY_BASE`、API key）提交到了 GitHub 私有仓库
2. 要求：这些文件不再存在于仓库任何地方（含 Git 历史），且未来不会被再次提交
3. 本地文件**保留**（本地部署/开发继续可用），只从 Git 中移除
4. 交付源码（客户拿到）不含任何本地敏感配置

## 影响范围

- Git 历史（24 个提交，7 个文件）
- `.gitignore`：`backend/`、`storefront/`、`platform/`、根
- 远端 `origin`：`https://github.com/stevenbian9266-cyber/pallastrade.git`
- 工作区：892 个未提交变更（React Dashboard 移除，需先 stash 再恢复）

## 技术方案

### 阶段 A — 索引清理（交付源码层面）
1. `git rm --cached` 7 个敏感文件（保留本地文件）
2. 强化 `.gitignore`：
   - `storefront/.gitignore`：补 `e2e-backend/.env`（或 `.env.e2e` 覆盖）
   - `platform/.gitignore`：补 `.claude/settings.local.json`
   - 根 `.gitignore`：补 `.claude/settings.local.json` 兜底
3. 提交一个"移除敏感文件跟踪"的提交

### 阶段 B — 历史彻底清理（GitHub 层面，需 force push）
1. `git stash push -u`（暂存 892 个 React Dashboard 移除变更，filter-branch 要求工作区干净）
2. `git filter-branch --index-filter "git rm --cached --ignore-unmatch <7 文件>" --prune-empty -- --all`
   - 3 个 `.env` 从唯一提交 `e916045f` 移除（该提交为空后自动删除）
   - 4 个 `.claude/settings.local.json` 从全部历史移除
3. `git stash pop`（恢复 892 个变更，路径不重叠，无冲突）
4. `git push --force origin main` —— ⚠️ **被 hooks 物理拦截，需用户手动执行**（或 `PALLASTRADE_HOOKS_DISABLE=1`）

### 阶段 C — 密钥轮换（建议，需用户确认）
- `SECRET_KEY_BASE`（已暴露）→ `bin/rails secret` 重新生成并更新 `backend/.env`
- `PALLASTRADE_API_KEY` / `PALLASTRADE_PUBLISHABLE_KEY`（已暴露）→ 后台轮换
- 理由：即使历史已清理，密钥曾在 GitHub 上存在过；GitHub 的缓存/分叉可能仍持有

## 风险点

| 风险 | 等级 | 缓解 |
|---|---|---|
| filter-branch 重写全部 24 个提交 SHA | 高 | 私有仓库单用户；操作前 `git clone --mirror` 备份 |
| force push 被 hooks 拦截 | 中 | 明确告知用户手动执行 |
| stash 892 变更 pop 冲突 | 低 | 7 个文件与 dashboard 移除路径不重叠 |
| 密钥曾在 GitHub 短暂存在 | 中 | 阶段 C 轮换 |

## 决策节点

1. **是否执行阶段 B（历史重写 + force push）？** 若只清跟踪不重写历史，GitHub 历史中仍可检出敏感文件。
   → 用户需求是"从仓库中全部清理掉"，**建议执行**。
2. **是否执行阶段 C（密钥轮换）？** 会中断当前运行实例，需重新配置。
   → 作为安全建议，请用户选择。

---

## 阶段③：实施后验证

| 改动类型 | 最低验证 | 状态 |
|---|---|---|
| Git 跟踪状态 | `git ls-files` 无 7 个敏感文件 | ⬜ |
| Git 历史 | `git log --all -- <敏感文件>` 返回空 | ⬜ |
| .gitignore | `git check-ignore` 命中所有 7 个文件 | ⬜ |
| 本地部署 | `backend/.env` 等本地文件仍存在（未删除） | ⬜ |
| 密钥模式 | `git grep` 敏感模式仅文档示例 | ⬜ |
