store = PallasTrade::Store.find(4)
puts "Store: #{store.name} (id=#{store.id})"

# Check for_store scope
scope = PallasTrade::Product.for_store(store)
puts "for_store count: #{scope.count}"

# Check available scope
available = PallasTrade::Product.for_store(store).available(Time.current, 'USD', include_preorderable: true)
puts "available count: #{available.count}"

# Check raw products
puts "Products where store_id=4: #{PallasTrade::Product.where(store_id: 4).count}"

# Check product publications for store
pubs = PallasTrade::ProductPublication.joins(:product).where(pallastrade_products: { store_id: 4 }).count
puts "Publications for store 4: #{pubs}"

# Check a sample product
p = PallasTrade::Product.where(store_id: 4).first
if p
  puts "Sample product: #{p.name}"
  puts "  available_on: #{p.available_on}"
  puts "  status: #{p.status}"
  puts "  publications count: #{p.product_publications.count}"
  puts "  store: #{p.store_id}"
end
