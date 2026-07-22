PallasTrade::Channel.all.each do |c|
  puts "id=#{c.id}, name=#{c.name}, store_id=#{c.store_id}"
end
puts "---"
s = PallasTrade::Store.find(4)
dc = s.default_channel
puts "Default channel: #{dc&.name} (id=#{dc&.id})"
s.channels.each do |ch|
  puts "  Channel: #{ch.name} (id=#{ch.id})"
end

