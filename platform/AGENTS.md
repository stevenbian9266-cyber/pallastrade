# PallasTrade Platform — Agent Guidance

See [CLAUDE.md](./CLAUDE.md) for full project conventions.

## Governance Documents

| Document | Purpose |
|----------|---------|
| `../AGENTS.md` | Root agent instructions — single source of truth (contains §0 file navigation map) |
| `./CLAUDE.md` | Platform conventions (type generation, code style, testing) |
| `../ai/skills/pallastrade-typescript-sdk/SKILL.md` | `@pallastrade/sdk` / admin SDK conventions |
| `../ai/skills/pallastrade-cli/SKILL.md` | PallasTrade CLI conventions |

## Quick Verification

```sh
pnpm install --frozen-lockfile
pnpm turbo lint typecheck test build --cache-dir=.turbo
```