# frozen_string_literal: true

# Create default store
store = PallasTrade::Store.find_or_create_by!(code: 'pallastrade') do |s|
  s.name = 'PallasTrade'
  s.url = 'localhost:3000'
  s.mail_from_address = 'hello@example.com'
  s.default_currency = 'USD'
  s.customer_support_email = 'support@example.com'
end
puts "Store: #{store.name} (id=#{store.id})"

# Check counts
puts "Stores: #{PallasTrade::Store.count}"
puts "Products: #{PallasTrade::Product.count}"
puts "Taxons: #{PallasTrade::Taxon.count}"
puts "Taxonomies: #{PallasTrade::Taxonomy.count}"
puts "DONE"
