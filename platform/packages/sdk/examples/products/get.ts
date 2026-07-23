import { createClient } from '@pallastrade/sdk'

const client = createClient({
  baseUrl: 'https://your-store.com',
  publishableKey: '<api-key>',
})

// region:example
const product = await client.products.get('pallastrade-tote', {
  expand: ['variants', 'media'],
})
// endregion:example

export { product }
