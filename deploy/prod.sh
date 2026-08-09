#!/usr/bin/env bash
# PallasTrade prod 栈启停脚本
#   用法: bash deploy/prod.sh up      # 启动 prod 栈（pallastrade.cn）
#         bash deploy/prod.sh down    # 停止 prod 栈（保留数据卷，下次 up 即恢复）
#         bash deploy/prod.sh status  # 查看 prod 栈状态
set -euo pipefail

cd "$(dirname "$0")"

ACTION="${1:-status}"
COMPOSE="docker-compose.prod.yml"
ENVFILE=".env.prod"

case "$ACTION" in
  up)
    echo "=== 启动 prod 栈 ==="
    docker compose -f "$COMPOSE" --env-file "$ENVFILE" up -d
    echo "=== 健康检查（等 30s）==="
    sleep 30
    curl -sf http://127.0.0.1:3100/up && echo "✅ prod backend OK" || echo "⚠️ prod backend 未就绪"
    curl -sf http://127.0.0.1:3101/us/zh && echo "✅ prod storefront OK" || echo "⚠️ prod storefront 未就绪"
    ;;
  down)
    echo "=== 停止 prod 栈（保留数据卷）==="
    docker compose -f "$COMPOSE" down
    echo "✅ prod 栈已停止（数据保留，下次 up 即恢复）"
    ;;
  status)
    docker compose -f "$COMPOSE" ps --format 'table {{.Name}}\t{{.Status}}' 2>/dev/null | head -10 || echo "prod 栈未启动"
    ;;
  *)
    echo "用法: bash deploy/prod.sh [up|down|status]" >&2
    exit 1
    ;;
esac
