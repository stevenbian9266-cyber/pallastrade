import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..')
const skippedDirectories = new Set([
  '.git',
  'node_modules',
  '.pnpm-store',
  '.turbo',
  'coverage',
  'dist',
])
const blockedExactNames = new Set([
  'LICENSE',
  'NOTICE',
  'COPYING',
  'COPYRIGHT',
  'AUTHORS',
  'CONTRIBUTORS',
  'CODE_OF_CONDUCT',
  'CLA',
])
const blockedIdentities = [
  ['blocked identity A', ['sp', 'ree'].join('')],
  ['blocked identity B', ['ven', 'do'].join('')],
  ['blocked identity C', ['up', 'stream'].join('')],
]
const blockedOriginPhrases = [
  ['adapted', 'from'].join(' '),
  ['inspired', 'by'].join(' '),
  ['forked', 'from'].join(' '),
  ['original', 'project'].join(' '),
  ['original', 'repository'].join(' '),
  ['contributor', 'covenant'].join(' '),
  ['signed', 'contributors'].join(''),
]
const textExtensions = new Set([
  '.c', '.cc', '.conf', '.cpp', '.css', '.csv', '.erb', '.gemspec', '.go', '.graphql',
  '.h', '.html', '.java', '.js', '.json', '.jsx', '.lock', '.md', '.mdx', '.mjs', '.rb',
  '.rake', '.rs', '.scss', '.sh', '.sql', '.svg', '.toml', '.ts', '.tsx', '.txt', '.xml',
  '.yaml', '.yml',
])
const textBasenames = new Set([
  '.gitignore', '.gitattributes', '.ruby-version', 'Dockerfile', 'Gemfile', 'Procfile',
])
const failures = []

function walk(directory, files = []) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    if (entry.isDirectory() && skippedDirectories.has(entry.name)) continue
    const absolute = path.join(directory, entry.name)
    if (entry.isDirectory()) walk(absolute, files)
    else if (entry.isFile()) files.push(absolute)
  }
  return files
}

function logicalBasename(file) {
  let name = path.basename(file).toUpperCase()
  while (path.extname(name)) name = path.basename(name, path.extname(name))
  return name
}

function isTextFile(file) {
  return textExtensions.has(path.extname(file).toLowerCase()) || textBasenames.has(path.basename(file))
}

function readText(file) {
  const stat = fs.statSync(file)
  if (stat.size > 20 * 1024 * 1024) return null
  const buffer = fs.readFileSync(file)
  if (buffer.includes(0)) return null
  return buffer.toString('utf8')
}

for (const file of walk(root)) {
  const relative = path.relative(root, file).replaceAll('\\', '/')
  if (blockedExactNames.has(logicalBasename(file))) {
    failures.push(`${relative}: ownership-record file is not allowed`)
  }
  if (
    relative.startsWith('legal/') ||
    relative.includes('/source-records/') ||
    relative.includes('/.github/signatures/') ||
    relative.startsWith('.agents/') ||
    relative.includes('/.agents/') ||
    relative.startsWith('.claude/skills/') ||
    relative.includes('/.claude/skills/')
  ) {
    failures.push(`${relative}: disallowed project record`)
  }
  if (!isTextFile(file)) continue

  const content = readText(file)
  if (content === null) continue
  for (const [label, identity] of blockedIdentities) {
    const pattern = new RegExp(`\\b${identity}\\b`, 'i')
    if (pattern.test(content)) failures.push(`${relative}: contains ${label}`)
  }

  const lowerContent = content.toLowerCase()
  for (const phrase of blockedOriginPhrases) {
    if (lowerContent.includes(phrase)) failures.push(relative + ': contains a disallowed origin phrase')
  }

  if (path.basename(file) === 'package.json') {
    try {
      const manifest = JSON.parse(content.replace(/^\uFEFF/, ''))
      const author = typeof manifest.author === 'string' ? manifest.author : manifest.author?.name
      if (author && !/Steven Bian|PallasTrade/i.test(author)) {
        failures.push(`${relative}: package author is not PallasTrade/Steven Bian`)
      }
    } catch (error) {
      failures.push(`${relative}: invalid package manifest: ${error.message}`)
    }
  }

  if (path.extname(file) === '.gemspec' && !content.includes('<%')) {
    for (const match of content.matchAll(/\b(?:s|spec)\.authors?\s*=\s*([^\n]+)/g)) {
      if (!/Steven Bian|PallasTrade/i.test(match[1])) {
        failures.push(`${relative}: Gem author is not PallasTrade/Steven Bian`)
      }
    }
  }
}

if (failures.length > 0) {
  console.error('PallasTrade ownership audit failed:')
  for (const failure of [...new Set(failures)].sort()) console.error(`- ${failure}`)
  process.exit(1)
}

console.log('PallasTrade ownership audit passed.')
