# create-pallastrade-app

Scaffold a new [PallasTrade Commerce](https://pallastrade.cn) project with a single command. Backend runs via Docker using pre-built images, with a full Rails app included for customization.

## Quick Start

```bash
npx create-pallastrade-app my-store
```

This will walk you through an interactive setup:

1. Include **Next.js Storefront** (default: yes)
2. Optionally load sample data (products, categories, images)
3. Optionally start Docker services immediately

## CLI Flags

For non-interactive usage:

```bash
npx create-pallastrade-app my-store --no-storefront --no-sample-data --no-start
```

| Flag | Description |
|------|-------------|
| `--no-storefront` | Skip Next.js storefront setup |
| `--no-sample-data` | Skip loading sample products |
| `--no-start` | Don't start Docker services |
| `--port <number>` | Port for the PallasTrade backend (default: `3000`) |
| `--use-npm` | Use npm as package manager |
| `--use-yarn` | Use yarn as package manager |
| `--use-pnpm` | Use pnpm as package manager |

## What You Get

```
my-store/
├── docker-compose.yml        # PallasTrade backend (prebuilt image) + Postgres + Redis
├── docker-compose.dev.yml    # Alternative: build from local backend/
├── .env                      # SECRET_KEY_BASE, PALLASTRADE_PORT
├── .gitignore
├── package.json              # @pallastrade/cli + convenience scripts
├── README.md
├── backend/                  # Full Rails app (from stevenbian9266-cyber/pallastrade)
│   ├── Gemfile
│   ├── Dockerfile
│   ├── config/
│   ├── app/
│   └── ...
└── apps/
    └── storefront/           # Next.js app (unless --no-storefront)
```

## Prerequisites

- [Node.js](https://nodejs.org/) >= 20
- [Docker](https://docs.docker.com/get-docker/) (for running the backend)

## After Setup

### Admin Dashboard

Open http://localhost:3000/admin

- Email: `pallastrade@example.com`
- Password: `pallastrade123`

### Store API

http://localhost:3000/api/v3/store

### Storefront

```bash
cd my-store/apps/storefront
npm run dev
```

Open http://localhost:3001

## Customizing the Backend

The `backend/` directory contains a full Rails application with PallasTrade installed. By default, the project uses a prebuilt Docker image. To switch to building from your local backend:

```bash
npx pallastrade eject
```

This rebuilds the Docker image from `backend/` and restarts services. You can then:

- **Add gems** to `backend/Gemfile`
- **Override models** with decorators in `backend/app/models/`
- **Add controllers** in `backend/app/controllers/`
- **Configure PallasTrade** in `backend/config/initializers/pallastrade.rb`
- **Add migrations** with `cd backend && bin/rails generate migration`

## Useful Commands

Run these from your project directory (powered by [`@pallastrade/cli`](https://www.npmjs.com/package/@pallastrade/cli)):

| Command | Description |
|---------|-------------|
| `npm run dev` | Start backend services and stream logs |
| `npm run stop` | Stop backend services |
| `npm run eject` | Switch from prebuilt image to local backend builds |
| `npm run update` | Pull latest PallasTrade image and restart |
| `npm run logs` | View backend logs |
| `npm run console` | Rails console |

You can also use the CLI directly for additional commands:

```bash
npx pallastrade user create          # Create an admin user
npx pallastrade api-key create       # Create an API key
npx pallastrade api-key list         # List API keys
```

## Learn More

- [PallasTrade Documentation](https://pallastrade.cn/docs)
