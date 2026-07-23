#!/usr/bin/env bash
# Bootstrap the E2E PallasTrade backend using @pallastrade/cli.
#
# Steps:
#   1. `pallastrade seed` — seed the default store, roles, countries.
#   2. `pallastrade sample-data` — load sample products, categories, images.
#   3. `pallastrade api-key create --name E2E --type publishable` — mint a key
#      and capture the printed pk_… token.
#
# Idempotent: the CLI's seed/sample-data tasks are no-ops on already-seeded
# databases, and a fresh API key per run is fine (old "E2E" keys just
# accumulate but don't break anything).
#
# Output: writes `.env.e2e` at the repo root with PALLASTRADE_API_URL +
# PALLASTRADE_PUBLISHABLE_KEY for the storefront to consume.

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
readonly BACKEND_DIR="$REPO_ROOT/e2e-backend"
readonly ENV_FILE="$REPO_ROOT/.env.e2e"
readonly PALLASTRADE_URL="http://localhost:4000"

# Stripe test-mode API keys. Both must come from the SAME Stripe sandbox
# account — a mismatched pair makes Stripe.js fail to confirm the
# PaymentIntent during checkout. Stripe no longer publishes a working
# sample pair (the old docs sk_test_… key is expired), so use keys from
# your own Stripe sandbox:
#
#   export STRIPE_PUBLISHABLE_KEY=pk_test_…
#   export STRIPE_SECRET_KEY=sk_test_…
#   npm run e2e:up
#
# The secret key is never committed: GitHub's push protection flags any
# sk_test_ literal as a secret regardless of provenance. In CI,
# STRIPE_SECRET_KEY is a repository secret and STRIPE_PUBLISHABLE_KEY a
# repository variable, both injected via the workflow env (see
# .github/workflows/ci.yml).
if [[ -z "${STRIPE_PUBLISHABLE_KEY:-}" || -z "${STRIPE_SECRET_KEY:-}" ]]; then
  echo "STRIPE_PUBLISHABLE_KEY and STRIPE_SECRET_KEY must both be set." >&2
  echo "Use a pk_test_…/sk_test_… pair from your own Stripe sandbox." >&2
  echo "See script header for details." >&2
  exit 1
fi

# Full-shape checks (not just prefix): a stray quote, space, or other
# copy-paste artifact would otherwise flow into .env.e2e and break parsing.
if [[ ! "$STRIPE_PUBLISHABLE_KEY" =~ ^pk_test_[A-Za-z0-9_]+$ ]]; then
  echo "STRIPE_PUBLISHABLE_KEY must be a test-mode key (pk_test_…)." >&2
  echo "Got: ${STRIPE_PUBLISHABLE_KEY:0:8}…" >&2
  exit 1
fi

if [[ ! "$STRIPE_SECRET_KEY" =~ ^sk_test_[A-Za-z0-9_]+$ ]]; then
  echo "STRIPE_SECRET_KEY must be a test-mode key (sk_test_…)." >&2
  echo "Got: ${STRIPE_SECRET_KEY:0:8}…" >&2
  exit 1
fi

# @pallastrade/cli looks for docker-compose.yml in the cwd, so all CLI calls
# happen from the backend dir.
cd "$BACKEND_DIR"

# Both callers (`npm run e2e:up` and CI) already gate on the compose
# healthcheck via `up -d --wait`; this guard only covers running the
# script standalone against a still-booting stack.
echo "==> Waiting for PallasTrade to accept HTTP requests at $PALLASTRADE_URL/up"
if ! curl -fsS --retry 60 --retry-delay 2 --retry-all-errors "$PALLASTRADE_URL/up" >/dev/null 2>&1; then
  echo "PallasTrade never came up. Check 'docker compose -f $BACKEND_DIR/docker-compose.yml logs web'." >&2
  exit 1
fi

echo "==> Seeding default PallasTrade data (pallastrade seed)"
npx @pallastrade/cli seed

echo "==> Loading sample products and categories (pallastrade sample-data)"
npx @pallastrade/cli sample-data

# Vanilla PallasTrade ships without any payment gateway configured. The Admin API
# can create one declaratively, but that endpoint only exists from PallasTrade 5.5
# onward — this E2E targets the stable 5.4.3.1 image, so we fall back to a
# `bin/rails runner` snippet that creates a PallasTradeStripe::Gateway row directly.
# The script is idempotent: re-running matches the existing row by name
# (where(...).first_or_initialize) and reapplies the same attributes.
# The keys reach Ruby via the container environment (-e pass-through from
# this script's env) rather than heredoc interpolation, so the Ruby source
# never embeds them — the heredoc delimiter is quoted on purpose.
echo "==> Configuring Stripe payment gateway on the default store"
docker compose exec -T -e STRIPE_PUBLISHABLE_KEY -e STRIPE_SECRET_KEY web bin/rails runner - <<'RUBY'
store = PallasTrade::Store.default
gateway = PallasTrade::PaymentMethod.where(type: 'PallasTradeStripe::Gateway', name: 'E2E Stripe').first_or_initialize
gateway.assign_attributes(
  active: true,
  display_on: 'both',
  auto_capture: true,
  stores: [store],
  preferences: {
    publishable_key: ENV.fetch('STRIPE_PUBLISHABLE_KEY'),
    secret_key: ENV.fetch('STRIPE_SECRET_KEY')
  }
)
# validate: false skips PallasTradeStripe's validate_secret_key hook — a live
# Stripe API roundtrip at save time. The key still gets exercised for real
# when checkout creates a PaymentIntent.
gateway.save!(validate: false)
puts "OK: gateway #{gateway.id} (#{gateway.name})"
RUBY

echo "==> Creating publishable API key (pallastrade api-key create)"
api_key_output=$(npx @pallastrade/cli api-key create --name E2E --type publishable)

publishable_key=$(printf '%s\n' "$api_key_output" | grep -oE 'pk_[A-Za-z0-9_-]+' | head -n 1)
if [[ -z "$publishable_key" ]]; then
  echo "Could not extract publishable key from CLI output:" >&2
  printf '%s\n' "$api_key_output" >&2
  exit 1
fi

cat >"$ENV_FILE" <<EOF
# Generated by scripts/e2e/bootstrap-pallastrade.sh — DO NOT EDIT
PALLASTRADE_API_URL=$PALLASTRADE_URL
PALLASTRADE_PUBLISHABLE_KEY=$publishable_key
NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=$STRIPE_PUBLISHABLE_KEY
EOF

echo
echo "==> Done. Wrote $ENV_FILE"
echo "    PALLASTRADE_API_URL=$PALLASTRADE_URL"
echo "    PALLASTRADE_PUBLISHABLE_KEY=${publishable_key:0:12}…"
