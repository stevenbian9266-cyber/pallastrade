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
docker compose -f "$COMPOSE" --env-file "$ENVFILE" up -d --build
echo "=== 容器状态 ==="
docker compose -f "$COMPOSE" ps
echo "=== 健康检查（等 30s）==="
sleep 30
if [ "$ENV" = "main" ] || [ "$ENV" = "prod" ]; then
  curl -sf http://127.0.0.1:3100/up && echo "✅ prod backend OK" || echo "⚠️ prod backend 未就绪"
else
  curl -sf http://127.0.0.1:3102/up && echo "✅ dev backend OK" || echo "⚠️ dev backend 未就绪"
fi
