#!/usr/bin/env bash
# PallasTrade dev 回滚演练脚本（2026-09-13 建立）
#
# 目的：以 dev 栈为靶场，实测「回退到旧版本 → 健康检查 → 前滚」的可行性与真实耗时，
#       并把结论沉淀成可复用的回滚 SOP 证据（见 docs/operations/runbooks/ROLLBACK-DRILL-dev.md）。
#
# 用法（在服务器 /opt/pallastrade/repo 内执行）：
#   bash deploy/drill-rollback-dev.sh <ROLLBACK_SHA> [--dry-run]
#
# 安全保证：
#   1) 演练前备份 crontab 并临时注释 pull-deploy 行（否则 cron 每 5 分钟自动前滚，窗口太短）；
#   2) EXIT trap 无论成功/失败都：恢复 crontab → 前滚到 origin/dev → 重新记录 state 文件；
#   3) 全程日志写入 /var/log/pallastrade-drill-rollback.log，同时 tee 到 stdout；
#   4) 磁盘预检（<8G 直接拒绝执行，避免重建期间触发级联故障）。
#
# 退出码：0=演练完成且最终已前滚；2=前置条件不满足（未开始）；1=演练中途异常（trap 已前滚）
set -uo pipefail

ROLLBACK_SHA="${1:-}"
DRY_RUN="no"
[ "${2:-}" = "--dry-run" ] && DRY_RUN="yes"

REPO=/opt/pallastrade/repo
LOG=/var/log/pallastrade-drill-rollback.log
STATE=/opt/pallastrade/.pull-deploy-state-dev
CRON_BAK=/root/crontab-pre-drill.bak
WEB=pallastrade-dev-web-1
GEM=/rails/pallastrade_gems/pallastrade_core/app/services/pallastrade/disputes
MIN_FREE_KB=8388608   # 8GB

ROLLED_BACK="no"
CRON_DISABLED="no"
T0=""

step(){ echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }
fail(){ step "❌ $*"; }

restore(){
  rc=$?
  step "=== restore (trap, exit=$rc) ==="
  if [ "$CRON_DISABLED" = "yes" ] && [ -f "$CRON_BAK" ]; then
    crontab "$CRON_BAK" && step "✅ crontab 已恢复" || fail "crontab 恢复失败，请手工执行: crontab $CRON_BAK"
    # 恢复后必须验证：不允许残留 #DRILL# 标记（否则 cron 自动部署会静默停摆）
    if crontab -l | grep -q '^#DRILL#'; then
      fail "🔴 crontab 仍含 #DRILL# 标记（备份本身被污染）——请人工执行: crontab -l | sed 's|^#DRILL# ||' | crontab -"
    else
      step "✅ crontab 校验通过（无 #DRILL# 残留，pull-deploy 行已启用）"
    fi
    CRON_DISABLED="no"
  fi
  if [ "$ROLLED_BACK" = "yes" ]; then
    step "--- 前滚到 origin/dev ---"
    cd "$REPO" || { fail "cd $REPO 失败"; exit 1; }
    git fetch origin dev --quiet || fail "git fetch 失败"
    git checkout -f dev --quiet 2>/dev/null || git checkout -f -B dev origin/dev --quiet
    git reset --hard origin/dev --quiet || fail "git reset 失败"
    step "repo HEAD 已回到 $(git rev-parse --short HEAD)"
    if [ "$DRY_RUN" = "no" ]; then
      # ⚠️ 2026-09-13 首次演练实证：pull-deploy 的变化检测只看 state 文件
      #   （head + storefront digest），手工回退不会改 state → 会判定「无变化」而**跳过部署**
      #   → 必须删除 state 文件强制重部署，否则 dev 会永久停留在回退版本。
      rm -f "$STATE" && step "已删除 state 文件（强制重部署）"
      bash deploy/pull-deploy.sh dev || fail "pull-deploy 前滚失败（cron 将在 5 分钟内自动重试）"
    fi
    step "state 文件 = $(sed -n 1p "$STATE" 2>/dev/null | cut -c1-8) / $(sed -n 2p "$STATE" 2>/dev/null | cut -c1-19)"
  fi
  if [ -n "$T0" ]; then step "总耗时: $(( $(date +%s) - T0 ))s"; fi
  step "=== 演练结束 (exit=$rc) ==="
  exit $rc
}
trap restore EXIT

# ---------- 0. 前置检查 ----------
step "=== PallasTrade dev 回滚演练 $(date '+%F %T') ==="
[ -n "$ROLLBACK_SHA" ] || { fail "用法: bash deploy/drill-rollback-dev.sh <ROLLBACK_SHA> [--dry-run]"; exit 2; }
[ -d "$REPO/.git" ] || { fail "$REPO 不是 git 仓库"; exit 2; }
cd "$REPO" || exit 2
git cat-file -e "${ROLLBACK_SHA}^{commit}" 2>/dev/null || { fail "回滚目标 $ROLLBACK_SHA 不存在"; exit 2; }

AVAIL_KB="$(df -P / | awk 'NR==2 {print $4}')"
step "磁盘可用: $(( AVAIL_KB / 1024 ))MB"
if [ "$AVAIL_KB" -lt "$MIN_FREE_KB" ]; then
  step "磁盘 < 8GB，执行 builder prune"
  docker builder prune -f >/dev/null 2>&1 || true
  AVAIL_KB="$(df -P / | awk 'NR==2 {print $4}')"
fi
[ "$AVAIL_KB" -ge "$MIN_FREE_KB" ] || { fail "磁盘仍 < 8GB（$(($AVAIL_KB/1024))MB），拒绝演练以免级联故障"; exit 2; }

# ---------- 1. 基线取证 ----------
step "--- 基线 ---"
BASE_HEAD="$(git rev-parse HEAD)"; BASE_SHORT="$(git rev-parse --short HEAD)"
BASE_STATE="$(sed -n 1p "$STATE" 2>/dev/null || echo none)"
BASE_IMG="$(docker image inspect pallastrade-dev-web --format '{{.Id}}' 2>/dev/null | cut -c1-19 || echo none)"
BASE_UP="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3102/up || echo 000)"
BASE_HTTP="$(curl -s -o /dev/null -w '%{http_code}' https://dev.pallastrade.cn/up || echo 000)"
step "HEAD=$BASE_SHORT state=$(echo "$BASE_STATE" | cut -c1-8) web_image=$BASE_IMG backend/up=$BASE_UP public/up=$BASE_HTTP"
step "回滚目标: $ROLLBACK_SHA"

if [ "$DRY_RUN" = "yes" ]; then step "(--dry-run) 前置检查通过，退出"; exit 0; fi

# ---------- 2. 禁用 cron ----------
step "--- 禁用 cron pull-deploy ---"
crontab -l > "$CRON_BAK" 2>/dev/null || { fail "crontab -l 失败"; exit 2; }
# ⚠️ 2026-09-13 自查修正：备份文件必须保持**未修改原样**；禁用变换只能作用于临时副本。
#    首次演练曾用 `sed -i $CRON_BAK` + `crontab $CRON_BAK`，导致 restore 把「已禁用版」
#    当成原始 crontab 写回 —— cron 自动部署被长期停摆（dev 卡在旧 commit 数小时）。
CRON_TMP="$(mktemp)"
sed 's|^\([^#].*pull-deploy\)|#DRILL# \1|' "$CRON_BAK" > "$CRON_TMP"
crontab "$CRON_TMP" || { fail "crontab 写入失败"; exit 2; }
rm -f "$CRON_TMP"
CRON_DISABLED="yes"
step "已禁用（未修改备份 $CRON_BAK）"
if crontab -l | grep -q '^#DRILL#'; then step "✅ 禁用已生效"; else fail "禁用未生效（crontab 无 #DRILL# 标记）"; fi

# ---------- 3. 回退 ----------
T0="$(date +%s)"
step "--- 回退到 $ROLLBACK_SHA ---"
RB_START="$(date +%s)"
git checkout -f "$ROLLBACK_SHA" --quiet || { fail "git checkout 失败"; exit 1; }
ROLLED_BACK="yes"
step "repo 已切到 $(git rev-parse --short HEAD)"
bash deploy/deploy.sh dev 2>&1 | tail -20 | tee -a "$LOG"
RB_SECS=$(( $(date +%s) - RB_START ))
step "回退部署耗时: ${RB_SECS}s"

# ---------- 4. 回退态验证 ----------
step "--- 回退态验证 ---"
sleep 20
cd "$REPO/deploy" || fail "cd $REPO/deploy 失败"
docker compose -f docker-compose.dev.yml --env-file .env.dev ps 2>&1 | tee -a "$LOG"
cd "$REPO"
RB_UP="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3102/up || echo 000)"
RB_HTTP="$(curl -s -o /dev/null -w '%{http_code}' https://dev.pallastrade.cn/up || echo 000)"
RB_IMG="$(docker image inspect pallastrade-dev-web --format '{{.Id}}' 2>/dev/null | cut -c1-19 || echo none)"
RB_CODE="$(docker exec "$WEB" bash -lc "ls $GEM 2>/dev/null | tr '\n' ' '" 2>/dev/null || echo '<exec失败>')"
step "回退态: backend/up=$RB_UP public/up=$RB_HTTP web_image=$RB_IMG"
step "回退态 P7-9 工件清单: ${RB_CODE:-<空>}"
case "$RB_CODE" in
  *capture_fee.rb*) step "⚠️ P7-9 工件仍存在 —— 回退未生效或镜像未重建" ;;
  *) step "✅ P7-9 工件已随版本消失（capture_fee.rb 不在 disputes/ 目录）" ;;
esac
RUNBOOK_DIR=/tmp/drill-$RB_SECS
mkdir -p "$RUNBOOK_DIR"
{ echo "baseline_head=$BASE_SHORT"; echo "baseline_state=$(echo "$BASE_STATE" | cut -c1-19)"; echo "baseline_web_image=$BASE_IMG";
  echo "baseline_backend_up=$BASE_UP"; echo "baseline_public_up=$BASE_HTTP";
  echo "rollback_sha=$ROLLBACK_SHA"; echo "rollback_secs=$RB_SECS";
  echo "rollback_backend_up=$RB_UP"; echo "rollback_public_up=$RB_HTTP"; echo "rollback_web_image=$RB_IMG";
  echo "rollback_disputes_dir=$RB_CODE"; } > "$RUNBOOK_DIR/evidence.txt"
step "回退态证据已写入 $RUNBOOK_DIR/evidence.txt"

# ---------- 5. 前滚（由 trap 统一执行，这里显式触发以便计时） ----------
FW_START="$(date +%s)"
step "--- 前滚 ---"
git fetch origin dev --quiet
git checkout -f dev --quiet 2>/dev/null || git checkout -f -B dev origin/dev --quiet
git reset --hard origin/dev --quiet
rm -f "$STATE" && step "已删除 state 文件（强制重部署；见 §4.2）"
bash deploy/pull-deploy.sh dev 2>&1 | tail -15 | tee -a "$LOG"
ROLLED_BACK="no"
FW_SECS=$(( $(date +%s) - FW_START ))
step "前滚耗时: ${FW_SECS}s"

step "--- 前滚态验证 ---"
FW_UP="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3102/up || echo 000)"
FW_HTTP="$(curl -s -o /dev/null -w '%{http_code}' https://dev.pallastrade.cn/up || echo 000)"
FW_IMG="$(docker image inspect pallastrade-dev-web --format '{{.Id}}' 2>/dev/null | cut -c1-19 || echo none)"
FW_CODE="$(docker exec "$WEB" bash -lc "ls $GEM 2>/dev/null | tr '\n' ' '" 2>/dev/null || echo '<exec失败>')"
step "前滚态: backend/up=$FW_UP public/up=$FW_HTTP web_image=$FW_IMG"
step "前滚态 disputes/ 清单: ${FW_CODE:-<空>}"
case "$FW_CODE" in
  *capture_fee.rb*) step "✅ P7-9 工件已回归" ;;
  *) step "⚠️ P7-9 工件缺失 —— 前滚未完全生效" ;;
esac
{ echo "forward_secs=$FW_SECS"; echo "forward_backend_up=$FW_UP"; echo "forward_public_up=$FW_HTTP";
  echo "forward_web_image=$FW_IMG"; echo "forward_disputes_dir=$FW_CODE";
  echo "final_state=$(sed -n 1p "$STATE" | cut -c1-19)"; } >> "$RUNBOOK_DIR/evidence.txt"
step "完整证据: $RUNBOOK_DIR/evidence.txt"
