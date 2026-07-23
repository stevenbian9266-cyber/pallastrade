import { createAdminClient } from '@pallastrade/admin-sdk'

const client = createAdminClient({
  baseUrl: 'https://your-store.com',
  secretKey: 'sk_xxx',
})

// region:example
const { data: definitions } = await client.customFieldDefinitions.list({
  q: { resource_type_eq: 'PallasTrade::Product' },
})

// endregion:example

export { definitions }
