import type { Command } from 'commander'
import { detectProject } from '../context.js'
import { dockerComposeExecOrRun } from '../docker.js'

// Run bundler inside the web container. Gems install into the bundle_cache
// volume and persist across container restarts without an image rebuild.
//   pallastrade bundle add stripe
//   pallastrade bundle update pallastrade pallastrade_api
//   pallastrade bundle outdated
//
// Gemfile.lock drift crashes the containers before `exec` can reach them —
// exactly the state where bundler is needed most — so when web is down we fall
// back to a one-off `compose run` container, which mounts the same bundle_cache
// volume so gems land where the next boot expects them.
export function registerBundleCommand(program: Command): void {
  program
    .command('bundle')
    .description('Run a bundler command (`bundle …`) inside the web container')
    .argument('<args...>', 'arguments to pass to bundle')
    .allowUnknownOption(true)
    .passThroughOptions(true)
    .action(async (args: string[]) => {
      const ctx = detectProject()
      await dockerComposeExecOrRun(['bundle', ...args], ctx.projectDir, {
        edgeHint: 'the edge stack heals gem drift on boot',
      })
    })
}
