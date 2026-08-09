# REQ-20260809-infra-aliyun-dev-prod-deploy — 阿里云 dev/prod 双环境部署

> 关联 PRD：`docs/prd/infra/PRD-20260809-infra-aliyun-dev-prod-deploy.md`
> 任务类型：feature（需求：部署双环境 + CI 自动部署）

## Step 0：跨层搜索

| 层 | 路径 | 关键词 | 找到 | 是否满足 |
|---|---|---|---|---|
| backend | backend/docker-compose.yml | web/worker/postgres/redis/meilisearch/mailpit | 完整服务定义 | 复用 |
| backend | backend/Dockerfile | Rails 镜像 | 存在 | 复用 |
| storefront | storefront/Dockerfile | PALLASTRADE_API_URL build-arg | 存在 | 复用 |
| storefront | storefront/.env.example | PALLASTRADE_API_URL/PUBLISHABLE_KEY 等 | 变量清单 | 复用 |
| CI | .github/workflows/ | storefront-ci/backend-ci | workflow_call 模式 | 参考 |
| skill | ai/skills/pallastrade-deployment | RAILS_HOST/FORCE_SSL/ASSUME_SSL | env 依据 | 依据 |
| 服务器 | nginx sites-enabled | pallastrade/dev.pallastrade.cn | 已有反代+证书 | 复用/微调 |

**结论**：全部复用现有能力（compose 服务、Dockerfile、nginx、证书），需新增 deploy/ 配置 + CI workflow + 服务器编排。

## Step 1：Skill 文件咨询

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `pallastrade-customization/SKILL.md` | ✅ 已读 | 部署属 infra 层，走 pallastrade-deployment |
| `pallastrade-deployment/SKILL.md` | ✅ 已读 | RAILS_HOST/FORCE_SSL/ASSUME_SSL；Plain Docker + 反代 SSL 终止；SMTP 必配 |
| `pallastrade-prd/SKILL.md` | ✅ 已读 | §6 接口/CI 同步 |

---

## 需求标题

阿里云 dev/prod 双环境 Docker 部署 + CI 自动部署

## 需求描述

- prod 栈（pallastrade.cn）：backend 3100 + storefront 3101 + 独立依赖，RAILS_HOST=pallastrade.cn
- dev 栈（dev.pallastrade.cn）：backend 3102 + storefront 3103 + 独立依赖，RAILS_HOST=dev.pallastrade.cn
- nginx：prod storefront 3001→3101；dev 已配
- CI：push main→prod、push dev→dev（SSH 服务器执行 deploy.sh）
- 清理：shopdemo 容器已停（数据保留）

## 影响文件

- 新增：`deploy/docker-compose.prod.yml`、`deploy/docker-compose.dev.yml`、`deploy/deploy.sh`、`deploy/.env.{prod,dev}.example`
- 新增：`.github/workflows/deploy.yml`
- 服务器：/opt/pallastrade/repo、nginx 微调

## 测试计划

- 服务器：docker ps、curl /up、浏览器访问两域名
- CI：workflow_dispatch 手动触发验证
