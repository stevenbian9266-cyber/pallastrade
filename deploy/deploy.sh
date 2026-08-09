#!/usr/bin/env bash
# PallasTrade 服务器部署脚本（在 /opt/pallastrade/repo 内执行）
#   用法: bash deploy/deploy.sh dev    # 部署 dev 栈（dev.pallastrade.cn）
#         bash deploy/deploy.sh main   # 部署 prod 栈（pallastrade.cn）
set -euo pipefail

ENV="${1:-dev}"
cd "$(dirname "$0")"

case "$ENV" in
  main|prod)
    COMPOSE="docker-compose.prod.yml"
    ENVFILE=".env.prod"
    SFENV=".env.storefront.prod"
    ;;
  dev)
    COMPOSE="docker-compose.dev.yml"
    ENVFILE=".env.dev"
    SFENV=".env.storefront.dev"
    ;;
  *)
    echo "用法: deploy.sh [dev|main]" >&2
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
