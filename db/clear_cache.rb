Rails.cache.clear
puts "Cache cleared"

p = PallasTrade::Product.find_by(slug: 'semi-automatic-espresso-machine')
puts "meta_title: #{p.meta_title.inspect}"
puts "meta_description: #{p.meta_description.inspect}"
puts "meta_keywords: #{p.meta_keywords.inspect}"
