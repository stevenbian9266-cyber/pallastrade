puts "Products: #{PallasTrade::Product.count}"
puts "Available: #{PallasTrade::Product.where(status: 'active').count}"
puts "ProductPublications: #{PallasTrade::ProductPublication.count}"
PallasTrade::Store.all.each { |s| puts "Store ##{s.id}: #{s.code} | #{s.name} | #{s.url}" }
puts "Taxons: #{PallasTrade::Taxon.count}"
puts "Taxonomies: #{PallasTrade::Taxonomy.count}"
