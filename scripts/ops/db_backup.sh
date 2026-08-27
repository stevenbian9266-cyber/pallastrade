#!/usr/bin/env bash
# PallasTrade 数据库备份脚本（服务器 + Linux 环境）
#   - 用法: bash scripts/ops/db_backup.sh [env] [container] [db]
#   - 默认: env=dev, container=pallastrade-dev-postgres-1, db=pallastrade_development
#   - 本地 docker（backend/docker-compose.dev.yml，项目名 pallastrade）:
#       bash scripts/ops/db_backup.sh dev pallastrade-postgres-1
#   - 定时（服务器 cron，每日 03:00）:
#       0 3 * * * cd /opt/pallastrade/repo && bash scripts/ops/db_backup.sh dev >> /var/log/pallastrade-backup.log 2>&1
set -euo pipefail

ENV="${1:-dev}"
CONTAINER="${2:-pallastrade-dev-postgres-1}"
DB="${3:-pallastrade_development}"
KEEP="${KEEP:-7}"
BACKUP_DIR="${BACKUP_DIR:-$PWD/backups}"

# 从 repo 根执行时保证相对路径正确
if [ -f "backend/db/schema.rb" ]; then
  BACKUP_DIR="${BACKUP_DIR:-$PWD/backups}"
elif [ -d "backend" ] && [ ! -f "backend/db/schema.rb" ]; then
  echo "❌ 未找到 backend/db/schema.rb，请在仓库根目录执行" >&2
  exit 1
fi

TS="$(date +%Y%m%d-%H%M%S)"
OUT="$BACKUP_DIR/${ENV}-${DB}-${TS}.sql.gz"

mkdir -p "$BACKUP_DIR"
echo "=== 备份 ${ENV}/${DB}（容器 ${CONTAINER}）→ $OUT ==="

# trust auth（compose 配置 POSTGRES_HOST_AUTH_METHOD=trust），无需密码
docker exec "$CONTAINER" pg_dump -U postgres -d "$DB" --no-owner --no-acl | gzip > "$OUT"
echo "✅ 完成: $(du -h "$OUT" | cut -f1)  $(date '+%Y-%m-%d %H:%M:%S')"

# 清理旧备份，仅保留最近 $KEEP 份
mapfile -t OLD < <(ls -1t "$BACKUP_DIR"/"${ENV}-${DB}-"*.sql.gz 2>/dev/null | tail -n +$((KEEP+1)))
if [ "${#OLD[@]}" -gt 0 ]; then
  rm -f "${OLD[@]}"
  echo "🧹 清理 ${#OLD[@]} 份旧备份（保留最近 $KEEP 份）"
fi
