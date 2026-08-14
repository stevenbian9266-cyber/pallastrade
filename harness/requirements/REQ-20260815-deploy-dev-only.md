# REQ-20260815-deploy-dev-only

| 元数据 | 值 |
|---|---|
| Task | TASK-20260814161845-cdc96101 |
| Gate | GATE-2026-08-14T16-19-08 |
| 类型 | 优化（部署规则调整） |
| 关联 PRD | PRD-20260809-infra-aliyun-dev-prod-deploy（§8.6） |

## 需求

**部署规则调整：后续部署只部署 dev，不再部署 prod。**

服务器 2C/3.5G 单栈策略下，prod 部署会 down dev 栈并占用全部资源；用户决策 prod 不再部署上线，仅维护 dev（dev.pallastrade.cn）。

## 跨层搜索记录

| 层 | 路径 | 关键词 | 找到 |
|---|---|---|---|
| App | backend/app/ | 部署、prod | 无相关 |
| Core | pallastrade_core/ | 部署 | 无 |
| API | pallastrade_api/ | 部署 | 无 |
| Admin | pallastrade_admin/ | 部署 | 无 |
| Storefront | storefront/ | 部署 | 无（部署在 deploy/） |
| Platform | platform/packages/ | 部署 | 无 |
| **deploy/** | deploy/deploy.sh、pull-deploy.sh、prod.sh、dev.sh | prod、main | **本次修改点** |
| **CI** | .github/workflows/deploy.yml | prod、main | storefront 镜像构建（main Deploy 失败 pre-existing，不影响后端） |
| 服务器 | crontab | pull-deploy | 仅 dev cron（已符合） |

## Skill 咨询证据表

| Skill | 结论 |
|---|---|
| pallastrade-deployment | 部署环境/命令约定；本次为部署脚本规则调整 |
| pallastrade-customization | 决策树确认：部署运维属平台层，直接改 deploy/ 脚本（非 gem/业务代码） |
| pallastrade-prd | 一句话需求 → PRD 回写更新原 PRD（查重命中 33%） |

## 改动清单

1. `deploy/deploy.sh`：`main|prod` 参数 → 拒绝部署（提示 + exit 1）
2. `deploy/pull-deploy.sh`：`main|prod` → 拒绝（提示 + exit 1）
3. `deploy/prod.sh`：`up` 拒绝；`down`/`status` 保留
4. `deploy/README.md`：更新部署规则（仅 dev，prod 已禁用）
5. `docs/prd/infra/PRD-20260809-infra-aliyun-dev-prod-deploy.md`：§8.6 + 变更记录（已更新）

## 验收标准（AC）

- AC-001：`bash deploy.sh prod|main` → 拒绝并提示，exit 1
- AC-002：`bash pull-deploy.sh main|prod` → 拒绝，exit 1
- AC-003：`bash prod.sh up` → 拒绝；`prod.sh down|status` 可用
- AC-004：`bash deploy.sh dev` 正常部署（dev 栈不受影响）
- AC-005：服务器 cron 仅 `pull-deploy.sh dev`（已符合，无需改）

## 验证证据

- 脚本语法：服务器 `bash -n` 验证
- 行为验证：服务器执行 `deploy.sh prod` / `pull-deploy.sh main` / `prod.sh up` 确认拒绝
- dev 部署不受影响：当前 dev 栈在线（healthy）
