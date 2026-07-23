import { createAdminClient } from '@pallastrade/admin-sdk'

const client = createAdminClient({
  baseUrl: 'https://your-store.com',
  secretKey: 'sk_xxx',
})

// region:example
const definition = await client.customFieldDefinitions.get('cfd_UkLWZg9DAJ')

// endregion:example

export { definition }
