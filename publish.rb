store = PallasTrade::Store.default
channel = store.channels.default.first || store.channels.create!(name: 'Online Store', code: 'online', default: true)
count = 0
PallasTrade::Product.find_each do |p|
  unless p.channels.include?(channel)
    p.channels << channel
    count += 1
  end
end
puts "Published #{count} products to '#{channel.name}'"
