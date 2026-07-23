import type { Command } from 'commander'
import { detectProject } from '../context.js'
import { dockerComposeExec } from '../docker.js'

// Forwarded as-is so `pallastrade generate migration AddX` hits Rails's own
// generator instead of the non-existent `pallastrade:migration`. `model` is
// intentionally absent — PallasTrade provides `pallastrade:model`.
const RAILS_BUILTIN_GENERATORS = new Set([
  'migration',
  'controller',
  'scaffold',
  'scaffold_controller',
  'mailer',
  'job',
  'channel',
  'helper',
  'resource',
  'integration_test',
  'system_test',
  'task',
  'generator',
  'benchmark',
])

export function registerGenerateCommand(program: Command): void {
  program
    .command('generate')
    .alias('g')
    .description(
      'Run a generator (PallasTrade generators auto-prefixed; Rails built-ins forwarded as-is)',
    )
    .argument('<name>', 'generator name (`model`, `model_decorator`, `migration`, …)')
    .argument('[args...]', 'arguments to pass to the generator')
    .allowUnknownOption(true)
    .passThroughOptions(true)
    .action(async (name: string, args: string[]) => {
      const ctx = detectProject()
      const generator =
        name.includes(':') || RAILS_BUILTIN_GENERATORS.has(name) ? name : `pallastrade:${name}`
      await dockerComposeExec(['bin/rails', 'g', generator, ...args], ctx.projectDir)
    })
}
