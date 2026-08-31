# REQ-20260831-删除 prod/main 引用

| 项 | 值 |
|---|---|
| 关联 PRD | 延续 PRD-20260831-infra（部署清理）；无新 PRD |
| 任务类型 | 优化迭代（基础设施清理，无应用逻辑） |
| 用户确认 | ✅ 用户原话："删除github main分支；阿里云服务器上，删除main服务器及相关数据。github和服务器只保留dev相关的"（2026-08-31） |

## 需求描述（FR）

已完成的破坏性操作（git/服务器，无仓库文件）：
- ✅ GitHub main 分支已删除；默认分支已切换为 dev
- ✅ 服务器 prod 镜像（4 个）、数据卷（4 个含 postgres 数据库）、.env.prod/.env.storefront.prod/prod.sh 已删
- ✅ 本地备份 backup-main 保留（main 含社交登录等 dev 缺失提交，可恢复）

本 REQ 的仓库清理（FR）：
- FR-001：`deploy/` 删除 prod 残留：`docker-compose.prod.yml`、`prod.sh`、`.env.prod.example`、`.env.storefront.prod.example`
- FR-002：`deploy/deploy.sh`、`deploy/pull-deploy.sh`、`deploy/dev.sh` 移除 prod/main 分支逻辑，只接受 dev
- FR-003：`deploy/README.md` 更新为仅 dev（删除 prod 表行/禁用说明/恢复措辞）
- FR-004：根 `.github/workflows/*.yml` 监听 `[main, dev]` → `[dev]`；`harness-full.yml` 的 `--base origin/main` → `origin/dev`；`deploy.yml` 移除 main 分支的 ghcr main tag 逻辑

## Step 0 跨层搜索

6 层（backend app/core/api/admin + storefront + platform）无 prod/main 部署引用；prod 引用集中在 `deploy/`（8 文件 58 处）与根 `.github/workflows/`（19 文件 41 处）。子项目目录（platform/、storefront/、backend/ 下的 .github/workflows）为独立包模板，GitHub 不识别，不改。

## Step 1 Skill 咨询

| Skill | 结论 |
|---|---|
| pallastrade-deployment | 已读：不影响（清理脚本与 CI，非应用部署配置） |
| pallastrade-customization | 已读：不涉定制决策树 |
| harness-prd | 已读：简版 REQ |

## 验证方案（AC ↔ 命令）

| AC | 验证 |
|---|---|
| AC-001 prod 文件已删 | `ls deploy/docker-compose.prod.yml deploy/prod.sh` 不存在 |
| AC-002 脚本只留 dev | `grep -c "main\|prod" deploy/deploy.sh deploy/pull-deploy.sh` 仅剩注释/无 |
| AC-003 workflows 只监听 dev | `grep -rn "branches: \[main" .github/workflows/` 无结果；harness-full `--base origin/dev` |
| AC-004 服务器 prod 无残留 | docker images/volumes 无 prod（已验） |

## 变更文件（allow: deploy/** + .github/workflows/**）
