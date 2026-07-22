s = PallasTrade::Store.default
puts "Before: #{s.default_currency}"
s.update!(default_currency: 'USD')
puts "After: #{s.reload.default_currency}"
puts "Prices: #{PallasTrade::Price.pluck(:currency).uniq}"
