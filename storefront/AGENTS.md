# PallasTrade Storefront — Agent Guidance

See [CLAUDE.md](./CLAUDE.md) for full project conventions.

## Governance Documents

| Document | Purpose |
|----------|---------|
| `../AGENTS.md` | Root agent instructions — single source of truth for all components |

## Quick Verification

```sh
npm run check          # Biome format + lint
npx tsc --noEmit       # TypeScript typecheck
npm test               # Vitest (111 tests)
npm run build          # Production build
```
