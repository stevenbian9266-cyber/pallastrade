#!/usr/bin/env bash
# PallasTrade 拉取式部署（方案 A）
#   服务器主动拉取代码（git）和 storefront 镜像（ghcr.io），检测到变化才部署。
#   解决跨境 SSH 被阻断问题：GitHub runner（美国）→ 阿里云（杭州）的 TCP 22 不通，
#   但服务器出站到 github.com / ghcr.io 实测通畅。
#
#   用法: bash deploy/pull-deploy.sh dev       # 部署 dev 栈（dev.pallastrade.cn）
#   ⚠️ 2026-08-31 起只保留 dev；main 分支与 prod 栈已删除（见 README）
#
#   cron 安装（每 5 分钟检查一次）：
#     */5 * * * * /opt/pallastrade/repo/deploy/pull-deploy.sh dev >> /var/log/pallastrade-pull.log 2>&1
set -euo pipefail

ENV="${1:-dev}"
cd /opt/pallastrade/repo

if [ "$ENV" != "dev" ]; then
  echo "用法: pull-deploy.sh dev   （仅支持 dev）" >&2
  exit 1
fi
BRANCH="dev"
SF_IMG="pallastrade-dev-storefront:latest"

GHCR_IMG="ghcr.io/stevenbian9266-cyber/pallastrade-storefront:${BRANCH}"
STATE_FILE="/opt/pallastrade/.pull-deploy-state-${ENV}"
LOCK_FILE="/tmp/pull-deploy-${ENV}.lock"

# 防并发：上次拉取/部署未结束时直接退出
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "[$(date '+%F %T')] 已有部署进程在运行，跳过本次检查" >&2
  exit 0
fi

# 0. 磁盘预检（复盘 2026-08-31：磁盘满 → git fetch/pull 挂起 → 级联故障）
MIN_FREE_KB=5242880 # 5GB
AVAIL_KB="$(df -P /opt | awk 'NR==2 {print $4}')"
if [ "$AVAIL_KB" -lt "$MIN_FREE_KB" ]; then
  echo "[$(date '+%F %T')] ⚠️ 磁盘可用 ${AVAIL_KB}KB < 5GB，执行 builder prune" >&2
  docker builder prune -f >/dev/null 2>&1 || true
  AVAIL_KB="$(df -P /opt | awk 'NR==2 {print $4}')"
fi
if [ "$AVAIL_KB" -lt "$MIN_FREE_KB" ]; then
  echo "[$(date '+%F %T')] ❌ 磁盘仍不足 5GB，跳过本轮（防级联挂起）" >&2
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
# PALLAS-CUSTOM bugfix (2026-09-11): 180s 在跨境带宽下经常不足（实测每轮均超时，
# 永远回退本地旧镜像 → storefront 镜像更新实际依赖手动）。放宽到 900s，与
# deploy.sh 同量级；docker 已完成层跨轮复用（Already exists），未完成层下轮重下，
# 多轮可累积完成拉取。
NEW_IMG_ID="none"
if timeout 900 docker pull "$GHCR_IMG" >/dev/null 2>&1; then
  NEW_IMG_ID="$(docker image inspect "$GHCR_IMG" --format '{{.Id}}' 2>/dev/null || echo none)"
else
  echo "⚠️ docker pull $GHCR_IMG 失败/超时，使用本地已有镜像" >&2
fi

# 3. 变化检测（2026-09-13 修复 P0：**状态文件不是事实来源，实际运行态才是**）
#   旧版只比 (状态文件 head, 状态文件 img) —— 手动回滚/半途失败后状态文件不变 →
#   误判「无变化」→ 静默长期跑旧版（rollback drill 实测，见 runbook §4.2）。
OLD_HEAD=""; OLD_IMG_ID=""
if [ -f "$STATE_FILE" ]; then
  OLD_HEAD="$(sed -n 1p "$STATE_FILE")"
  OLD_IMG_ID="$(sed -n 2p "$STATE_FILE")"
fi

# 3.1 实际运行态对账（镜像内版本戳 + storefront 运行镜像 ID）
WEB_CONTAINER="pallastrade-dev-web-1"
SF_CONTAINER="pallastrade-dev-storefront-1"
RUNNING_HEAD="$(docker exec "$WEB_CONTAINER" cat /rails/.deployed-revision 2>/dev/null | tr -d '\r\n' || true)"
RUNNING_SF_IMG="$(docker inspect --format '{{.Image}}' "$SF_CONTAINER" 2>/dev/null || true)"

DEPLOY_REASON=""
add_reason() {
  if [ -n "$DEPLOY_REASON" ]; then DEPLOY_REASON="$DEPLOY_REASON; $1"; else DEPLOY_REASON="$1"; fi
}

if [ "$NEW_HEAD" != "$OLD_HEAD" ]; then
  add_reason "代码更新 ${OLD_HEAD:0:8}→${NEW_HEAD:0:8}"
fi
if [ "$NEW_IMG_ID" != "$OLD_IMG_ID" ]; then
  add_reason "storefront 镜像更新 ${OLD_IMG_ID:0:12}→${NEW_IMG_ID:0:12}"
fi
# 前滚保证：运行态与期望不一致（含首次上线无戳 / 手动回滚 / 构建半途失败）必须部署
if [ "$RUNNING_HEAD" != "$NEW_HEAD" ]; then
  add_reason "运行态≠期望（运行=${RUNNING_HEAD:-未知} 期望=${NEW_HEAD:0:8}）"
fi
if [ "$NEW_IMG_ID" != "none" ] && [ -n "$RUNNING_SF_IMG" ] && [ "$RUNNING_SF_IMG" != "$NEW_IMG_ID" ]; then
  add_reason "storefront 运行镜像陈旧"
fi

if [ -z "$DEPLOY_REASON" ]; then
  echo "✅ 无变化（head=${NEW_HEAD:0:8} img=${NEW_IMG_ID:0:12}，运行态已一致），跳过部署"
  exit 0
fi

echo "🔔 需要部署：$DEPLOY_REASON"

# 4. 部署（整体 15 分钟超时，防 deploy.sh 内部卡死）
git reset --hard "origin/$BRANCH"
if [ "$NEW_IMG_ID" != "none" ]; then
  docker tag "$GHCR_IMG" "$SF_IMG"
fi
timeout 900 env DEPLOY_REVISION="$NEW_HEAD" bash deploy/deploy.sh "$ENV" || echo "⚠️ deploy.sh 超时/失败（exit=$?），状态可能未完成" >&2

# 4.1 nginx 权威配置同步（仓库版本化）+ 路由归属 smoke test（2026-09-06 根治：
#     /api/v3 → Rails、其余 /api → Next BFF。失败则不记录状态，下轮 cron 重试）
if ! timeout 120 bash deploy/nginx/sync-and-smoke.sh "$ENV"; then
  echo "❌ nginx 同步/smoke 失败，不记录状态（下轮自动重试）" >&2
  exit 1
fi

# 5. 记录状态
mkdir -p "$(dirname "$STATE_FILE")"
printf '%s\n%s\n' "$NEW_HEAD" "$NEW_IMG_ID" > "$STATE_FILE"
echo "✅ 部署完成，状态已记录"
