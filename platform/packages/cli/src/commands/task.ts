import type { Command } from 'commander'
import { detectProject } from '../context.js'
import { dockerComposeExec } from '../docker.js'

// Shortcut for `pallastrade rake pallastrade:<name>` — most rake tasks a PallasTrade dev runs
// are in the `pallastrade:` namespace, so this saves the prefix.
//   pallastrade task search:reindex      → bin/rake pallastrade:search:reindex
//   pallastrade task channels:full_upgrade
//   pallastrade task price_history:seed
export function registerTaskCommand(program: Command): void {
  program
    .command('task')
    .description('Run a PallasTrade rake task (auto-prefixes `pallastrade:`)')
    .argument('<name>', 'task name (without `pallastrade:` prefix)')
    .argument('[args...]', 'arguments to pass to the task')
    .allowUnknownOption(true)
    .passThroughOptions(true)
    .action(async (name: string, args: string[]) => {
      const ctx = detectProject()
      await dockerComposeExec(['bin/rake', `pallastrade:${name}`, ...args], ctx.projectDir)
    })
}
