#!/usr/bin/env bash
# PallasTrade 服务器部署脚本（在 /opt/pallastrade/repo 内执行）
#   用法: bash deploy/deploy.sh dev    # 部署 dev 栈（dev.pallastrade.cn）
# ⚠️ 2026-08-15 起仅部署 dev；prod 部署已禁用（见 README）
set -euo pipefail

ENV="${1:-dev}"
cd "$(dirname "$0")"

case "$ENV" in
  main|prod)
    echo "❌ prod 部署已禁用（2026-08-15 部署规则调整：仅部署 dev）。" >&2
    echo "   prod 配置/镜像/数据保留，未来如需恢复请人工解除 deploy.sh 禁用逻辑。" >&2
    exit 1
    ;;
  dev)
    COMPOSE="docker-compose.dev.yml"
    ENVFILE=".env.dev"
    SFENV=".env.storefront.dev"
    ;;
  *)
    echo "用法: deploy.sh dev   （prod 已禁用）" >&2
    exit 1
    ;;
esac

for f in "$ENVFILE" "$SFENV"; do
  if [ ! -f "$f" ]; then
    echo "❌ 缺少 $f —— 从 ${f}.example 复制并填写实际值" >&2
    exit 1
  fi
done

echo "=== 部署 $ENV（$COMPOSE）==="
# 单栈策略：2C/3.5G 服务器双栈同时运行会 OOM，部署前先停另一栈
if [ "$ENV" = "main" ] || [ "$ENV" = "prod" ]; then
  echo "--- 确保 dev 栈停止（单栈策略）---"
  docker compose -f docker-compose.dev.yml down 2>/dev/null || true
else
  echo "--- 确保 prod 栈停止（单栈策略）---"
  docker compose -f docker-compose.prod.yml down 2>/dev/null || true
fi

# Backend 在服务器构建（构建缓存命中时快，且不会 OOM）
docker compose -f "$COMPOSE" --env-file "$ENVFILE" build web worker
# Storefront 镜像由 CI runner / 本地构建后传输（服务器不跑 next build，避免 OOM）；
# up 时若镜像缺失 compose 会尝试构建，故先确认镜像存在
if [ "$ENV" = "main" ] || [ "$ENV" = "prod" ]; then
  SF_IMG="pallastrade-prod-storefront:latest"
else
  SF_IMG="pallastrade-dev-storefront:latest"
fi
if ! docker image inspect "$SF_IMG" >/dev/null 2>&1; then
  echo "⚠️ 未找到 storefront 镜像 $SF_IMG —— 请先构建并传输镜像" >&2
fi

# 清理残留/停止的 compose 容器（防 502：compose recreate 冲突会留下 Created 残留容器，
# 占用容器名导致后续 up 无法启动 → 全栈 502。up 前先清掉本栈的 created/exited 容器）
echo "--- 清理残留 ${ENV} 容器（防 502 复发）---"
if [ "$ENV" = "dev" ]; then
  PROJECT_PREFIX="pallastrade-dev"
else
  PROJECT_PREFIX="pallastrade-prod"
fi
docker ps -a --filter "name=${PROJECT_PREFIX}-" --filter "status=created" -q | xargs -r docker rm -f
docker ps -a --filter "name=${PROJECT_PREFIX}-" --filter "status=exited" -q | xargs -r docker rm -f

docker compose -f "$COMPOSE" --env-file "$ENVFILE" up -d
echo "=== 容器状态 ==="
docker compose -f "$COMPOSE" ps
echo "=== 健康检查（等 30s）==="
sleep 30
if [ "$ENV" = "main" ] || [ "$ENV" = "prod" ]; then
  curl -sf http://127.0.0.1:3100/up && echo "✅ prod backend OK" || echo "⚠️ prod backend 未就绪"
else
  curl -sf http://127.0.0.1:3102/up && echo "✅ dev backend OK" || echo "⚠️ dev backend 未就绪"
fi
