import type { PackageManager } from '../types.js'
import { runCommand } from '../utils.js'

export function agentsMdContent(): string {
  return `# Agent Instructions

See [CLAUDE.md](./CLAUDE.md) for full project instructions and conventions.

## PallasTrade-specific agent skills

For deeper PallasTrade-specific guidance (API conventions, the data model, event system,
testing patterns, security, deployment, the Next.js storefront, etc.), install the
official skill set:

\`\`\`bash
npx skills add stevenbian9266-cyber/pallastrade
\`\`\`

Works for Claude Code, Codex, Cursor, GitHub Copilot, Cline, Aider, Zed, Windsurf,
and 60+ other agentic CLIs. See https://github.com/stevenbian9266-cyber/pallastrade for the
full skill list.
`
}

export function rootClaudeMdContent(
  hasStorefront: boolean,
  pm: PackageManager = 'npm',
): string {
  const run = runCommand(pm)
  const lines = [
    '# PallasTrade Commerce Application',
    '',
    '## Project Structure',
    '',
    '| Directory | Description |',
    '|-----------|-------------|',
    '| `backend/` | Rails API application (PallasTrade Commerce) |',
  ]

  if (hasStorefront) {
    lines.push('| `apps/storefront/` | Next.js storefront |')
  }

  lines.push(
    '',
    '## Agent Instructions',
    '',
    '- **Backend work** (Ruby/Rails, PallasTrade models, API, database): See `backend/CLAUDE.md`',
  )

  if (hasStorefront) {
    lines.push(
      '- **Storefront work** (Next.js, React, TypeScript): See `apps/storefront/CLAUDE.md`',
    )
  }

  lines.push(
    '',
    '## PallasTrade Documentation',
    '',
    'Canonical repository: https://github.com/stevenbian9266-cyber/pallastrade',
    'Full developer docs: https://pallastrade.cn/docs (also installed locally)',
    '',
    'Full developer docs are installed locally:',
    '',
    '```',
    'node_modules/@pallastrade/docs/dist/',
    '├── developer/',
    '│   ├── core-concepts/     # Products, orders, payments, inventory, etc.',
    '│   ├── customization/     # Decorators, extensions, configuration, dependencies',
    '│   ├── admin/             # Admin panel customization',
    '│   ├── storefront/        # Storefront building guides',
    '│   ├── sdk/               # TypeScript SDK documentation',
    '│   └── tutorial/          # Step-by-step tutorials',
    '├── api-reference/',
    '│   ├── store-api/         # Store API v3 guides',
    '│   ├── admin-api/         # Admin API v3 guides',
    '│   └── store.yaml         # OpenAPI 3.0 spec (all endpoints, params, schemas)',
    '└── integrations/          # Stripe, Meilisearch, etc.',
    '```',
    '',
    'Read these files when you need PallasTrade-specific guidance.',
    '',
    '## Common Commands',
    '',
    '```bash',
    `${pm} run dev              # Start the PallasTrade API (Docker)`,
    `${pm} run stop             # Stop services`,
    `${pm} run console          # Rails console`,
    `${pm} run logs             # Backend logs`,
    `${run} pallastrade eject          # Build the API locally from backend/`,
    '```',
    '',
  )

  return lines.join('\n')
}
