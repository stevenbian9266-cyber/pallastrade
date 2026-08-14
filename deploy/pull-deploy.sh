#!/usr/bin/env bash
# PallasTrade 拉取式部署（方案 A）
#   服务器主动拉取代码（git）和 storefront 镜像（ghcr.io），检测到变化才部署。
#   解决跨境 SSH 被阻断问题：GitHub runner（美国）→ 阿里云（杭州）的 TCP 22 不通，
#   但服务器出站到 github.com / ghcr.io 实测通畅。
#
#   用法: bash deploy/pull-deploy.sh dev       # 部署 dev 栈（dev.pallastrade.cn）
#         bash deploy/pull-deploy.sh main      # 部署 prod 栈（pallastrade.cn）
#
#   cron 安装（每 5 分钟检查一次）：
#     */5 * * * * /opt/pallastrade/repo/deploy/pull-deploy.sh dev >> /var/log/pallastrade-pull.log 2>&1
set -euo pipefail

ENV="${1:-dev}"
cd /opt/pallastrade/repo

case "$ENV" in
  main|prod)
    echo "❌ prod 部署已禁用（2026-08-15 部署规则调整：仅部署 dev）。" >&2
    exit 1
    ;;
  dev)
    BRANCH="dev"
    SF_IMG="pallastrade-dev-storefront:latest"
    ;;
  *)
    echo "用法: pull-deploy.sh dev   （prod 已禁用）" >&2
    exit 1
    ;;
esac

GHCR_IMG="ghcr.io/stevenbian9266-cyber/pallastrade-storefront:${BRANCH}"
STATE_FILE="/opt/pallastrade/.pull-deploy-state-${ENV}"
LOCK_FILE="/tmp/pull-deploy-${ENV}.lock"

# 防并发：上次拉取/部署未结束时直接退出
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "[$(date '+%F %T')] 已有部署进程在运行，跳过本次检查" >&2
  exit 0
fi

echo "=== pull-deploy ($ENV) $(date '+%F %T') ==="

# 1. 拉取代码（60s 超时，防 git fetch 挂起）
if ! timeout 60 git fetch origin "$BRANCH" --quiet 2>/dev/null; then
  echo "❌ git fetch 失败/超时（检查 deploy key 与网络），跳过部署" >&2
  exit 1
fi
NEW_HEAD="$(git rev-parse "origin/$BRANCH")"

# 2. 拉取 storefront 镜像（失败/超时不致命：可能 CI 尚未推送过）
NEW_IMG_ID="none"
if timeout 180 docker pull "$GHCR_IMG" >/dev/null 2>&1; then
  NEW_IMG_ID="$(docker image inspect "$GHCR_IMG" --format '{{.Id}}' 2>/dev/null || echo none)"
else
  echo "⚠️ docker pull $GHCR_IMG 失败/超时，使用本地已有镜像" >&2
fi

# 3. 变化检测
OLD_HEAD=""; OLD_IMG_ID=""
if [ -f "$STATE_FILE" ]; then
  OLD_HEAD="$(sed -n 1p "$STATE_FILE")"
  OLD_IMG_ID="$(sed -n 2p "$STATE_FILE")"
fi

if [ "$NEW_HEAD" = "$OLD_HEAD" ] && [ "$NEW_IMG_ID" = "$OLD_IMG_ID" ]; then
  echo "✅ 无变化（head=${NEW_HEAD:0:8} img=${NEW_IMG_ID:0:12}），跳过部署"
  exit 0
fi

echo "🔔 检测到变化: head ${OLD_HEAD:0:8}→${NEW_HEAD:0:8}, img ${OLD_IMG_ID:0:12}→${NEW_IMG_ID:0:12}"

# 4. 部署（整体 15 分钟超时，防 deploy.sh 内部卡死）
git reset --hard "origin/$BRANCH"
if [ "$NEW_IMG_ID" != "none" ]; then
  docker tag "$GHCR_IMG" "$SF_IMG"
fi
timeout 900 bash deploy/deploy.sh "$ENV" || echo "⚠️ deploy.sh 超时/失败（exit=$?），状态可能未完成" >&2

# 5. 记录状态
mkdir -p "$(dirname "$STATE_FILE")"
printf '%s\n%s\n' "$NEW_HEAD" "$NEW_IMG_ID" > "$STATE_FILE"
echo "✅ 部署完成，状态已记录"
