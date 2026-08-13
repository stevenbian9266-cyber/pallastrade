# PallasTrade 阿里云部署运维手册

> 本手册定义本项目服务器部署与栈切换的**标准机制**，是 dev/prod 双环境部署的唯一权威说明。
> 服务器：阿里云 ECS `115.29.185.128`（cn-hangzhou-j，2C/3.5G，8G swap），代码目录 `/opt/pallastrade/repo`。

## 环境与域名

| 环境 | 域名 | backend 端口 | storefront 端口 | 数据库 |
|---|---|---|---|---|
| dev | `dev.pallastrade.cn` | 3102 | 3103 | 独立 PostgreSQL（dev 栈） |
| prod | `pallastrade.cn` | 3100 | 3101 | 独立 PostgreSQL（prod 栈） |

> ⚠️ **dev 与 prod 使用相互独立的数据库**。示例数据（如三级分类）必须分别在两个环境创建。

## 快捷脚本（在 `/opt/pallastrade/repo/deploy/` 内执行）

| 脚本 | 用法 | 说明 |
|---|---|---|
| `prod.sh` | `bash prod.sh up\|down\|status` | prod 栈启停（down 保留数据卷） |
| `dev.sh` | `bash dev.sh up\|down\|status` | dev 栈启停（down 保留数据卷） |
| `deploy.sh` | `bash deploy.sh dev\|prod` | 全量部署（backend 服务器构建 + storefront 镜像检查 + 启动 + 健康检查；自动停另一栈） |

## 单栈策略（强制）

服务器 2C/3.5G 无法承受双栈并行（会 OOM），**任一时刻只允许一个栈运行**：

- **默认态（常驻）：dev 栈运行，prod 栈停止**
- prod 按需启动：先 `bash dev.sh down` 再 `bash prod.sh up`
- 切栈用 `deploy.sh prod`（自动 `down` dev）或手动 `prod.sh down` + `dev.sh up`

## 标准部署流程（任务结束后机制）

**任何涉及 storefront 代码的任务结束，必须按以下顺序完成部署：**

1. **本地验证**：`pnpm vitest run` + `pnpm build` + 浏览器实测（localhost:3001）
2. **构建 storefront 镜像**（本地，服务器不能跑 next build 会 OOM）：

   ```powershell
   $env:HTTP_PROXY='http://127.0.0.1:7890'; $env:HTTPS_PROXY='http://127.0.0.1:7890'; $env:NO_PROXY='host.docker.internal,localhost,127.0.0.1'
   docker build -f storefront/Dockerfile `
     --build-arg PALLASTRADE_API_URL=http://host.docker.internal:3000 `
     --build-arg PALLASTRADE_PUBLISHABLE_KEY=<本地key> `
     --build-arg NEXT_PUBLIC_TAWK_TO_PROPERTY_ID=6a32b7a845840f1d49424bd9 `
     --build-arg NEXT_PUBLIC_TAWK_TO_WIDGET_ID=1jrb1qrcu `
     --build-arg NEXT_PUBLIC_TURNSTILE_SITE_KEY=0x4AAAAAADhWPvWYVdWLedL2 `
     --build-arg NEXT_PUBLIC_GTM_ID=<GTM-ID，可选> `
     -t pallastrade-{dev|prod}-storefront:latest .
   ```

   > `NEXT_PUBLIC_*` 在构建时内联进 bundle，必须作为 build-arg 传入；tawk.to 两个 ID 与 Turnstile site key（PRD-20260812，公开值）必须带。GTM ID（`NEXT_PUBLIC_GTM_ID`）为可选的公开 ID，供 cookie consent 门控加载（PRD-20260812）。

3. **部署 dev**：
   - `docker save` → `tar -czf` → `scp` 到服务器 `/tmp/` → `gunzip | tar -xf` → `docker load`
   - `docker compose -f docker-compose.dev.yml --env-file .env.dev up -d storefront`（recreate 用新镜像）
   - 验证 `https://dev.pallastrade.cn/us/zh`（首页板块 / nav 面板 / 三级分类 / llms.txt / tawk 挂件）
4. **部署 prod**：
   - 构建 prod 镜像 → save/scp/load（同上）
   - `bash deploy.sh prod`（自动停 dev 栈，启动 prod + 健康检查）
   - 验证 `https://pallastrade.cn/us/zh`
   - **数据改动需同步 prod 独立库**（如新建三级分类：`docker exec pallastrade-prod-web-1 bundle exec rails runner <脚本>`）
5. **最终状态（本机制默认态）**：`bash prod.sh down` → `bash dev.sh up`，**启动 dev，关闭 prod**。

## 环境配置（服务器 `/opt/pallastrade/repo/deploy/`）

| 文件 | 内容 |
|---|---|
| `.env.dev` / `.env.prod` | backend 密钥（SECRET_KEY_BASE 等） |
| `.env.storefront.dev` / `.env.storefront.prod` | storefront 运行时环境（API URL、STORE_LOGO_URL、tawk ID 等） |
| `.env.storefront.dev.example` 等 | 模板（复制改名填写） |

## GitHub Actions 自动部署（拉取式 / 方案 A）

> ⚠️ 跨境 SSH（GitHub runner 美国 → 阿里云杭州）TCP 22 被阻断，rsync/scp/ssh 推送式部署不可用。

**拉取式机制**：
1. `deploy.yml`（监听 `[main, dev]` 推送）：runner 构建 storefront 镜像 → **push 到 ghcr.io**（`ghcr.io/stevenbian9266-cyber/pallastrade-storefront:{dev|main}`），不再连接服务器
2. 服务器 cron 每 5 分钟运行 `deploy/pull-deploy.sh dev`：`git fetch` + `docker pull`，检测到 HEAD 或镜像 digest 变化才执行 `deploy.sh`

**前提（一次性配置）**：
- GitHub 仓库 Deploy Keys 已添加服务器公钥（`/root/.ssh/id_ed25519.pub`，名称 `pallastrade-deploy`）
- ghcr.io 包 `pallastrade-storefront` 设为 **Public**（镜像仅含公开信息：`pk_` 公钥、turnstile site key、tawk ID，无 secrets）
- 服务器 `/opt/pallastrade/repo` 已 `git init` + remote 指向仓库

**常用命令**：
```bash
crontab -l                                   # 查看拉取任务
tail -f /var/log/pallastrade-pull.log        # 查看拉取部署日志
bash deploy/pull-deploy.sh dev               # 手动触发一次检查
```

- 需要仓库 **Actions Variables**：`TAWK_TO_PROPERTY_ID` / `TAWK_TO_WIDGET_ID`（公开变量，非 Secrets）。
- 未配置时挂件禁用，不影响部署。

## 常用运维命令

```bash
# 健康检查（服务器上）
curl -sf http://127.0.0.1:3102/up   # dev backend
curl -sf http://127.0.0.1:3103/us/zh # dev storefront
curl -sf http://127.0.0.1:3100/up   # prod backend

# 查看容器
docker ps | grep pallastrade-{dev,prod}

# 内存（单栈策略依据）
free -m
```
