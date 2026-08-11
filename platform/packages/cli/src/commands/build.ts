import fs from 'node:fs'
import path from 'node:path'
import * as p from '@clack/prompts'
import type { Command } from 'commander'
import { execa } from 'execa'
import pc from 'picocolors'
import { detectProject, hasMonorepoPallasTradePath, isEjectedProject } from '../context.js'
import { dockerCompose } from '../docker.js'

export function registerBuildCommand(program: Command): void {
  program
    .command('build')
    .description('Rebuild the dev image (after Dockerfile / .ruby-version changes)')
    .option('--reset-bundle', 'also wipe the bundle_cache volume to re-seed gems')
    .option('--yes', 'skip confirmation prompts (for CI)')
    .option('--production', 'build the production image instead')
    .option('--tag <tag>', 'image tag for --production (default: <project>-pallastrade:latest)')
    .action(
      async (flags: {
        resetBundle?: boolean
        yes?: boolean
        production?: boolean
        tag?: string
      }) => {
        if (flags.production) {
          await buildProductionImage(detectProject().projectDir, flags.tag)
          return
        }
        await buildDevImage(flags)
      },
    )
}

async function buildDevImage(flags: { resetBundle?: boolean; yes?: boolean }): Promise<void> {
  const ctx = detectProject()

  if (hasMonorepoPallasTradePath(ctx.projectDir)) {
    p.cancel(
      [
        'This project uses PALLASTRADE_PATH for monorepo development.',
        `Use ${pc.bold('pnpm server:build')} from the monorepo root instead of ${pc.bold('pallastrade build')}.`,
        'It builds against the edge compose overlay the running stack was started with.',
      ].join('\n'),
    )
    process.exit(1)
  }

  // Always build against the active docker-compose.yml — the same file
  // `pallastrade dev` runs. After `pallastrade eject` that contains a `build:` section
  // pointing at ./backend; before eject, it's a prebuilt-image stack and
  // there's nothing to rebuild.
  if (!isEjectedProject(ctx.projectDir)) {
    console.error(
      `\n${pc.red('Error:')} docker-compose.yml has no \`build:\` section. ` +
        `Run ${pc.bold('pallastrade eject')} first to switch to a build-from-source stack.\n`,
    )
    process.exit(1)
  }

  if (flags.resetBundle) {
    if (!flags.yes) {
      const confirmed = await p.confirm({
        message:
          'Wipe the bundle_cache volume? Any gems added via `pallastrade bundle add` since the last image build will be lost.',
        initialValue: false,
      })
      if (p.isCancel(confirmed) || !confirmed) {
        p.cancel('Build cancelled.')
        process.exit(0)
      }
    }

    const s = p.spinner()
    s.start('Wiping bundle_cache volume...')
    try {
      // `down` without -v preserves postgres/redis/meilisearch/storage volumes.
      await dockerCompose(['down'], ctx.projectDir, { stdio: 'ignore' })
      const projectName = await resolveComposeProjectName(ctx.projectDir)
      const volumeName = `${projectName}_bundle_cache`
      // Check before removal so we can report missing-volume distinctly
      // from a real failure (wrong permissions, daemon issue).
      const exists = await volumeExists(volumeName, ctx.projectDir)
      if (exists) {
        await execa('docker', ['volume', 'rm', volumeName], {
          cwd: ctx.projectDir,
          stdio: 'ignore',
        })
        s.stop('bundle_cache volume wiped.')
      } else {
        s.stop(`bundle_cache volume not present (looked for ${volumeName}).`)
      }
    } catch (error) {
      s.stop('Failed to wipe bundle_cache volume.')
      throw error
    }
  }

  console.log(`\n${pc.bold('Rebuilding dev image...')}\n`)
  await dockerCompose(['build', 'web', 'worker'], ctx.projectDir, {
    stdio: 'inherit',
  })

  p.note(
    [
      `Image rebuilt. Start the stack with ${pc.bold('pallastrade dev')}.`,
      flags.resetBundle
        ? `On next boot, gems will re-seed into a fresh ${pc.dim('bundle_cache')} volume.`
        : '',
    ]
      .filter(Boolean)
      .join('\n'),
    'Build complete',
  )
}

/**
 * What `pallastrade build --production` will run, computed without touching Docker
 * — exported for tests. `docker build backend/` with the tag, nothing more.
 */
export function planProductionBuild(
  projectDir: string,
  tag?: string,
): {
  args: string[]
  imageTag: string
} {
  const backendDir = path.join(projectDir, 'backend')
  const dockerfile = path.join(backendDir, 'Dockerfile')
  if (!fs.existsSync(dockerfile)) {
    throw new Error('No backend/Dockerfile found. Is this a create-pallastrade-app project?')
  }

  const imageTag =
    tag ??
    `${path
      .basename(projectDir)
      .toLowerCase()
      .replace(/[^a-z0-9_-]/g, '')}-pallastrade:latest`

  const args = ['build', backendDir, '-f', dockerfile, '-t', imageTag]
  return { args, imageTag }
}

/**
 * Build the production image (the Dockerfile's final stage) — the one you
 * push to a registry and run on Render/Railway/AWS/anywhere. Unlike the dev
 * flow this needs no compose file and no prior `pallastrade eject`.
 */
async function buildProductionImage(projectDir: string, tag?: string): Promise<void> {
  let plan: ReturnType<typeof planProductionBuild>
  try {
    plan = planProductionBuild(projectDir, tag)
  } catch (err) {
    console.error(`\n${pc.red('Error:')} ${err instanceof Error ? err.message : String(err)}\n`)
    process.exit(1)
  }

  console.log(`\n${pc.bold(`Building production image ${plan.imageTag}...`)}\n`)
  await execa('docker', plan.args, { cwd: projectDir, stdio: 'inherit' })

  p.note(
    [
      `Run it:   ${pc.cyan(`docker run --rm -p 3000:3000 ${plan.imageTag}`)}`,
      `Push it:  ${pc.cyan(`docker tag ${plan.imageTag} <registry>/<repo> && docker push <registry>/<repo>`)}`,
    ]
      .filter(Boolean)
      .join('\n'),
    'Production image built',
  )
}

async function resolveComposeProjectName(projectDir: string): Promise<string> {
  try {
    const { stdout } = await execa('docker', ['compose', 'config', '--format', 'json'], {
      cwd: projectDir,
    })
    const parsed = JSON.parse(stdout) as { name?: string }
    if (parsed.name) return parsed.name
  } catch {
    // Fall through to basename fallback.
  }
  return path
    .basename(projectDir)
    .toLowerCase()
    .replace(/[^a-z0-9_-]/g, '')
}

async function volumeExists(name: string, projectDir: string): Promise<boolean> {
  try {
    await execa('docker', ['volume', 'inspect', name], {
      cwd: projectDir,
      stdio: 'ignore',
    })
    return true
  } catch {
    return false
  }
}
