import { createClient } from '@pallastrade/sdk'

const client = createClient({
  baseUrl: 'https://your-store.com',
  publishableKey: '<api-key>',
})

// region:example
await client.auth.logout({
  refresh_token: 'rt_xxx',
})
// endregion:example
