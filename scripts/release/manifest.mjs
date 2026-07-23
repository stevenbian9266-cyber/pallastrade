import fs from 'node:fs'
import path from 'node:path'
import crypto from 'node:crypto'
import { execFileSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..')
const componentNames = ['backend', 'platform', 'storefront', 'ai']
const repository = 'https://github.com/stevenbian9266-cyber/pallastrade'
const tagPattern = /^pallastrade-v\d+\.\d+\.\d+(?:-rc\.\d+)?$/

function gitText(...args) {
  return execFileSync('git', ['-C', root, ...args], {
    encoding: 'utf8',
    maxBuffer: 128 * 1024 * 1024,
  }).trim()
}

function gitBuffer(...args) {
  return execFileSync('git', ['-C', root, ...args], {
    encoding: 'buffer',
    maxBuffer: 128 * 1024 * 1024,
  })
}

function option(flag) {
  const index = process.argv.indexOf(flag)
  return index === -1 ? undefined : process.argv[index + 1]
}

function requireTag(tag) {
  if (!tagPattern.test(tag ?? '')) throw new Error(`Invalid release tag: ${tag ?? '(missing)'}`)
}

function resolveCommit(value) {
  return gitText('rev-parse', '--verify', `${value}^{commit}`)
}

function readAtCommit(commit, filePath) {
  return gitBuffer('show', `${commit}:${filePath}`).toString('utf8').replace(/^\uFEFF/, '')
}

function readJsonFile(filePath) {
  return JSON.parse(fs.readFileSync(path.resolve(filePath), 'utf8').replace(/^\uFEFF/, ''))
}

function treeEntries(commit, component) {
  const output = gitBuffer('ls-tree', '-r', '-z', '--full-tree', commit, '--', `${component}/`)
  return output
    .toString('utf8')
    .split('\0')
    .filter(Boolean)
    .map((record) => {
      const match = record.match(/^(\d+)\s+(\w+)\s+([0-9a-f]+)\t(.+)$/s)
      if (!match) throw new Error(`Cannot parse Git tree record for ${component}`)
      return { mode: match[1], type: match[2], object: match[3], path: match[4], record }
    })
}

function componentSnapshot(commit, component) {
  const entries = treeEntries(commit, component)
  if (entries.length === 0) throw new Error(`Commit ${commit} has no files under ${component}/`)
  const digest = crypto.createHash('sha256')
  for (const entry of entries) digest.update(entry.record).update('\0')
  return {
    tree: gitText('rev-parse', `${commit}:${component}`),
    sha256: digest.digest('hex'),
    files: entries.length,
  }
}

function npmPackages(commit, component, entries) {
  return entries
    .filter((entry) => entry.path.endsWith('/package.json'))
    .map((entry) => {
      let parsed
      try {
        parsed = JSON.parse(readAtCommit(commit, entry.path))
      } catch (error) {
        throw new Error(`Invalid package.json at ${entry.path}: ${error.message}`)
      }
      if (!parsed.name || !parsed.version) return null
      return { component, name: parsed.name, version: parsed.version, path: entry.path }
    })
    .filter(Boolean)
}

function gemPackages(commit, component, entries) {
  const rubyFiles = entries.filter((entry) => entry.path.endsWith('.rb'))
  return entries
    .filter((entry) => entry.path.endsWith('.gemspec') && !entry.path.includes('/templates/'))
    .map((entry) => {
      const source = readAtCommit(commit, entry.path)
      if (source.includes('<%')) return null
      const name = source.match(/\b(?:s|spec)\.name\s*=\s*(['"])([^'"]+)\1/)?.[2]
      const literalVersion = source.match(/\b(?:s|spec)\.version\s*=\s*(['"])([^'"]+)\1/)?.[2]
      let version = literalVersion

      if (!version) {
        const directory = path.posix.dirname(entry.path)
        const candidates = rubyFiles.filter((file) => file.path.startsWith(`${directory}/`))
        for (const candidate of candidates) {
          const match = readAtCommit(commit, candidate.path).match(/\bVERSION\s*=\s*(['"])([^'"]+)\1/)
          if (match) {
            version = match[2]
            break
          }
        }
      }

      if (!name || !version) throw new Error(`Cannot resolve Gem name/version from ${entry.path}`)
      return { component, name, version, path: entry.path }
    })
    .filter(Boolean)
}

function collectPackages(commit) {
  const npm = []
  const gem = []
  for (const component of componentNames) {
    const entries = treeEntries(commit, component)
    npm.push(...npmPackages(commit, component, entries))
    gem.push(...gemPackages(commit, component, entries))
  }
  const byPath = (left, right) => left.path.localeCompare(right.path, 'en')
  return { gem: gem.sort(byPath), npm: npm.sort(byPath) }
}

function validateTests(tests, commit) {
  if (!Array.isArray(tests)) throw new Error('Evidence must contain a tests array.')
  for (const component of componentNames) {
    const passed = tests.filter(
      (test) =>
        test?.component === component &&
        test.status === 'passed' &&
        typeof test.command === 'string' &&
        test.command.length > 0 &&
        typeof test.url === 'string' &&
        test.url.length > 0,
    )
    if (passed.length === 0) throw new Error(`Missing passed test evidence for ${component}.`)
  }
  if (tests.some((test) => test.status !== 'passed')) {
    throw new Error('A release manifest cannot contain non-passing test evidence.')
  }
  return tests.map(({ component, command, status, url }) => ({ component, command, status, url }))
}

function buildSnapshot(commit) {
  return {
    commitTimestamp: gitText('show', '-s', '--format=%cI', commit),
    components: Object.fromEntries(
      componentNames.map((component) => [component, componentSnapshot(commit, component)]),
    ),
    packages: collectPackages(commit),
  }
}

function assertTagCommit(tag, commit) {
  const tagCommit = resolveCommit(`refs/tags/${tag}`)
  if (tagCommit !== commit) throw new Error(`Tag ${tag} points to ${tagCommit}, not ${commit}.`)
}

function same(left, right) {
  return JSON.stringify(left) === JSON.stringify(right)
}

function createManifest() {
  const tag = option('--tag')
  const evidencePath = option('--evidence')
  const outputPath = option('--output')
  requireTag(tag)
  if (!evidencePath || !outputPath) {
    throw new Error('create requires --tag, --evidence and --output.')
  }

  const commit = resolveCommit(option('--commit') ?? `refs/tags/${tag}`)
  assertTagCommit(tag, commit)
  const evidence = readJsonFile(evidencePath)
  if (evidence.commit && evidence.commit !== commit) {
    throw new Error(`Evidence commit ${evidence.commit} does not match ${commit}.`)
  }
  const tests = validateTests(evidence.tests ?? evidence, commit)
  const snapshot = buildSnapshot(commit)
  const manifest = {
    schemaVersion: 1,
    repository,
    tag,
    commit,
    commitTimestamp: snapshot.commitTimestamp,
    components: snapshot.components,
    packages: snapshot.packages,
    tests,
  }

  const resolvedOutput = path.resolve(outputPath)
  if (fs.existsSync(resolvedOutput)) throw new Error(`Refusing to overwrite ${resolvedOutput}`)
  fs.mkdirSync(path.dirname(resolvedOutput), { recursive: true })
  fs.writeFileSync(resolvedOutput, `${JSON.stringify(manifest, null, 2)}\n`)
  console.log(`Created ${resolvedOutput}`)
}

function verifyManifest() {
  const manifestPath = option('--manifest')
  if (!manifestPath) throw new Error('verify requires --manifest.')
  const manifest = readJsonFile(manifestPath)
  if (manifest.schemaVersion !== 1) throw new Error('Unsupported manifest schemaVersion.')
  if (manifest.repository !== repository) throw new Error('Unexpected repository in manifest.')
  requireTag(manifest.tag)
  const commit = resolveCommit(manifest.commit)
  if (commit !== manifest.commit) throw new Error('Manifest commit must be a full commit ID.')
  assertTagCommit(manifest.tag, commit)
  validateTests(manifest.tests, commit)

  const snapshot = buildSnapshot(commit)
  if (manifest.commitTimestamp !== snapshot.commitTimestamp) {
    throw new Error('Commit timestamp does not match the tagged commit.')
  }
  if (!same(manifest.components, snapshot.components)) {
    throw new Error('Component checksums do not match the tagged commit.')
  }
  if (!same(manifest.packages, snapshot.packages)) {
    throw new Error('Package versions do not match the tagged commit.')
  }
  console.log(`Verified ${manifest.tag} at ${manifest.commit}.`)
}

const command = process.argv[2]
if (command === 'create') createManifest()
else if (command === 'verify') verifyManifest()
else {
  console.error('Usage: node scripts/release/manifest.mjs <create|verify> [options]')
  process.exit(1)
}
