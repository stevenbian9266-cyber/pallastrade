puts "Products per store:"
PallasTrade::Product.group(:store_id).count.each do |store_id, count|
  store = PallasTrade::Store.find_by(id: store_id)
  puts "  Store #{store&.name || 'N/A'} (id=#{store_id}): #{count} products"
end
puts ""
puts "Taxons per taxonomy:"
PallasTrade::Taxon.group(:taxonomy_id).count.each do |tax_id, count|
  puts "  Taxonomy #{tax_id}: #{count} taxons"
end
puts ""
store4 = PallasTrade::Store.find(4)
puts "Store 4 (PallasTrade) products: #{store4.products.count}"
store3 = PallasTrade::Store.find(3)
puts "Store 3 (Shop) products: #{store3.products.count}"
