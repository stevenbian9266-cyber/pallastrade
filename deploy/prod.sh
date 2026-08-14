#!/usr/bin/env bash
# PallasTrade prod 栈启停脚本（2026-08-15 起 prod 部署已禁用）
#   用法: bash deploy/prod.sh down    # 停止 prod 栈（保留数据卷）
#         bash deploy/prod.sh status  # 查看 prod 栈状态
# ⚠️ up 已禁用：仅部署 dev；prod 配置保留可恢复，未来恢复需人工解除禁用
set -euo pipefail

cd "$(dirname "$0")"

ACTION="${1:-status}"
COMPOSE="docker-compose.prod.yml"
ENVFILE=".env.prod"

case "$ACTION" in
  up)
    echo "❌ prod 部署已禁用（2026-08-15 部署规则调整：仅部署 dev）。" >&2
    echo "   prod 配置/镜像/数据保留，未来如需恢复请人工解除 prod.sh 禁用逻辑。" >&2
    exit 1
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
