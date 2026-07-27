# PallasTrade Platform — Agent Guidance

See [CLAUDE.md](./CLAUDE.md) for full project conventions.

## Governance Documents

| Document | Purpose |
|----------|---------|
| `../AGENTS.md` | Root agent instructions — single source of truth for all components |

## Quick Verification

```sh
pnpm install --frozen-lockfile
pnpm turbo lint typecheck test build --cache-dir=.turbo
```