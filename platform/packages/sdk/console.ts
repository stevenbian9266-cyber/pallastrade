import * as repl from 'node:repl'
import { createClient, PallasTradeError } from './src'

const baseUrl = process.env.PALLASTRADE_URL || 'http://localhost:3000'
const publishableKey = process.env.PALLASTRADE_PUBLISHABLE_KEY || ''

if (!publishableKey) {
  console.log('Usage: PALLASTRADE_PUBLISHABLE_KEY=pallastrade_pk_xxx npx tsx console.ts')
  console.log(
    '       PALLASTRADE_PUBLISHABLE_KEY=pallastrade_pk_xxx PALLASTRADE_URL=https://api.mystore.com npx tsx console.ts',
  )
  console.log('')
}

const client = createClient({ baseUrl, publishableKey })

console.log('PallasTrade SDK Console')
console.log(`Connected to: ${baseUrl}`)
console.log('')
console.log('Available:')
console.log('  client              - Client instance')
console.log('  createClient        - Create new client')
console.log('')
console.log('Examples:')
console.log('  await client.products.list()')
console.log('  await client.products.get("my-product", {}, { locale: "fr" })')
console.log('  await client.categories.get("clothing/shirts", {}, { currency: "EUR" })')
console.log('')

const r = repl.start({ prompt: 'pallastrade> ', useGlobal: true })

// Make await work at top level
r.context.client = client
r.context.createClient = createClient
r.context.PallasTradeError = PallasTradeError
