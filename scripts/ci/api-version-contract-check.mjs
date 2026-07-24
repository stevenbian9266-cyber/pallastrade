import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs'
import { dirname, extname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..')
const failures = []

const removedPaths = [
  'backend/pallastrade_gems/pallastrade_legacy_api_v2',
  'backend/pallastrade_gems/pallastrade_adyen/lib/pallastrade_api_v2',
  'backend/pallastrade_gems/pallastrade_stripe/lib/pallastrade_api_v2',
  'backend/pallastrade_gems/pallastrade_paypal_checkout/lib/pallastrade_api_v2',
  'platform/payments/pallastrade_adyen/lib/pallastrade_api_v2',
  'platform/payments/pallastrade_paypal_checkout/lib/pallastrade_api_v2',
  'ai/skills/pallastrade-legacy-api-v2',
]

const forbiddenRuntimePatterns = [
  [/\/api\/v[12](?:\/|["'`\s]|$)/i, 'first-party V1/V2 API path'],
  [/PallasTrade(?:::Api)?::V2\b/, 'V2 Ruby namespace'],
  [/PallasTradeLegacyApiV2\b/, 'legacy V2 engine constant'],
  [/pallastrade_(?:legacy_)?api_v2/i, 'legacy V2 package or load path'],
  [/api_v[12]\b/i, 'V1/V2 Rails route helper or configuration key'],
  [/namespace\s+:v[12]\b/, 'V1/V2 route namespace'],
  [/path:\s*["']v[12]["']/, 'V1/V2 route scope'],
]

function walk(directory, files = []) {
  if (!existsSync(directory)) return files
  for (const entry of readdirSync(directory)) {
    const target = join(directory, entry)
    if (statSync(target).isDirectory()) walk(target, files)
    else files.push(target)
  }
  return files
}

for (const removedPath of removedPaths) {
  if (existsSync(join(root, removedPath))) {
    failures.push(`retired implementation path exists: ${removedPath}`)
  }
}

const runtimeRoots = [join(root, 'backend'), join(root, 'platform', 'payments')]
const sourceExtensions = new Set(['.rb', '.rake', '.yml', '.yaml', '.js', '.mjs', '.ts', '.tsx'])
for (const runtimeRoot of runtimeRoots) {
  for (const file of walk(runtimeRoot)) {
    if (!sourceExtensions.has(extname(file))) continue
    const runtimePath = relative(root, file).replaceAll('\\', '/')
    if (runtimePath === 'backend/spec/requests/api/version_contract_spec.rb') continue
    const content = readFileSync(file, 'utf8')
    for (const [pattern, description] of forbiddenRuntimePatterns) {
      if (pattern.test(content)) {
        failures.push(`${relative(root, file).replaceAll('\\', '/')}: ${description}`)
      }
    }
  }
}

const apiRoutesPath = join(
  root,
  'backend/pallastrade_gems/pallastrade_api/config/routes.rb',
)
const apiRoutes = readFileSync(apiRoutesPath, 'utf8')
if (!/namespace\s+:v3\b/.test(apiRoutes)) {
  failures.push('canonical API routes do not define namespace :v3')
}

for (const [clientPath, requiredBase] of [
  ['platform/packages/sdk/src/client.ts', '/api/v3/store'],
  ['platform/packages/admin-sdk/src/client.ts', '/api/v3/admin'],
]) {
  const content = readFileSync(join(root, clientPath), 'utf8')
  if (!content.includes(requiredBase)) {
    failures.push(`${clientPath} does not use ${requiredBase}`)
  }
}

if (failures.length > 0) {
  console.error('API V3 runtime contract check failed:')
  for (const failure of failures) console.error(`- ${failure}`)
  process.exit(1)
}

console.log('API V3 runtime contract check passed.')
