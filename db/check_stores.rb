puts "=== All Stores ==="
PallasTrade::Store.all.each do |s|
  puts "id=#{s.id}, name=#{s.name}, code=#{s.code}, url=#{s.url}, default=#{s.default?}"
end
puts ""
puts "=== Store URL resolution ==="
# Simulate what the store finder would do
finder = PallasTrade.current_store_finder
if finder
  result = finder.new(url: 'localhost:3000').execute
  if result
    puts "Found store for 'localhost:3000': id=#{result.id}, name=#{result.name}"
  else
    puts "No store found for 'localhost:3000'"
  end
  result = finder.new(url: 'localhost').execute
  if result
    puts "Found store for 'localhost': id=#{result.id}, name=#{result.name}"
  else
    puts "No store found for 'localhost'"
  end
end
