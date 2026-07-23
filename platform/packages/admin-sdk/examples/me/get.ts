import { createAdminClient } from '@pallastrade/admin-sdk'

const client = createAdminClient({
  baseUrl: 'https://your-store.com',
  secretKey: 'sk_xxx',
})

// region:example
const me = await client.me.get()
if (
  me.permissions.some(
    (r) => r.allow && r.actions.includes('manage') && r.subjects.includes('PallasTrade::Product'),
  )
) {
  // show "Create product" button
}

// endregion:example

export { me }
