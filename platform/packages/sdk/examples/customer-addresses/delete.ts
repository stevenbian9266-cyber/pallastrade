import { createClient } from '@pallastrade/sdk'

const client = createClient({
  baseUrl: 'https://your-store.com',
  publishableKey: '<api-key>',
})

// region:example
await client.customer.addresses.delete('addr_abc123', {
  token: '<token>',
})
// endregion:example
