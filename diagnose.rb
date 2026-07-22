# Deep diagnostics + fix
store = PallasTrade::Store.default
puts "=== Store ==="
puts "Default currency: #{store.default_currency}"
puts "Store ID: #{store.id}"

puts "\n=== Config ==="
puts "show_products_without_price: #{PallasTrade::Config.show_products_without_price}"

puts "\n=== Prices ==="
prices = PallasTrade::Price.all
puts "Total prices: #{prices.count}"
puts "Currencies: #{prices.pluck(:currency).uniq}"
usd_count = prices.where(currency: 'USD').count
puts "USD prices: #{usd_count}"

puts "\n=== Products ==="
puts "Total products: #{PallasTrade::Product.count}"
puts "Active products: #{PallasTrade::Product.where(status: 'active').count}"
puts "Available (no args): #{PallasTrade::Product.available.count}"
puts "Available (USD): #{PallasTrade::Product.available(nil, 'USD').count}"
puts "Available (store currency): #{PallasTrade::Product.available(nil, store.default_currency).count}"

# Check available scope SQL
puts "\n=== Available Scope SQL (USD) ==="
puts PallasTrade::Product.available(nil, 'USD').to_sql.truncate(500)

# Fix: Ensure store default currency matches price currency
if usd_count > 0 && store.default_currency != 'USD'
  puts "\n=== FIXING: Setting default currency to USD ==="
  store.update!(default_currency: 'USD')
  puts "Done. New default: #{store.reload.default_currency}"
end

# Fix: Enable show without price as safety net
unless PallasTrade::Config.show_products_without_price
  puts "\n=== FIXING: Enabling show_products_without_price ==="
  PallasTrade::Config.show_products_without_price = true
  puts "Done."
end

puts "\n=== Final check ==="
puts "Available products now: #{PallasTrade::Product.available.count}"
