puts "=== Stores ==="
PallasTrade::Store.all.each { |s| puts "  id=#{s.id}, name=#{s.name}, code=#{s.code}" }

puts ""
puts "=== API Keys ==="
PallasTrade::ApiKey.all.each do |k|
  store = k.store
  puts "  id=#{k.id}, token=#{k.token}, store_id=#{k.store_id}, store=#{store&.name}, revoked=#{k.revoked_at}"
end
