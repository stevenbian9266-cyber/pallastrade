puts "Current.currency: #{PallasTrade::Current.currency.inspect}"
puts "Current.channel: #{PallasTrade::Current.channel&.name.inspect}"
puts "Current.store: #{PallasTrade::Current.store&.name.inspect}"
puts ""

# Test store default
store = PallasTrade::Store.find(4)
puts "Store default currency: #{store.default_currency}"
puts "Store default channel: #{store.default_channel&.name}"

# Test available with explicit currency
scope = PallasTrade::Product.for_store(store)
  .accessible_by(PallasTrade::Ability.new(PallasTrade.user_class.new, store: store), :index)
  .available(Time.current, store.default_currency, include_preorderable: true)
puts ""
puts "Available with explicit USD: #{scope.count}"

# Test without currency
scope2 = PallasTrade::Product.for_store(store)
  .accessible_by(PallasTrade::Ability.new(PallasTrade.user_class.new, store: store), :index)
  .available(Time.current, nil, include_preorderable: true)
puts "Available with nil currency: #{scope2.count}"

# Check the SQL difference
puts ""
puts "SQL with USD:"
puts scope.to_sql
puts ""
puts "SQL with nil:"
puts scope2.to_sql
