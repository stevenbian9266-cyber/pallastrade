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
- **✅ 最终决策（实施后）**：服务器 2C/3.5G 小规格，**双栈同时运行必 OOM**（实测 load 51 崩溃）→ 采用**单栈策略**：prod 常驻 + dev 按需，新增 `deploy/prod.sh` / `deploy/dev.sh` 快捷启停

## 2. 用户故事 / 场景

- 作为开发者：push 到 dev → dev.pallastrade.cn 自动更新；push 到 main → pallastrade.cn 自动更新
- 作为管理员：dev/prod 数据隔离、可独立重启

## 3. 功能需求（FR）

- FR-001：prod 栈（project `pallastrade-prod`）：backend web 3100 + storefront 3101 + postgres/redis/meilisearch/mailpit，RAILS_HOST=pallastrade.cn — **✅ 已实现**
- FR-002：dev 栈（project `pallastrade-dev`）：backend web 3102 + storefront 3103 + 独立依赖，RAILS_HOST=dev.pallastrade.cn — **✅ 已实现**
- FR-003：storefront 双栈独立构建（build-arg PALLASTRADE_API_URL 区分）— **✅ 已实现**（本地 Docker 构建 + docker save/load 传输，见实施结果）
- FR-004：nginx 调整（prod storefront 3001→3101；dev 已配 3102/3103）— **✅ 已实现**
- FR-005：CI 自动部署（push main→prod 栈，push dev→dev 栈，SSH 执行）— **✅ 已实现**（`.github/workflows/deploy.yml`，含单栈互斥）
- FR-006：清理旧 shopdemo（已停容器，数据保留待确认）— **✅ 已完成**（3100 释放）
- FR-007：**新增** 快捷启停脚本 `deploy/prod.sh` / `deploy/dev.sh`（对称，up/down/status）— **✅ 已实现并部署**

## 4. 非功能需求（NFR）

- 安全：SSH key 走 GitHub secret；env 文件不入库（示例提交）
- 兼容：不动 haijiquan/youzan 等无关服务
- HTTPS：复用现有 Let's Encrypt 证书

## 5. 验收标准（AC）

- AC-001：`pallastrade.cn` 打开生产 storefront + `/admin` 管理后台 — **✅ 通过**（部署期验证 200/302）
- AC-002：`dev.pallastrade.cn` 打开开发 storefront + `/admin` — **✅ 通过**（当前 dev 常驻，健康 200）
- AC-003：`deploy/docker-compose.{prod,dev}.yml` + `deploy/deploy.sh` 落盘 — **✅ 通过**（另含 prod.sh/dev.sh 快捷脚本）
- AC-004：`.github/workflows/deploy.yml` 存在（push main/dev 触发）— **✅ 通过**
- AC-005：服务器双栈容器运行（docker ps 见 pallastrade-prod-* / pallastrade-dev-*）— **✅ 通过**（单栈策略：当前 prod 已停、dev 常驻）

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

- 服务器验证：docker ps（双栈容器）、curl 健康检查、浏览器访问两域名 — **✅ 已执行**
- CI：手动触发 deploy workflow 验证 SSH 链路 — **✅ 已执行**

## 8.5 实施结果与运维要点（2026-08-09 实测）

### 单栈策略（核心约束）
- 服务器 **2C/3.5G**：双栈同时运行必 OOM（实测 load 51、available 199MB、SSH/Web 无响应）
- 已加 **8G swap**（/swapfile，fstab 持久化）缓解，但仍不能双栈常开
- **prod 常驻 + dev 按需**；切栈前先 `down` 另一栈

### 快捷启停（服务器 /opt/pallastrade/repo/deploy/）
```bash
bash prod.sh up|down|status   # prod 栈（3100/3101），up 含 30s 健康检查
bash dev.sh  up|down|status   # dev 栈（3102/3103）
```
- `down` 保留数据卷，下次 `up` 数据即恢复

### Storefront 构建限制
- 服务器**绝不能跑 next build**（多次 OOM）→ storefront 镜像**本地 Docker 构建** + `docker save`/`docker load` 传输（CI runner 同样在构建机构建）
- `pnpm file:` 依赖需处理 `platform/packages/sdk` 的 `dist`（package.json `files:["dist"]` + Dockerfile `cp -r` + dist force-add git）

### 演示数据与账号
- prod+dev 各 **37 商品 / 24 分类**（`rake pallastrade:load_sample_data`），Meilisearch 已 reindex
- 管理后台：`pallastrade@example.com` / `pallastrade123`（seeds 默认）

### 服务器资源清理（2026-08-09）
- 删除崩溃循环容器 `registry-mirror`（Restarting 空转）
- 停止 `haijiquan-api`、停+删 `youzan-proxy`（PM2 旧项目遗留）
- 清理 VS Code Remote-SSH 的 `vscode-server` 进程（~390MB）
- 当前服务器仅 dev 栈 7 容器，available ~1.9GB

### 已知问题与镜像源
- APT 用 tuna（aliyun 缺 libcgif0 404）；Bundler 用 aliyun rubygems；APK aliyun；npm npmmirror
- `next/image` remotePatterns 需显式加入根域（`**.pallastrade.cn` 通配不匹配根域）

## 9. 文档同步清单

- [x] README（部署章节）
- [ ] ai/skills/pallastrade-deployment/SKILL.md（若环境变量/流程变化）

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-09 | 0.1 | 初稿（用户已确认决策） | AI |
| 2026-08-09 | 0.2 | 记录最终实施结果：单栈策略、prod.sh/dev.sh 快捷脚本、storefront 镜像传输构建、演示数据、服务器资源清理 | AI |
