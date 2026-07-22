# Create a new API key properly
store = PallasTrade::Store.find_by(code: 'pallastrade') || PallasTrade::Store.first

# Delete old broken key
PallasTrade::ApiKey.delete_all
puts "Old keys deleted"

# Create new key via the model's creation method
key = store.api_keys.create!(
  name: 'Storefront',
  key_type: 'publishable'
)
puts "New key created:"
puts "  Raw token (save this!): #{key.token}"
puts "  Token prefix: #{key.token_prefix}"
puts "  Token digest (first 20 chars): #{key.token_digest&.slice(0, 20)}"
puts "  Store: #{key.store.name} (id=#{key.store_id})"
