# PallasTrade Platform — Agent Guidance

See [CLAUDE.md](./CLAUDE.md) for full project conventions.

## Governance Documents

| Document | Purpose |
|----------|---------|
| `../docs/governance/rename-map.yml` | Brand rename map (PallasTrade → PallasTrade) |
| `../docs/governance/OBLIGATIONS.md` | Cross-module sync rules |
| `../docs/governance/IMPACT_MAP.md` | Module dependency matrix |
| `../docs/governance/PAYMENT_SECURITY_GATE.md` | Payment security gate (STR-001–012) |
| `../docs/adr/` | Architecture Decision Records |

## Quick Verification

```sh
pnpm install --frozen-lockfile
pnpm turbo lint typecheck test build --cache-dir=.turbo
```