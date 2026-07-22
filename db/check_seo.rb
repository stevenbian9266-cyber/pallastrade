s = PallasTrade::Store.find(4)
puts "name: #{s.name}"
puts "seo_title: #{s.seo_title.inspect}"
puts "meta_description: #{s.meta_description.inspect}"
puts "---"
# Check product meta too
p = PallasTrade::Product.first
puts "Product: #{p.name}"
puts "Product meta_title: #{p.meta_title.inspect}"
puts "Product meta_description: #{p.meta_description.inspect}"
