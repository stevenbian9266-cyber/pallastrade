store = PallasTrade::Store.find_by(code: 'pallastrade')
store.update!(default: true)
puts "Using store: #{store.name} (id=#{store.id})"

# Delete old Shop store's products to avoid conflicts
PallasTrade::Product.where(store_id: PallasTrade::Store.find_by(code: 'shop').id).delete_all
puts "Cleared Shop products"

# Reload sample data for PallasTrade store
loader = PallasTrade::SampleData::Loader.new
loader.instance_variable_set(:@store, store)
loader.call

puts "DONE"
puts "Products: #{store.products.count}"
puts "Taxonomies: #{PallasTrade::Taxonomy.where(store_id: store.id).count}"
