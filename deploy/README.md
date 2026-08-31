# PallasTrade 阿里云部署运维手册

> 本手册定义本项目服务器部署与栈切换的**标准机制**，是 dev 部署的唯一权威说明。
> 服务器：阿里云 ECS `115.29.185.128`（cn-hangzhou-j，2C/3.5G，8G swap），代码目录 `/opt/pallastrade/repo`。

> ## ⛔ 部署规则（2026-08-31 起）
> **仅部署 dev（dev.pallastrade.cn）。**
> GitHub main 分支、服务器 prod 栈（镜像/数据卷/数据库/配置）已全部删除，仓库脚本与 CI 只保留 dev。

## 环境与域名

| 环境 | 域名 | backend 端口 | storefront 端口 | 数据库 | 状态 |
|---|---|---|---|---|---|
| dev | `dev.pallastrade.cn` | 3102 | 3103 | 独立 PostgreSQL（dev 栈） | ✅ 常驻部署 |

## 快捷脚本（在 `/opt/pallastrade/repo/deploy/` 内执行）

| 脚本 | 用法 | 说明 |
|---|---|---|
| `dev.sh` | `bash dev.sh up\|down\|status` | dev 栈启停（down 保留数据卷） |
| `deploy.sh` | `bash deploy.sh dev` | 全量部署 dev（backend 服务器构建 + storefront 镜像检查 + 启动 + 健康检查） |
| `deploy-sf.sh` | `bash deploy-sf.sh` | 仅 storefront 单独构建部署（源码整目录同步 + 特征校验 + 磁盘预检） |

## 单栈策略

prod 栈已删除（2026-08-31），服务器仅运行 dev 栈（常驻）。

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
     -t pallastrade-dev-storefront:latest .
   ```

   > `NEXT_PUBLIC_*` 在构建时内联进 bundle，必须作为 build-arg 传入；tawk.to 两个 ID 与 Turnstile site key（PRD-20260812，公开值）必须带。GTM ID（`NEXT_PUBLIC_GTM_ID`）为可选的公开 ID，供 cookie consent 门控加载（PRD-20260812）。

3. **部署 dev**：
   - `docker save` → `tar -czf` → `scp` 到服务器 `/tmp/` → `gunzip | tar -xf` → `docker load`
   - `docker compose -f docker-compose.dev.yml --env-file .env.dev up -d storefront`（recreate 用新镜像）
   - 验证 `https://dev.pallastrade.cn/us/zh`（首页板块 / nav 面板 / 三级分类 / llms.txt / tawk 挂件）
5. **最终状态（本机制默认态）**：dev 栈常驻运行。

## 环境配置（服务器 `/opt/pallastrade/repo/deploy/`）

| 文件 | 内容 |
|---|---|
| `.env.dev` | backend 密钥（SECRET_KEY_BASE 等） |
| `.env.storefront.dev` | storefront 运行时环境（API URL、STORE_LOGO_URL、tawk ID 等） |
| `.env.storefront.dev.example` 等 | 模板（复制改名填写） |

## GitHub Actions 自动部署（拉取式 / 方案 A）

> ⚠️ 跨境 SSH（GitHub runner 美国 → 阿里云杭州）TCP 22 被阻断，rsync/scp/ssh 推送式部署不可用。

**拉取式机制**：
1. `deploy.yml`（监听 `[dev]` 推送）：runner 构建 storefront 镜像 → **push 到 ghcr.io**（`ghcr.io/stevenbian9266-cyber/pallastrade-storefront:dev`），不再连接服务器
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

# 查看容器
docker ps | grep pallastrade-dev

# 内存（单栈策略依据）
free -m
```

## 部署故障处理（复盘 2026-08-31）

### 1. 磁盘满级联（最常见）

**症状链**：磁盘 <5G → git fetch / docker pull 挂起 → cron 卡死 → 后续所有部署跳过。

- **预防**：`pull-deploy.sh` 与 `deploy-sf.sh` 已内置磁盘预检（<5G 自动 `docker builder prune -f`，仍不足则跳过本轮）
- **恢复**：`df -h` 确认；`docker builder prune -f`；卡死进程 `pkill -f pull-deploy`
- **锁泄漏**：flock 锁随进程退出自动释放；残留 `/tmp/pull-deploy-dev.lock` 可安全删除

### 2. storefront 构建超时（corepack）

- **症状**：构建日志 `UND_ERR_CONNECT_TIMEOUT`，deps/builder 阶段首次 pnpm 命令触发
- **根因**：corepack 按 `package.json` 的 `packageManager` 从 npm 官方源下载 pnpm（服务器直连官方源超时）
- **修复**：`storefront/Dockerfile` 两阶段均设 `COREPACK_NPM_REGISTRY=https://registry.npmmirror.com` + `corepack prepare`
- **维护**：`packageManager` 版本升级时同步改 Dockerfile；`deploy-sf.sh` 有特征校验（缺失即中止）

### 3. 禁止在服务器 repo 使用 git pull

服务器分支历史与本地不一致，`git pull` 会冲突。统一使用：

```bash
cd /opt/pallastrade/repo
git fetch origin dev -q
git checkout origin/dev -- <变更文件或目录>
```

`deploy-sf.sh` 已按此模式整目录同步 `storefront/`。

### 4. 远程命令引号规范

本地 PowerShell → 服务器 SSH 的多层引号极易破坏（`&`、`$`、`{{...}}`、`-o` 均会被 PS 解释）：

- **规则**：复杂命令一律写 `.sh` → `scp` 上传 → `ssh "bash /tmp/x.sh"`
- **后台任务**：`nohup bash x.sh > /tmp/x.log 2>&1 < /dev/null &`（`< /dev/null` 断开 stdin，防 SSH 会话卡住），然后新开会话 `tail -f /tmp/x.log` 轮询

### 5. 构建期应用层超时是预期

服务器 2C/3.5G，backend 构建（bundle install）期间一切应用层请求超时属正常；**30 分钟内不恢复**才排查 deploy.sh 是否卡死。判定依据：`ps aux | grep 'docker.*build'` 进程存活且未超时。

### 6. 探活端点统一用 `/up`

- backend 健康端点：`/up`（`/health` 不存在，会 404 误判）
- storefront：`/us/en`（200 正常；`307` 为 locale 重定向，同样视为通过）
