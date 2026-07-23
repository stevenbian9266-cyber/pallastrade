#!/usr/bin/env bash
# PreToolUse hook for the Bash tool. Blocks destructive database commands
# that have a real chance of wiping production data if mistargeted.
#
# Reads the tool invocation JSON from stdin, returns:
#   exit 0   — allow (stderr is not shown to Claude on success)
#   exit 2   — block (Claude shows the stderr message and refuses)
#
# We're deliberately strict on commands that match well-known destructive
# patterns, and we honor an environment-based escape hatch (PALLASTRADE_HOOKS_DISABLE=1)
# so power users can opt out. False positives are a real risk — keep the
# match list small and pinned to commands that are genuinely scary.

set -euo pipefail

# Escape hatch — set in CI or for advanced users.
if [[ "${PALLASTRADE_HOOKS_DISABLE:-}" == "1" ]]; then
  exit 0
fi

# Read the tool input. Format: { "tool_name": "Bash", "tool_input": { "command": "..." } }
input="$(cat)"
command="$(echo "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[[ -z "$command" ]] && command="$(echo "$input" | sed -n 's/.*"command":[[:space:]]*"\([^"]*\)".*/\1/p')"

# No command extracted? Don't block; fall through.
[[ -z "$command" ]] && exit 0

# Patterns we consider unambiguously destructive in a PallasTrade project context.
# Each entry is a regex (extended). Order doesn't matter; first match blocks.
patterns=(
  # Database-level drops and resets
  # Anchored to a command position (line start, separator, subshell open, or
  # JSON-escaped newline) so quoted mentions — rg 'rake db:reset',
  # git commit -m '... rails db:drop' — don't trip the hook.
  '(^|[;&|`][[:space:]]*|\\n[[:space:]]*|\$\([[:space:]]*)([[:alnum:]_/.=-]+[[:space:]]+)*(bin/)?(rake|rails)[[:space:]]+db:(drop|reset)'
  'pallastrade[[:space:]]+db:reset[[:space:]]+.*--yes'

  # Raw SQL drops against PallasTrade tables
  'DROP[[:space:]]+TABLE.*pallastrade_'
  'DROP[[:space:]]+DATABASE'
  'TRUNCATE.*pallastrade_orders'
  'TRUNCATE.*pallastrade_payments'
  'TRUNCATE.*pallastrade_users'

  # Mass deletes against critical PallasTrade tables (raw SQL through CLI). No
  # trailing-semicolon anchor — `DELETE FROM pallastrade_orders` is destructive
  # whether or not it's terminated; semicolon-anchoring would let unwrapped
  # SQL through.
  'DELETE[[:space:]]+FROM[[:space:]]+pallastrade_orders([[:space:]]|$)'
  'DELETE[[:space:]]+FROM[[:space:]]+pallastrade_payments([[:space:]]|$)'
  'DELETE[[:space:]]+FROM[[:space:]]+pallastrade_users([[:space:]]|$)'

  # ActiveRecord mass deletes via runner / console
  'PallasTrade::Order\.delete_all'
  'PallasTrade::Order\.destroy_all'
  'PallasTrade::User\.delete_all'
  'PallasTrade::Payment\.delete_all'

  # Force-pushes to main/master. Match both flag orderings (`--force …
  # main` and `… main --force`) by checking the components independently
  # rather than anchoring on their order.
  'git[[:space:]]+push[[:space:]]+.*--force.*[[:space:]](main|master)([[:space:]]|$)'
  'git[[:space:]]+push[[:space:]]+.*[[:space:]](main|master)([[:space:]].*)?--force'
  'git[[:space:]]+push[[:space:]]+.*-f[[:space:]].*(main|master)([[:space:]]|$)'
  'git[[:space:]]+push[[:space:]]+.*[[:space:]](main|master)([[:space:]].*)?[[:space:]]-f([[:space:]]|$)'
)

for pattern in "${patterns[@]}"; do
  if echo "$command" | grep -qE "$pattern"; then
    cat <<EOF >&2
🛑 PallasTrade safety hook blocked this command:

  $command

Pattern matched: $pattern

This looks like a destructive operation against PallasTrade data. If this is
intentional (you really want to drop the database / wipe orders), set
PALLASTRADE_HOOKS_DISABLE=1 in your environment and re-run, OR run the command
yourself outside Claude's tool invocation.
EOF
    exit 2
  fi
done

exit 0
