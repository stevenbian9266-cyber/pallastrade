import fs from 'node:fs'
import path from 'node:path'
import { execFileSync, spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..')
const components = ['backend', 'platform', 'storefront', 'ai']
const tagPattern = /^pallastrade-v\d+\.\d+\.\d+(?:-rc\.\d+)?$/

function git(...args) {
  return execFileSync('git', ['-C', root, ...args], { encoding: 'utf8' }).trim()
}

function valueAfter(flag) {
  const index = process.argv.indexOf(flag)
  return index === -1 ? undefined : process.argv[index + 1]
}

const tag = valueAfter('--tag')
if (!tagPattern.test(tag ?? '')) {
  console.error('Usage: node scripts/release/create-tag.mjs --tag pallastrade-v1.0.0[-rc.1]')
  process.exit(1)
}

if (git('branch', '--show-current') !== 'dev') {
  throw new Error('Release tags can only be created from dev.')
}
if (git('status', '--porcelain')) {
  throw new Error('Release tags require a clean working tree.')
}

for (const component of components) {
  if (!fs.statSync(path.join(root, component), { throwIfNoEntry: false })?.isDirectory()) {
    throw new Error(`Missing component directory: ${component}/`)
  }
  if (fs.existsSync(path.join(root, component, '.git'))) {
    throw new Error(`Nested Git metadata is forbidden: ${component}/.git`)
  }
  git('rev-parse', `HEAD:${component}`)
}

try {
  git('rev-parse', '--verify', `refs/tags/${tag}`)
  throw new Error(`Tag already exists and will not be moved: ${tag}`)
} catch (error) {
  if (error instanceof Error && error.message.startsWith('Tag already exists')) throw error
}

const remoteCheck = spawnSync(
  'git',
  ['-C', root, 'ls-remote', '--exit-code', '--tags', 'origin', `refs/tags/${tag}`],
  { encoding: 'utf8' },
)
if (remoteCheck.status === 0) {
  throw new Error(`Remote tag already exists and will not be moved: ${tag}`)
}
if (remoteCheck.status !== 2) {
  throw new Error(`Cannot verify remote tag state: ${remoteCheck.stderr.trim()}`)
}

git('tag', '--annotate', tag, '--message', `PallasTrade ${tag}`)
console.log(`Created immutable local tag ${tag} at ${git('rev-parse', 'HEAD')}.`)
console.log(`Push with: git push origin ${tag}`)
