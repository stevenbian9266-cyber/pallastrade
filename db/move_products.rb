shop = PallasTrade::Store.find(3)
pallastrade = PallasTrade::Store.find(4)

# Move all products from Shop to PallasTrade
count = 0
PallasTrade::Product.where(store_id: shop.id).find_each do |product|
  product.update_column(:store_id, pallastrade.id)
  count += 1
end
puts "Moved #{count} products to PallasTrade store"

# Move all taxonomies
tax_count = 0
PallasTrade::Taxonomy.where(store_id: shop.id).find_each do |tax|
  tax.update_column(:store_id, pallastrade.id)
  tax_count += 1
end
puts "Moved #{tax_count} taxonomies to PallasTrade store"

# Verify
puts "PallasTrade products: #{pallastrade.products.count}"
puts "Shop products: #{shop.products.count}"
