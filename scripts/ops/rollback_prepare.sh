#!/usr/bin/env bash
# PallasTrade 回滚演练准备脚本（服务器 + Linux 环境）
#   - 在实施任何带数据库迁移的升级前运行，记录可回滚依据：
#       1) backend/db/schema.rb 快照
#       2) 当前最新迁移版本（schema_migrations）
#       3) 触发数据库备份（调用 db_backup.sh）
#   - 用法: bash scripts/ops/rollback_prepare.sh [env] [container] [db]
#   - 回滚到该版本: rake db:rollback STEP=N（迁移必须可 down）；或 git checkout <commit> 后 db:rollback
set -euo pipefail

ENV="${1:-dev}"
CONTAINER="${2:-pallastrade-dev-postgres-1}"
DB="${3:-pallastrade_development}"
SNAP_DIR="${SNAP_DIR:-$PWD/backups/schema}"
LOG="$SNAP_DIR/migration-version.log"

if [ ! -f "backend/db/schema.rb" ]; then
  echo "❌ 未找到 backend/db/schema.rb，请在仓库根目录执行" >&2
  exit 1
fi

TS="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$SNAP_DIR"

echo "=== 回滚演练准备（$ENV）==="

# 1) schema.rb 快照
cp -f backend/db/schema.rb "$SNAP_DIR/schema.rb.$TS"
echo "✅ schema.rb 快照: $SNAP_DIR/schema.rb.$TS"

# 2) 当前最新迁移版本（schema_migrations 表）
VERSION="$(docker exec "$CONTAINER" psql -U postgres -d "$DB" -t -A -c "SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')"
if [ -z "$VERSION" ]; then
  echo "⚠️ 无法读取迁移版本（容器/数据库不可达？）——手动记录: docker exec $CONTAINER psql -U postgres -d $DB -c 'SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 1'"
else
  echo "✅ 当前最新迁移版本: $VERSION"
  echo "$TS $ENV $DB $VERSION" >> "$LOG"
  echo "   （已追加到 $LOG）"
fi

# 3) 触发数据库备份
echo "--- 触发数据库备份 ---"
bash "$(dirname "$0")/db_backup.sh" "$ENV" "$CONTAINER" "$DB"

echo ""
echo "=== 完成。回滚提示 ==="
echo "  迁移回滚:  docker exec $CONTAINER 所在 web 容器内  bundle exec rails db:rollback STEP=N"
echo "  代码回滚:  git checkout <上一提交> 后重建镜像部署（见 deploy/README.md）"
