import { createClient } from '@pallastrade/sdk'

const client = createClient({
  baseUrl: 'https://your-store.com',
  publishableKey: '<api-key>',
})

// region:example
const locales = await client.locales.list()
// endregion:example

export { locales }
