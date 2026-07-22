p = PallasTrade::Product.find_by(slug: 'semi-automatic-espresso-machine')
puts "meta_title: #{p.meta_title.inspect}"
puts "meta_description: #{p.meta_description.inspect}"
puts "---"
# Check a few more
PallasTrade::Product.limit(3).each do |pr|
  puts "#{pr.name}: #{pr.meta_title.inspect}"
end
