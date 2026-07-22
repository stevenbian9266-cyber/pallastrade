s = PallasTrade::Store.default
s.update!(default_currency: 'USD')
PallasTrade::Config.show_products_without_price = true
puts "OK: currency=#{s.reload.default_currency} show_without_price=#{PallasTrade::Config.show_products_without_price} count=#{PallasTrade::Product.available.count}"
