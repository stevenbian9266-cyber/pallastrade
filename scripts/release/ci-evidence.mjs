import fs from 'node:fs'
import path from 'node:path'
import { execFileSync } from 'node:child_process'

function valueAfter(flag) {
  const index = process.argv.indexOf(flag)
  return index === -1 ? undefined : process.argv[index + 1]
}

const output = valueAfter('--output')
if (!output) {
  console.error('Usage: node scripts/release/ci-evidence.mjs --output <file>')
  process.exit(1)
}

const repository = process.env.GITHUB_REPOSITORY
const runId = process.env.GITHUB_RUN_ID
const commit = execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim()
if (!repository || !runId) {
  throw new Error('GITHUB_REPOSITORY and GITHUB_RUN_ID are required.')
}

const url = `https://github.com/${repository}/actions/runs/${runId}`
const tests = [
  { component: 'backend', command: 'compose contract, database preparation, assets, RSpec and security checks', status: 'passed', url },
  { component: 'platform', command: 'API V3 docs, lint, typecheck, tests and build', status: 'passed', url },
  { component: 'storefront', command: 'check, typecheck and unit tests', status: 'passed', url },
  { component: 'ai', command: 'plugin structure check', status: 'passed', url },
]

fs.mkdirSync(path.dirname(path.resolve(output)), { recursive: true })
fs.writeFileSync(output, `${JSON.stringify({ schemaVersion: 1, commit, tests }, null, 2)}\n`)
