# PRD-20260809-infra-aliyun-dev-prod-deploy

| 元数据 | 值 |
|---|---|
| 状态 | approved |
| 创建日期 | 2026-08-09 |
| 来源 | 需求：dev 部署 dev.pallastrade.cn + 生产部署 pallastrade.cn（阿里云 + CI 自动部署） |
| 分类 | infra（部署 / 基础设施） |
| 关联 Skill | pallastrade-deployment |
| 关联 REQ | REQ-20260809-infra-aliyun-dev-prod-deploy.md |
| 需求类型 | 新功能（部署基础设施） |

## 1. 背景与目标

- **背景**：项目需在阿里云服务器（115.29.185.128）部署双环境——生产 `pallastrade.cn`、开发 `dev.pallastrade.cn`，以接入三方服务（Tawk 客服、阿里云 OSS、Cloudflare Turnstile 人机验证等）验证
- **现状**：服务器已有 nginx（pallastrade.cn/dev.pallastrade.cn 反代 + Let's Encrypt 证书）+ PM2 storefront(3001)，但 backend 3100 被旧 shopdemo 容器占用；无自动部署
- **目标**：Docker 双栈（prod/dev 独立容器组）+ CI 自动部署；清理旧 shopdemo
- **成功指标**：`pallastrade.cn` 访问生产、`dev.pallastrade.cn` 访问开发；push dev/main 自动部署

## 2. 用户故事 / 场景

- 作为开发者：push 到 dev → dev.pallastrade.cn 自动更新；push 到 main → pallastrade.cn 自动更新
- 作为管理员：dev/prod 数据隔离、可独立重启

## 3. 功能需求（FR）

- FR-001：prod 栈（project `pallastrade-prod`）：backend web 3100 + storefront 3101 + postgres/redis/meilisearch/mailpit，RAILS_HOST=pallastrade.cn
- FR-002：dev 栈（project `pallastrade-dev`）：backend web 3102 + storefront 3103 + 独立依赖，RAILS_HOST=dev.pallastrade.cn
- FR-003：storefront 双栈独立构建（build-arg PALLASTRADE_API_URL 区分）
- FR-004：nginx 调整（prod storefront 3001→3101；dev 已配 3102/3103）
- FR-005：CI 自动部署（push main→prod 栈，push dev→dev 栈，SSH 执行）
- FR-006：清理旧 shopdemo（已停容器，数据保留待确认）

## 4. 非功能需求（NFR）

- 安全：SSH key 走 GitHub secret；env 文件不入库（示例提交）
- 兼容：不动 haijiquan/youzan 等无关服务
- HTTPS：复用现有 Let's Encrypt 证书

## 5. 验收标准（AC）

- AC-001：`pallastrade.cn` 打开生产 storefront + `/admin` 管理后台
- AC-002：`dev.pallastrade.cn` 打开开发 storefront + `/admin`
- AC-003：`deploy/docker-compose.{prod,dev}.yml` + `deploy/deploy.sh` 落盘
- AC-004：`.github/workflows/deploy.yml` 存在（push main/dev 触发）
- AC-005：服务器双栈容器运行（docker ps 见 pallastrade-prod-* / pallastrade-dev-*）

## 6. 跨层搜索记录

| 层 | 路径 | 关键词 | 找到 |
|---|---|---|---|
| backend | backend/docker-compose.yml | web/worker/postgres/redis/meilisearch/mailpit | 复用服务定义 |
| storefront | storefront/Dockerfile | PALLASTRADE_API_URL build-arg | 复用 |
| CI | .github/workflows/*.yml | storefront-ci/backend-ci | workflow 模式参考 |
| ai/skills | pallastrade-deployment | RAILS_HOST/FORCE_SSL/ASSUME_SSL | 环境变量依据 |
| 服务器 | nginx sites-enabled | pallastrade/dev.pallastrade.cn | 已有反代+证书 |

## 7. 技术影响

- 新增 `deploy/`（compose prod/dev、deploy.sh、env 示例）
- 新增 `.github/workflows/deploy.yml`
- 服务器：nginx prod storefront 端口 3001→3101；建 /opt/pallastrade/repo

## 8. 测试计划

- 服务器验证：docker ps（双栈容器）、curl 健康检查、浏览器访问两域名
- CI：手动触发 deploy workflow 验证 SSH 链路

## 9. 文档同步清单

- [ ] README（部署章节）
- [ ] ai/skills/pallastrade-deployment/SKILL.md（若环境变量/流程变化）

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-09 | 0.1 | 初稿（用户已确认决策） | AI |
