#!/usr/bin/env bash
# 原子同步 nginx 权威配置（仓库版本化） + 路由归属 smoke test。
#
#   bash deploy/nginx/sync-and-smoke.sh dev
#
# 由 deploy/pull-deploy.sh 在容器部署成功后自动调用（仅服务器；本机无 nginx 时跳过）。
# 根治目标（2026-09-06 bugfix）：
#   * nginx 配置纳入代码仓库，服务器不再手工编辑（防漂移）；
#   * 每次部署校验路由归属：/api/checkout/* → Next、/api/v3/* → Rails，
#     防止未来新增 Next BFF 路由 / 新 Rails namespace 时被错误转发。
set -euo pipefail

ENV="${1:-dev}"
if [ "$ENV" != "dev" ]; then
  echo "用法: sync-and-smoke.sh dev   （仅支持 dev）" >&2
  exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONF="$REPO_DIR/deploy/nginx/dev.pallastrade.cn.conf"
SITES="/etc/nginx/sites-enabled"
INSTALLED="$SITES/dev.pallastrade.cn"
DOMAIN="https://dev.pallastrade.cn"
TMP_BODY="/tmp/pallastrade-smoke-body"

echo "=== nginx sync+smoke ($ENV) $(date '+%F %T') ==="

# 非服务器主机（无 nginx）→ 跳过安装与 smoke，不阻塞本地/CI
if [ ! -d "$SITES" ] || ! command -v nginx >/dev/null 2>&1; then
  echo "ℹ️ 本机无 nginx（$SITES 不存在或 nginx 未安装）——跳过（仅服务器执行）"
  exit 0
fi

# ── 1) 与仓库权威配置 diff；不一致才原子安装 ────────────────────────
if ! cmp -s "$CONF" "$INSTALLED"; then
  BACKUP="${INSTALLED}.bak-$(date +%Y%m%d%H%M%S)"
  echo "🔧 检测到漂移，同步 $CONF → $INSTALLED"
  cp "$INSTALLED" "$BACKUP" 2>/dev/null || true
  cp "$CONF" "$INSTALLED"
  if ! nginx -t; then
    echo "❌ nginx -t 失败，回滚到备份 $BACKUP" >&2
    cp "$BACKUP" "$INSTALLED" 2>/dev/null || true
    nginx -t >/dev/null 2>&1 || true
    exit 1
  fi
  if ! systemctl reload nginx 2>/dev/null && ! nginx -s reload 2>/dev/null; then
    echo "❌ nginx reload 失败" >&2
    exit 1
  fi
  echo "✅ nginx 已 reload（新配置生效）"
else
  echo "ℹ️ nginx 配置与仓库一致，无需同步"
fi

# ── 2) 路由归属 smoke test ─────────────────────────────────────────
fail=0

expect() { # name expected_code <curl args...>
  local name="$1" expected="$2"
  shift 2
  local code
  code="$(curl -s --noproxy '*' -o "$TMP_BODY" -w '%{http_code}' "$@")" || code=000
  if [ "$code" = "$expected" ]; then
    echo "✅ PASS  $name (HTTP $code)"
  else
    echo "❌ FAIL  $name (期望 HTTP $expected，实际 $code)"; fail=1
  fi
  echo "    body: $(head -c 200 "$TMP_BODY" 2>/dev/null | tr '\n' ' ')"
}

# Next BFF 命中：/api/checkout/start（同源 POST {} → 400 Invalid checkout request，而非 Rails route_not_found 404）
expect "checkout/start → Next (400 非 404)" 400 \
  -X POST "$DOMAIN/api/checkout/start" \
  -H "Origin: $DOMAIN" -H "Content-Type: application/json" -d '{}'
if grep -q "Invalid checkout request" "$TMP_BODY" && ! grep -q "route_not_found" "$TMP_BODY"; then
  echo "✅ PASS  checkout/start body = Next BFF 错误契约"
else
  echo "❌ FAIL  checkout/start body 未命中 Next（应含 Invalid checkout request 且无 route_not_found）"; fail=1
fi

# Next webhook 命中：/api/webhooks/pallastrade（Next 处理 503/401/400 皆可；
# 只要不是 Rails 的 route_not_found 404 即证明路由归属正确）
wh_code="$(curl -s --noproxy '*' -o "$TMP_BODY" -w '%{http_code}' \
  -X POST "$DOMAIN/api/webhooks/pallastrade" -H "Content-Type: application/json" -d '{}')" || wh_code=000
if [ "$wh_code" != "404" ] && ! grep -q "route_not_found" "$TMP_BODY"; then
  echo "✅ PASS  webhooks/pallastrade → Next (HTTP $wh_code，未被 Rails 拦截)"
else
  echo "❌ FAIL  webhooks/pallastrade 被 Rails route_not_found 拦截（应命中 Next）"; fail=1
fi

# Rails API 命中：/api/v3/store/products（无 key → Rails 401 invalid_token；若误发 Next 会 404）
expect "/api/v3/store/products → Rails (401)" 401 \
  "$DOMAIN/api/v3/store/products"
if grep -q "invalid_token\|Valid API key" "$TMP_BODY"; then
  echo "✅ PASS  /api/v3 body = Rails error envelope"
else
  echo "❌ FAIL  /api/v3 未命中 Rails（应含 invalid_token / Valid API key）"; fail=1
fi

# 页面可达
expect "storefront 页面 /us/en (200)" 200 "$DOMAIN/us/en"

if [ "$fail" -ne 0 ]; then
  echo "❌ nginx 路由归属 smoke test 未通过 —— 请检查 deploy/nginx/dev.pallastrade.cn.conf" >&2
  exit 1
fi
echo "✅ nginx sync+smoke 全部通过"
