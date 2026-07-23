#!/usr/bin/env bash
# server-build.sh — rebuild the edge dev image (`pnpm server:build`).
#
# The edge flow rewrites server/Gemfile.lock with a PATH block pointing at
# the host monorepo. The Docker image build copies that lock into a context
# where PALLASTRADE_GEMS_PATH is unset and bundler runs in frozen mode —
# so the build fails with "The list of sources changed".
#
# Fix: when the PATH block is present, regenerate a RubyGems-resolved lock
# (bundle lock in a throwaway ruby container, no .env so the Gemfile's
# PALLASTRADE_GEMS_PATH branch stays inactive) and build with that.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

LOCK="server/Gemfile.lock"

if grep -q "remote: $ROOT/pallastrade" "$LOCK" 2>/dev/null; then
  RUBY_VERSION="$(cat server/.ruby-version)"
  echo "→ Edge PATH block detected in $LOCK"
  echo "→ Regenerating a RubyGems-resolved lock for the image build (ruby:${RUBY_VERSION}-slim)"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  cp server/Gemfile server/.ruby-version "$TMP/"
  docker run --rm -v "$TMP":/rails -w /rails "ruby:${RUBY_VERSION}-slim" bundle lock
  cp "$TMP/Gemfile.lock" "$LOCK"
  echo "→ Lock regenerated. (The next \`pnpm server:dev\` boot restores the monorepo PATH lock automatically.)"
fi

echo "→ Building web + worker"
PALLASTRADE_GEMS_PATH="$ROOT" docker compose -f server/docker-compose.dev.yml -f scripts/docker-compose.edge.yml build web worker
