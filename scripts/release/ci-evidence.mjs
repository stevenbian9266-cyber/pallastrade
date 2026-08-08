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

// Embed harness evidence (doctor / anti-patterns / affected) so every release
// manifests machine-checkable engineering state, not just test pass flags.
// evidence.mjs writes artifacts/harness-evidence/latest.json.
let harness = null
const repoRoot = path.resolve(import.meta.dirname, '..', '..')
try {
  execFileSync('node', [path.join(repoRoot, 'scripts', 'harness', 'cli.mjs'), 'evidence'], {
    cwd: repoRoot, encoding: 'utf8', stdio: 'pipe',
  })
  const latestPath = path.join(repoRoot, 'artifacts', 'harness-evidence', 'latest.json')
  if (fs.existsSync(latestPath)) {
    harness = JSON.parse(fs.readFileSync(latestPath, 'utf8')).checks
  }
} catch (e) {
  harness = { error: String(e.message) }
}

fs.mkdirSync(path.dirname(path.resolve(output)), { recursive: true })
fs.writeFileSync(output, `${JSON.stringify({ schemaVersion: 1, commit, tests, harness }, null, 2)}\n`)
