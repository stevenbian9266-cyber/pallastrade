#!/usr/bin/env bash
# PallasTrade storefront 单独构建部署（dev）
#   后端不变、仅 storefront 变更时的快速部署。
#
# 关键防错（复盘 2026-08-31，见 deploy/README.md 故障处理节）：
#   1. 整目录同步源码（git checkout origin/dev -- storefront/），杜绝漏同步用旧源码构建
#   2. 构建前特征校验 Dockerfile 的 COREPACK_NPM_REGISTRY（CN 网络 corepack 超时修复）
#   3. 磁盘预检 <5G 先 builder prune，仍不足则中止（防磁盘满级联挂起）
#
# 用法: bash deploy/deploy-sf.sh
set -euo pipefail

cd /opt/pallastrade/repo

# 0. 磁盘预检
MIN_FREE_KB=5242880 # 5GB
AVAIL_KB="$(df -P /opt | awk 'NR==2 {print $4}')"
if [ "$AVAIL_KB" -lt "$MIN_FREE_KB" ]; then
  echo "⚠️ 磁盘可用 ${AVAIL_KB}KB < 5GB，执行 docker builder prune -f" >&2
  docker builder prune -f || true
  AVAIL_KB="$(df -P /opt | awk 'NR==2 {print $4}')"
fi
if [ "$AVAIL_KB" -lt "$MIN_FREE_KB" ]; then
  echo "❌ 清理后磁盘仍不足 5GB，中止部署（避免构建挂起）" >&2
  exit 1
fi

# 1. 源码同步（整目录，防止漏文件用旧源码构建）
git fetch origin dev -q
git checkout origin/dev -- storefront/

# 2. 特征校验：Dockerfile 必须含 corepack 镜像修复（CN 网络缺了构建必超时）
if ! grep -q "COREPACK_NPM_REGISTRY" storefront/Dockerfile; then
  echo "❌ storefront/Dockerfile 缺少 COREPACK_NPM_REGISTRY（corepack 镜像修复），中止" >&2
  exit 1
fi
echo "✅ Dockerfile COREPACK_NPM_REGISTRY x$(grep -c COREPACK_NPM_REGISTRY storefront/Dockerfile)"

# 3. 构建 + 启动（构建约 10-30 分钟）
cd /opt/pallastrade/repo/deploy
echo "=== deploy-sf build start $(date '+%F %T') ==="
docker compose -f docker-compose.dev.yml --env-file .env.dev build storefront
docker compose -f docker-compose.dev.yml --env-file .env.dev up -d --no-deps storefront
echo "=== deploy-sf up $(date '+%F %T') ==="

# 4. 探活（200 正常；307 为 locale 重定向，也视为通过）
sleep 15
CODE="$(curl -s --noproxy '*' -o /dev/null -w '%{http_code}' http://127.0.0.1:3103/us/en || echo 000)"
echo "storefront:/us/en -> $CODE"
[ "$CODE" = "200" ] || [ "$CODE" = "307" ]
echo "=== deploy-sf DONE $(date '+%F %T') ==="
