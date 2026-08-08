# PallasTrade Storefront — Agent Guidance

See [CLAUDE.md](./CLAUDE.md) for full project conventions.

## Governance Documents

| Document | Purpose |
|----------|---------|
| `../AGENTS.md` | Root agent instructions — single source of truth (contains §0 file navigation map) |
| `./CLAUDE.md` | Storefront conventions (Code Style, Biome, testing) |
| `../ai/skills/pallastrade-storefront/SKILL.md` | Storefront components / pages / Style Guide |
| `../ai/skills/pallastrade-i18n/SKILL.md` | UI translations + data translations |

## Quick Verification

```sh
npm run check          # Biome format + lint
npx tsc --noEmit       # TypeScript typecheck
npm test               # Vitest (111 tests)
npm run build          # Production build
```
