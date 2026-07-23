import fs from 'node:fs'
import path from 'node:path'
import * as p from '@clack/prompts'
import type { Command } from 'commander'
import { execa } from 'execa'
import pc from 'picocolors'
import { detectProject, hasMonorepoPallasTradePath } from '../context.js'
import { dockerComposeExec, isServiceRunning } from '../docker.js'

// Sequences bundle update + db:migrate + pallastrade:upgrade rake. Flags map
// to env vars on the inner rake task: --plan → DRY_RUN, --step → STEP,
// --to → TO. --plan and --step skip the bundle + migrate pre-steps.
export function registerUpgradeCommand(program: Command): void {
  program
    .command('upgrade')
    .description(
      'Walk through a PallasTrade version upgrade (bundle + migrate + pallastrade:upgrade)',
    )
    .option('--plan', 'print the plan via pallastrade:upgrade DRY_RUN=1; skip bundle + migrate')
    .option('--step <id>', 'run a single rake step by id (skips bundle + migrate)')
    .option(
      '--to <version>',
      'explicit target version (auto-detected from installed gem otherwise)',
    )
    .option('--yes', 'skip prompts on automated steps')
    .action(async (flags: { plan?: boolean; step?: string; to?: string; yes?: boolean }) => {
      const ctx = detectProject()
      await assertUpgradeable(ctx.projectDir)

      const skipUniversal = Boolean(flags.plan || flags.step)

      if (!skipUniversal) {
        await runBundleUpdate(ctx.projectDir, flags)
        await runMigrate(ctx.projectDir, flags)
      }

      await runRakeUpgrade(ctx.projectDir, flags)

      if (!flags.plan) printPostUpgradeReminder(ctx.projectDir)
    })
}

// Upgrade migrates the DB and runs pallastrade:upgrade rake against the project's
// REAL Postgres + warm bundle_cache. Unlike `pallastrade bundle`, a one-off
// `compose run` is wrong here (it would migrate an ephemeral DB), so we refuse
// rather than fall back. Shared cheap pre-checks: monorepo-edge + web running.
async function assertUpgradeable(projectDir: string): Promise<void> {
  const refuse = (lines: string[]): never => {
    p.cancel(lines.join('\n'))
    process.exit(1)
  }

  if (hasMonorepoPallasTradePath(projectDir)) {
    refuse([
      'This is a monorepo edge project (PALLASTRADE_PATH set in .env).',
      `Run the upgrade from the monorepo root with ${pc.bold('pnpm server:*')} — the`,
      'project-local docker-compose.yml is not the running config here.',
    ])
  }

  let running: boolean
  try {
    running = await isServiceRunning('web', projectDir)
  } catch (err) {
    // `compose ps` itself failed: broken/stale compose, daemon down, unknown
    // service. Point home instead of dumping the raw env-file error. (Backstop
    // for a stale backend/ that slipped past detectProject re-rooting.)
    return refuse([
      'Could not inspect the Docker stack from this directory.',
      `  ${pc.dim(String((err as Error).message).split('\n')[0])}`,
      '',
      `Run ${pc.bold('pallastrade upgrade')} from your project root (the directory holding the`,
      '.env with SECRET_KEY_BASE), and make sure Docker is running.',
    ])
  }

  if (!running) {
    refuse([
      'The web container is not running.',
      `Upgrade runs migrations and the ${pc.bold('pallastrade:upgrade')} rake against your live`,
      `database, so the stack must be up. Start it with ${pc.bold('pallastrade dev')}, then`,
      're-run `pallastrade upgrade`.',
    ])
  }
}

async function runBundleUpdate(projectDir: string, flags: { yes?: boolean }): Promise<void> {
  if (!flags.yes) {
    const confirmed = await p.confirm({
      message: 'Run `bundle update` to bump PallasTrade gems?',
      initialValue: true,
    })
    if (p.isCancel(confirmed)) {
      p.cancel('Upgrade aborted.')
      process.exit(0)
    }
    if (!confirmed) {
      p.log.info('Skipping `bundle update`.')
      return
    }
  }

  // Scope to pallastrade* gems to avoid surprise major bumps on unrelated deps.
  const pallastradeGems = await detectPallasTradeGems(projectDir)
  if (pallastradeGems.length === 0) {
    throw new Error(
      'No PallasTrade gems detected in Gemfile.lock. ' +
        'Confirm the project has `gem "pallastrade"` (or `pallastrade_core`/`pallastrade_admin`) in its Gemfile.',
    )
  }

  p.log.step(pc.bold(`bundle update ${pallastradeGems.join(' ')}`))
  await dockerComposeExec(['bundle', 'update', ...pallastradeGems], projectDir)
}

export async function detectPallasTradeGems(projectDir: string): Promise<string[]> {
  try {
    // No `2>/dev/null` and no `|| true`: a bundler failure (out-of-sync
    // lockfile, un-checked-out git source) must reach us as a nonzero exit
    // with stderr intact, not get laundered into an empty list that becomes
    // a misleading "No PallasTrade gems detected".
    const { stdout } = await execa(
      'docker',
      ['compose', 'exec', '-T', 'web', 'sh', '-c', "bundle list --name-only | grep '^pallastrade'"],
      { cwd: projectDir },
    )
    return stdout
      .split('\n')
      .map((line) => line.trim())
      .filter((line) => line.length > 0 && line.startsWith('pallastrade'))
  } catch (err) {
    const e = err as { exitCode?: number; stderr?: string }
    // grep exits 1 with empty stderr ⇒ bundle is fine but resolves zero pallastrade
    // gems. Return [] so the caller prints the friendly "No PallasTrade gems" message.
    if (e.exitCode === 1 && !e.stderr?.trim()) return []
    // Anything else: bundler itself errored (its stderr survives the pipe).
    // Surface it + the real next step instead of the misleading gem message.
    throw new Error(
      'Could not list gems in the web container — the bundle looks out of sync.\n' +
        'Run `pallastrade bundle install` first, then re-run `pallastrade upgrade`.' +
        (e.stderr?.trim() ? `\n\n${e.stderr.trim()}` : ''),
    )
  }
}

async function runMigrate(projectDir: string, flags: { yes?: boolean }): Promise<void> {
  if (!flags.yes) {
    const confirmed = await p.confirm({
      message: 'Install + run pending migrations?',
      initialValue: true,
    })
    if (p.isCancel(confirmed)) {
      p.cancel('Upgrade aborted.')
      process.exit(0)
    }
    if (!confirmed) {
      p.log.info('Skipping migrations.')
      return
    }
  }
  p.log.step(pc.bold('pallastrade:install:migrations + db:migrate'))
  await dockerComposeExec(['bin/rails', 'pallastrade:install:migrations', 'db:migrate'], projectDir)
}

async function runRakeUpgrade(
  projectDir: string,
  flags: { plan?: boolean; step?: string; to?: string },
): Promise<void> {
  // Flags map to env vars so prod (`STEP=channels rake pallastrade:upgrade`) and dev share the same path.
  const env: Record<string, string> = {}
  if (flags.plan) env.DRY_RUN = '1'
  if (flags.step) env.STEP = flags.step
  if (flags.to) env.TO = flags.to

  p.log.step(pc.bold('pallastrade:upgrade'))
  await dockerComposeExec(['bin/rake', 'pallastrade:upgrade'], projectDir, { env })
}

// The backend upgrade never touches frontend source — SDK bumps go through
// the consumer's own PR/CI cycle. But we can detect the conventional
// create-pallastrade-app storefront and tell the operator exactly what to bump.
export function sdkAdvisory(projectDir: string): string {
  const generic = 'Update @pallastrade/sdk in any storefront or integration consuming the API'
  const pkgPath = path.join(projectDir, 'apps', 'storefront', 'package.json')
  if (!fs.existsSync(pkgPath)) return generic
  try {
    const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf-8')) as {
      dependencies?: Record<string, string>
      devDependencies?: Record<string, string>
    }
    const declared =
      pkg.dependencies?.['@pallastrade/sdk'] ?? pkg.devDependencies?.['@pallastrade/sdk']
    if (!declared) return generic
    return `Update @pallastrade/sdk in apps/storefront (currently ${declared}) to the release matching the new PallasTrade version`
  } catch {
    return generic
  }
}

function printPostUpgradeReminder(projectDir: string): void {
  p.note(
    [
      `The manifest only ran ${pc.bold('rake-automatable')} steps.`,
      '',
      "Don't forget the manual parts from the upgrade doc:",
      `  ${pc.dim('- Schedule PallasTrade::StockReservations::ExpireJob (cron)')}`,
      `  ${pc.dim(`- ${sdkAdvisory(projectDir)}`)}`,
      `  ${pc.dim('- Review behavior changes (cart, availability, payment-method types)')}`,
      `  ${pc.dim('- Audit custom decorators against renamed APIs')}`,
      '',
      `Full checklist: ${pc.cyan('https://pallastrade.cn/docs/developer/upgrades')}`,
    ].join('\n'),
    'Next steps',
  )
}
