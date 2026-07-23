import fs from 'node:fs'
import path from 'node:path'
import { execFileSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..')
const components = ['backend', 'platform', 'storefront', 'ai']
const expectedRemote = 'github.com/stevenbian9266-cyber/pallastrade'

function git(...args) {
  return execFileSync('git', ['-C', root, ...args], { encoding: 'utf8' }).trim()
}

const errors = []
const gitRoot = path.resolve(git('rev-parse', '--show-toplevel'))
if (gitRoot.toLowerCase() !== root.toLowerCase()) {
  errors.push(`Git root is ${gitRoot}; expected ${root}`)
}

for (const component of components) {
  const componentRoot = path.join(root, component)
  if (!fs.statSync(componentRoot, { throwIfNoEntry: false })?.isDirectory()) {
    errors.push(`Missing component directory: ${component}/`)
    continue
  }
  if (fs.existsSync(path.join(componentRoot, '.git'))) {
    errors.push(`Nested Git metadata is forbidden: ${component}/.git`)
  }
}

const branch = git('branch', '--show-current')
if (branch && branch !== 'main') {
  errors.push(`Current branch is ${branch}; expected main`)
}

let remote = ''
try {
  remote = git('remote', 'get-url', 'origin')
} catch {
  errors.push('Missing origin remote')
}
const normalizedRemote = remote.toLowerCase().replace('github.com:', 'github.com/')
if (normalizedRemote && !normalizedRemote.includes(expectedRemote)) {
  errors.push(`origin does not point to ${expectedRemote}`)
}

if (errors.length > 0) {
  for (const error of errors) console.error(`ERROR: ${error}`)
  process.exit(1)
}

console.log('Monorepo contract check passed.')
