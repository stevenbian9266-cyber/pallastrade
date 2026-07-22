puts "Product publications: #{PallasTrade::ProductPublication.count}"
puts "By channel:"
PallasTrade::ProductPublication.group(:channel_id).count.each do |ch_id, count|
  ch = PallasTrade::Channel.find_by(id: ch_id)
  puts "  #{ch&.name} (id=#{ch_id}): #{count}"
end
puts ""
p = PallasTrade::Product.first
puts "First product: #{p.name}"
puts "  Store: #{p.store_id}"
puts "  Publications: #{p.product_publications.count}"
puts "  Status: #{p.status}"
puts "  Available on: #{p.available_on}"
puts "  Discontinue on: #{p.discontinue_on}"
puts ""
puts "Channels per store:"
PallasTrade::Store.includes(:channels).each do |s|
  puts "  #{s.name}: #{s.channels.pluck(:name).join(', ')}"
end
