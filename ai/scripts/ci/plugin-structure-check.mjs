import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs'
import { dirname, extname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..')
const failures = []

function readJson(path) {
  try {
    return JSON.parse(readFileSync(path, 'utf8'))
  } catch (error) {
    failures.push(`${relative(root, path)} is not valid JSON: ${error.message}`)
    return null
  }
}

function walk(directory, files = []) {
  for (const entry of readdirSync(directory)) {
    const path = join(directory, entry)
    if (statSync(path).isDirectory()) walk(path, files)
    else files.push(path)
  }
  return files
}

const expectedMetadata = {
  maintainer: 'Steven Bian',
  contactEmail: 'stevenbian9266@gmail.com',
  website: 'https://pallastrade.cn',
  repository: 'https://github.com/stevenbian9266-cyber/pallastrade',
}
const plugin = readJson(join(root, '.claude-plugin', 'plugin.json'))
const marketplace = readJson(join(root, '.claude-plugin', 'marketplace.json'))

const skillNames = readdirSync(join(root, 'skills'))
  .filter((name) => existsSync(join(root, 'skills', name, 'SKILL.md')))
  .sort()
const commandNames = readdirSync(join(root, 'commands'))
  .filter((name) => name.endsWith('.md'))
  .sort()
const agentNames = readdirSync(join(root, 'agents'))
  .filter((name) => name.endsWith('.md'))
  .sort()
const hookNames = readdirSync(join(root, 'hooks'))
  .filter((name) => name.endsWith('.sh'))
  .sort()

if (skillNames.length !== 24) {
  failures.push(`plugin must ship exactly 24 skills; found ${skillNames.length}`)
}
if (skillNames.includes('pallastrade-upgrade')) {
  failures.push('removed pallastrade-upgrade skill is still present')
}
if (JSON.stringify(commandNames) !== JSON.stringify(['audit-upgrade.md', 'doctor.md'])) {
  failures.push(`unexpected commands: ${commandNames.join(', ')}`)
}
if (JSON.stringify(agentNames) !== JSON.stringify(['pallastrade-expert.md'])) {
  failures.push(`unexpected agents: ${agentNames.join(', ')}`)
}
if (JSON.stringify(hookNames) !== JSON.stringify(['block_destructive_db.sh', 'warn_on_secrets.sh'])) {
  failures.push(`unexpected hooks: ${hookNames.join(', ')}`)
}

const readme = readFileSync(join(root, 'README.md'), 'utf8')
for (const [location, content] of [
  ['README.md', readme],
  ['.claude-plugin/plugin.json', JSON.stringify(plugin)],
  ['.claude-plugin/marketplace.json', JSON.stringify(marketplace)],
]) {
  if (!content.includes('24 skills')) {
    failures.push(`${location} does not declare the actual 24-skill count`)
  }
  if (content.includes('pallastrade-upgrade')) {
    failures.push(`${location} advertises the removed pallastrade-upgrade skill`)
  }
}

if (plugin) {
  if (plugin.author?.name !== expectedMetadata.maintainer) failures.push('plugin author must match canonical maintainer')
  if (plugin.author?.email !== expectedMetadata.contactEmail) failures.push('plugin author email must match canonical contact')
  if (plugin.author?.url !== expectedMetadata.website) failures.push('plugin author URL must match canonical website')
  if (plugin.homepage !== expectedMetadata.website) failures.push('plugin homepage must match canonical website')
  if (plugin.repository !== expectedMetadata.repository) failures.push('plugin repository must match canonical repository')
}
if (marketplace) {
  if (marketplace.owner?.name !== expectedMetadata.maintainer) failures.push('marketplace owner must match canonical maintainer')
  if (marketplace.owner?.email !== expectedMetadata.contactEmail) failures.push('marketplace owner email must match canonical contact')
  if (marketplace.owner?.url !== expectedMetadata.website) failures.push('marketplace owner URL must match canonical website')
}

const legacyBrandDomain = ['pallastradecommerce', 'org'].join('\\.')
const legacyDevDomain = ['pallastrade', 'dev'].join('\\.')
const legacyRepositoryOwner = ['github', 'com', 'pallastrade'].join('\\.')
const legacySkillsCoordinate = ['pallastrade', 'agent-skills'].join('\\/')

const bannedPatterns = [
  ['removed pallastrade-upgrade skill', /\bpallastrade-upgrade\b/],
  ['legacy PallasTrade domain', new RegExp(`(?:[a-z0-9-]+\\.)*${legacyBrandDomain}`, 'i')],
  ['legacy development domain', new RegExp(`(?:[a-z0-9-]+\\.)*${legacyDevDomain}`, 'i')],
  ['legacy GitHub owner', new RegExp(`${legacyRepositoryOwner}\\/`, 'i')],
  ['legacy agent-skills coordinate', new RegExp(`\\b${legacySkillsCoordinate}\\b`, 'i')],
]

const scanRoots = ['.claude-plugin', 'agents', 'commands', 'hooks', 'skills']
const textFiles = [join(root, 'README.md'), join(root, 'AGENTS.md')]
for (const scanRoot of scanRoots) {
  for (const path of walk(join(root, scanRoot))) {
    if (['.json', '.md', '.sh'].includes(extname(path))) textFiles.push(path)
  }
}

for (const path of textFiles) {
  const content = readFileSync(path, 'utf8')
  for (const [name, pattern] of bannedPatterns) {
    if (pattern.test(content)) failures.push(`${relative(root, path)} contains ${name}`)
  }
}

if (failures.length > 0) {
  console.error('AI plugin structure check failed:')
  for (const failure of failures) console.error(`- ${failure}`)
  process.exit(1)
}

console.log(
  `AI plugin structure check passed: ${skillNames.length} skills, ${commandNames.length} commands, ${agentNames.length} agent, ${hookNames.length} hooks.`,
)
