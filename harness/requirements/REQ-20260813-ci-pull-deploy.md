# REQ-20260813-CI-Pull-Deploy（拉取式部署）

## 背景

现有 `deploy.yml` 为**推送式**：GitHub runner（美国）→ rsync/scp/ssh → 阿里云服务器（杭州）。
实测：跨境 TCP 22 被阻断，CI run 31661327126 卡在 rsync 步骤（服务器 auth.log 无任何 runner 连接记录）。
服务器出站测试：github.com:22/443 ✅、ghcr.io ✅、docker.io ❌。

## 目标

改为**拉取式**：CI 只负责构建 + 推送镜像到 ghcr.io；服务器 cron 每 5 分钟主动拉代码 + 拉镜像，检测到变化才部署。

## 架构

```
GitHub push (dev/main)
  → CI: 构建 storefront 镜像 → push ghcr.io/stevenbian9266-cyber/pallastrade-storefront:{dev|main}
服务器 cron (每 5 分钟): deploy/pull-deploy.sh
  → git fetch origin (SSH deploy key)
  → docker pull ghcr.io/...storefront:{dev|main} (匿名拉取，包公开)
  → HEAD 或镜像 digest 变化 → git reset --hard + docker tag + deploy.sh
```

## 改动清单

| 文件 | 改动 |
|---|---|
| `.github/workflows/deploy.yml` | 重写：删 rsync/scp/ssh 三步；build 后 docker login ghcr + push；concurrency 改 cancel-in-progress: true |
| `deploy/pull-deploy.sh` | 新建：git fetch + docker pull + 变化检测（状态文件 `/opt/pallastrade/.deploy-state`）+ 调 deploy.sh |
| `deploy/.gitignore` | 新建：`.env*`（防 git pull 覆盖服务器 env 文件） |
| `deploy/README.md` | 更新部署架构说明 |
| `ai/skills/pallastrade-deployment/SKILL.md` | 更新 CI 机制描述 |

## 服务器一次性配置（我通过 SSH 执行）

1. `git init` + remote + SSH config（用已有 `pallastrade-deploy` 密钥）
2. 安装 cron（每 5 分钟 pull-deploy.sh dev）

## 需要用户的一次性操作（仅 GitHub 网页，无替代方案）

1. **Deploy key**：把服务器公钥添加到仓库 Deploy Keys（我已准备好公钥文本，粘贴即可）
2. **ghcr 包公开**：`pallastrade-storefront` 包设为 Public（镜像只含公开信息：pk 公钥/turnstile site key/tawk ID，无 secrets）

## 回滚方案

- `deploy/deploy.sh dev` 保持不变，手动部署流程不受影响
- 若拉取式失败：cron 可随时移除（`crontab -e` 删一行）

## 验证计划

1. 推送代码 → CI 绿色 + ghcr 出现新镜像 tag
2. 服务器 cron 自动部署 → dev.pallastrade.cn cookie/turnstile 功能正常
3. 记录证据（log + 截图）
