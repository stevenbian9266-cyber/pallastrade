import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs'
import { dirname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..')
const docsRoot = join(repositoryRoot, 'docs')
const docsConfigPath = join(docsRoot, 'docs.json')
const migrationGuide = 'api-reference/store-api/migrating-from-storefront-api-v2.mdx'

const failures = []
const expectedOpenApi = ['api-reference/admin.yaml', 'api-reference/store.yaml']
const retiredFiles = [
  'api-reference/oauth.yml',
  'api-reference/platform.yaml',
  'api-reference/platform/authentication.mdx',
  'api-reference/storefront.yaml',
  'api-reference/storefront/authentication.mdx',
  'api-reference/tutorials/adyen-integration-guide-for-android.mdx',
  'api-reference/tutorials/adyen-integration-guide-for-ios.mdx',
  'api-reference/tutorials/quick-checkout-with-stripe.mdx',
  'api-reference/v2/fetching-multiple-resources.mdx',
  'api-reference/v2/filtering-and-sorting.mdx',
  'api-reference/v2/introduction.mdx',
  'api-reference/v2/pagination.mdx',
]

function walk(directory, files = []) {
  for (const entry of readdirSync(directory)) {
    const path = join(directory, entry)
    if (statSync(path).isDirectory()) walk(path, files)
    else files.push(path)
  }
  return files
}

let config
try {
  config = JSON.parse(readFileSync(docsConfigPath, 'utf8'))
} catch (error) {
  failures.push(`docs/docs.json is not valid JSON: ${error.message}`)
}

if (config) {
  const configuredOpenApi = [...(config.api?.openapi ?? [])].sort()
  if (JSON.stringify(configuredOpenApi) !== JSON.stringify(expectedOpenApi)) {
    failures.push(
      `docs.json api.openapi must contain only ${expectedOpenApi.join(', ')}; got ${configuredOpenApi.join(', ')}`,
    )
  }

  const navigation = JSON.stringify(config.navigation ?? [])
  for (const marker of [
    'Legacy API v2',
    'api-reference/v2/',
    'api-reference/storefront.yaml',
    'api-reference/platform.yaml',
  ]) {
    if (navigation.includes(marker)) {
      failures.push(`docs navigation still exposes retired marker: ${marker}`)
    }
  }
}

for (const retiredFile of retiredFiles) {
  if (existsSync(join(docsRoot, retiredFile))) {
    failures.push(`retired v2 documentation still exists: docs/${retiredFile}`)
  }
}

for (const path of walk(join(docsRoot, 'api-reference'))) {
  const relativePath = relative(docsRoot, path).replaceAll('\\', '/')
  if (relativePath === migrationGuide) continue

  const content = readFileSync(path, 'utf8')
  if (/\/api\/v2(?:\/|["'`\s]|$)/i.test(content)) {
    failures.push(`active API reference contains a v2 route: docs/${relativePath}`)
  }
}

for (const [spec, requiredPrefix] of [
  ['api-reference/store.yaml', '/api/v3/store'],
  ['api-reference/admin.yaml', '/api/v3/admin'],
]) {
  const path = join(docsRoot, spec)
  if (!existsSync(path)) {
    failures.push(`missing V3 OpenAPI source: docs/${spec}`)
    continue
  }

  const content = readFileSync(path, 'utf8')
  if (!/^\s*version:\s*v3\s*$/m.test(content)) {
    failures.push(`docs/${spec} must declare info.version: v3`)
  }
  if (!content.includes(requiredPrefix)) {
    failures.push(`docs/${spec} does not contain the required ${requiredPrefix} paths`)
  }
  if (/\/api\/v[12](?:\/|["'`\s]|$)/i.test(content)) {
    failures.push(`docs/${spec} contains a retired v1/v2 route`)
  }
}

if (failures.length > 0) {
  console.error('API V3 documentation policy check failed:')
  for (const failure of failures) console.error(`- ${failure}`)
  process.exit(1)
}

console.log('API V3 documentation policy check passed.')
