# PallasTrade Backend — Agent Guidance

See [CLAUDE.md](./CLAUDE.md) for full project conventions.

## Governance Documents

| Document | Purpose |
|----------|---------|
| `../AGENTS.md` | Root agent instructions — single source of truth (contains §0 file navigation map) |
| `./CLAUDE.md` | Backend conventions (Rails, gems, testing stack) |
| `../ai/skills/pallastrade-project/SKILL.md` | PallasTrade project conventions (flavors, command mapping) |
| `../ai/skills/pallastrade-data-model/SKILL.md` | Data model questions (Orders, Variants, Stores, Markets) |
| `../ai/skills/pallastrade-testing/SKILL.md` | RSpec + Factory Bot + Capybara conventions |
| `../ai/skills/pallastrade-resource/SKILL.md` | Model/API resource generators |

## Quick Verification

```sh
cd backend && docker compose -f docker-compose.dev.yml exec web bundle exec rspec
```
