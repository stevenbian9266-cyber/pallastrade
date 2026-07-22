p = PallasTrade::Product.first
puts "First product: #{p.name}"
puts "  Taxons: #{p.taxons.pluck(:name).join(', ')}"
puts "  Status: #{p.status}"
puts "---"
puts "Root taxons: #{PallasTrade::Taxon.where(depth: 0).pluck(:name).join(', ')}"
puts "---"
taxon = PallasTrade::Taxon.find_by(name: 'Kitchen')
if taxon
  puts "Kitchen taxon products: #{taxon.products.count}"
end
# Check classifications
puts "Classifications: #{PallasTrade::Classification.count}"
puts "DONE"
