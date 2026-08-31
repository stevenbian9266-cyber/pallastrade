#!/usr/bin/env bash
# PallasTrade dev 栈启停脚本（2026-08-31 起只保留 dev 栈）
#   用法: bash deploy/dev.sh up    # 启动 dev 栈（dev.pallastrade.cn）
#         bash deploy/dev.sh down  # 停止 dev 栈（释放资源）
set -euo pipefail

cd "$(dirname "$0")"

ACTION="${1:-status}"
COMPOSE="docker-compose.dev.yml"
ENVFILE=".env.dev"

case "$ACTION" in
  up)
    echo "=== 启动 dev 栈 ==="
    docker compose -f "$COMPOSE" --env-file "$ENVFILE" up -d
    echo "=== 健康检查（等 30s）==="
    sleep 30
    curl -sf http://127.0.0.1:3102/up && echo "✅ dev backend OK" || echo "⚠️ dev backend 未就绪"
    curl -sf http://127.0.0.1:3103/us/zh && echo "✅ dev storefront OK" || echo "⚠️ dev storefront 未就绪"
    ;;
  down)
    echo "=== 停止 dev 栈（保留数据卷）==="
    docker compose -f "$COMPOSE" down
    echo "✅ dev 栈已停止（数据保留，下次 up 即恢复）"
    ;;
  status)
    docker compose -f "$COMPOSE" ps --format 'table {{.Name}}\t{{.Status}}' 2>/dev/null | head -10 || echo "dev 栈未启动"
    ;;
  *)
    echo "用法: bash deploy/dev.sh [up|down|status]" >&2
    exit 1
    ;;
esac
