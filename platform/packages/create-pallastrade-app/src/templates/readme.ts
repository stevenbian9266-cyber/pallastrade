import { DEFAULT_ADMIN_EMAIL, DEFAULT_ADMIN_PASSWORD, STOREFRONT_PORT } from '../constants.js'
import type { PackageManager } from '../types.js'
import { globalAddCommand, runCommand } from '../utils.js'

export function readmeContent(
  name: string,
  hasStorefront: boolean,
  port: number,
  pm: PackageManager = 'npm',
): string {
  const run = runCommand(pm)
  let content = `# ${name}

A [PallasTrade](https://pallastrade.example.com) project.

## Getting Started

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/) installed and running

### Start the PallasTrade API

\`\`\`bash
cd ${name}
${run} pallastrade dev
\`\`\`

The first run completes setup automatically — it pulls the latest PallasTrade image,
seeds the database, and configures API keys.

Wait for the services to be healthy, then open:

- **Admin Dashboard:** http://localhost:${port}/admin
  - Email: \`${DEFAULT_ADMIN_EMAIL}\`
  - Password: \`${DEFAULT_ADMIN_PASSWORD}\`
- **Store API:** http://localhost:${port}/api/v3/store
`

  if (hasStorefront) {
    content += `
### Start the storefront

Dependencies are already installed during setup — just start it:

\`\`\`bash
cd apps/storefront
${pm} run dev
\`\`\`

Open http://localhost:${STOREFRONT_PORT}
`
  }

  content += `
## Customizing the PallasTrade API

The \`backend/\` directory is the PallasTrade API — a full Rails application serving the Store and Admin APIs (plus background jobs and transactional emails) that your storefront and admin talk to. By default, the project runs it from a prebuilt Docker image. To switch to building from your local copy:

\`\`\`bash
${run} pallastrade eject
\`\`\`

This rebuilds the Docker image from \`backend/\` and restarts services. You can then:

- **Customize the API** by editing the files in \`backend/\`
- **Add gems** to \`backend/Gemfile\`
- **Add new resources** with \`pallastrade generate model <name> <attributes>\`

## PallasTrade CLI

This project uses [\`@pallastrade/cli\`](https://pallastrade.example.com/docs/developer/cli/quickstart) to manage the PallasTrade API.

### Services

| Command | Description |
|---------|-------------|
| \`pallastrade dev\` | Run the app in the foreground — streams logs, Ctrl+C stops it. First run completes setup automatically |
| \`pallastrade stop\` | Stop the API services |
| \`pallastrade update\` | Pull latest PallasTrade image and restart (runs migrations automatically) |
| \`pallastrade eject\` | Switch from prebuilt image to building from \`backend/\` |
| \`pallastrade build --production\` | Build the production image |
| \`pallastrade logs\` | View web server logs |
| \`pallastrade logs worker\` | View background jobs logs |
| \`pallastrade console\` | Open Rails console |

### Data

| Command | Description |
|---------|-------------|
| \`pallastrade migrate\` | Install pending PallasTrade migrations from gems, then run them or just run your own migrations |
| \`pallastrade seed\` | Seed the database |
| \`pallastrade sample-data\` | Load sample products, categories, images |

### Users & API Keys

| Command | Description |
|---------|-------------|
| \`pallastrade user create\` | Create an admin user |
| \`pallastrade api-key create\` | Create a publishable or secret API key |
| \`pallastrade api-key list\` | List all API keys |
| \`pallastrade api-key revoke <id>\` | Revoke an API key (ID from \`api-key list\`) |

### Generators

| Command | Description |
|---------|-------------|
| \`pallastrade generate model Brand name:string slug:string:uniq\` | Generate a new database model |
| \`pallastrade generate api_resource Brand name:string slug:string:uniq\` | Generate a new PallasTrade API resource |
| \`pallastrade generate subscriber OmsOrderSync order.completed\` | Generate a new event subscriber |
| \`pallastrade generate migration AddPositionToPallasTradeBrands position:integer\` | Generate a new database migration |

### Admin API

Project setup mints a read-only secret key into \`.pallastrade/credentials.json\` (gitignored), so the Admin API client works out of the box. If you skipped the setup step, \`pallastrade api\` mints the key on first use instead:

\`\`\`bash
${run} pallastrade api get products
${run} pallastrade api get "orders?q[state_eq]=complete"
${run} pallastrade api endpoints          # list endpoints + required scopes
${run} pallastrade api status             # show resolved credentials + server reachability
\`\`\`

The pre-configured key is read-only. To write, create a scoped secret key and pass it via \`PALLASTRADE_API_KEY\`:

\`\`\`bash
${run} pallastrade api-key create --scopes write_products
PALLASTRADE_API_KEY=sk_... ${run} pallastrade api post products --data '{"name":"New product","prices":[{"currency":"USD","amount":"29.99"}]}'
\`\`\`

| Command | Description |
|---------|-------------|
| \`pallastrade api get/post/patch/delete <path>\` | Call the Admin API directly |
| \`pallastrade api endpoints\` | List Admin API endpoints with required scopes |
| \`pallastrade auth login --profile <name>\` | Save named credentials for a remote store |

> **Running \`pallastrade\` directly.** The commands above use \`${run}\` because \`@pallastrade/cli\` is a local project dependency. You can also run any of the package scripts (e.g. \`${pm} run api -- get products\`), or install the CLI globally for a bare \`pallastrade\` command:
>
> \`\`\`bash
> ${globalAddCommand(pm)} @pallastrade/cli
> pallastrade api get products
> \`\`\`

## Learn More

- [PallasTrade Documentation](https://pallastrade.cn/docs)
- [Store API Reference](https://pallastrade.cn/docs/api-reference/store-api/introduction)
- [Admin API Reference](https://pallastrade.cn/docs/api-reference/admin-api/introduction)
- [CLI Reference](https://pallastrade.cn/docs/developer/cli/quickstart)
- [PallasTrade GitHub](https://github.com/stevenbian9266-cyber/pallastrade)
`

  return content
}
