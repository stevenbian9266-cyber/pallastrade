import { createAdminClient } from '@pallastrade/admin-sdk'

const client = createAdminClient({
  baseUrl: 'https://your-store.com',
  secretKey: 'sk_xxx',
})

// region:example
const optionType = await client.optionTypes.get('ot_UkLWZg9DAJ')

// endregion:example

export { optionType }
