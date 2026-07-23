import { createAdminClient } from '@pallastrade/admin-sdk'

const client = createAdminClient({
  baseUrl: 'https://your-store.com',
  secretKey: 'sk_xxx',
})

// region:example
const paymentMethod = await client.paymentMethods.get('pm_UkLWZg9DAJ')

// endregion:example

export { paymentMethod }
