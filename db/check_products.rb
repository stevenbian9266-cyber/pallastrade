products = PallasTrade::Product.limit(5)
products.each do |p|
  puts [p.id, p.name, p.status].join(' | ')
end
puts "---"
puts "Total: #{PallasTrade::Product.count}"
puts "Active: #{PallasTrade::Product.where(status: 'active').count}"
puts "Draft: #{PallasTrade::Product.where(status: 'draft').count}"
puts "---"
channels = PallasTrade::Channel.all
channels.each { |c| puts "Channel: #{c.name} (#{c.code})" }

store = PallasTrade::Store.first
if store
  channel = store.channels.first
  if channel
    count = PallasTrade::ProductPublication.where(channel_id: channel.id).count
    puts "Published to #{channel.name}: #{count}"
  end
end
puts "DONE"
