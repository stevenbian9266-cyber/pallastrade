#!/usr/bin/env bash
# R1 (2026-09-04): regenerate contract artifacts from the single source of
# truth (Rails serializers) and sync their published copies.
#
#   scripts/ci/contracts.sh            # full generation (idempotent)
#
# What it does (all idempotent — safe to run any time; `harness generated:check`
# runs this and diffs the repo snapshot to detect drift):
#   1. docker exec backend web -> bundle exec rake typelizer:generate
#      (writes backend/packages/{sdk,admin-sdk}/src/types/generated)
#   2. docker exec backend web -> bundle exec rake api:docs:schemas
#      (rewrites Typelizer-owned components.schemas in backend/public/api-docs)
#   3. Sync published copies on the host:
#      backend/packages/sdk|admin-sdk -> platform/packages/...
#      backend/public/api-docs/{store,admin}.yaml -> platform/docs/api-reference/
#
# Requires: a running backend web container (pallastrade-web-1) with the repo
# bind-mounted at /rails. Without docker this script echoes SKIP (exit 0).

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

if ! command -v docker >/dev/null 2>&1 || ! docker ps >/dev/null 2>&1; then
  echo "SKIP: backend container (docker) required for contract generation"
  exit 0
fi

CONTAINER="${PALLAS_CONTRACTS_CONTAINER:-pallastrade-web-1}"

echo "[contracts] typelizer:generate (SDK types)..."
docker exec -e ENABLE_TYPELIZER=1 "$CONTAINER" bash -lc \
  'cd /rails && bundle exec rake typelizer:generate' >/dev/null

echo "[contracts] api:docs:schemas (OpenAPI components.schemas)..."
docker exec "$CONTAINER" bash -lc \
  'cd /rails && bundle exec rake api:docs:schemas' >/dev/null

echo "[contracts] sync platform copies..."
# @pallastrade/sdk lives under platform/packages (consumed by storefront/dashboard);
# the admin SDK stays canonical at backend/packages/admin-sdk (no platform copy).
mkdir -p "platform/packages/sdk/src/types/generated"
cp -f backend/packages/sdk/src/types/generated/*.ts "platform/packages/sdk/src/types/generated/"
mkdir -p platform/docs/api-reference
cp -f backend/public/api-docs/store.yaml platform/docs/api-reference/store.yaml
cp -f backend/public/api-docs/admin.yaml platform/docs/api-reference/admin.yaml

echo "[contracts] done (idempotent)."
