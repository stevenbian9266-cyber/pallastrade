# Simulate what the ProductsController does
store = PallasTrade::Store.find(4)

# Step 1: model_class.for_store(current_store)
scope1 = PallasTrade::Product.for_store(store)
puts "1. for_store: #{scope1.count}"

# Step 2: accessible_by (simulate guest user)
user = PallasTrade.user_class.new
ability = PallasTrade::Ability.new(user, store: store)
scope2 = scope1.accessible_by(ability, :index)
puts "2. + accessible_by: #{scope2.count}"

# Step 3: available
scope3 = scope2.available(Time.current, 'USD', include_preorderable: true)
puts "3. + available: #{scope3.count}"

# Step 4: includes
scope4 = scope3.includes([:product_publications, { primary_media: { attachment_attachment: :blob }, master: [:prices, { stock_items: [:stock_location, :active_stock_reservations] }], variants: [:prices, { stock_items: [:stock_location, :active_stock_reservations] }] }])
puts "4. + includes: #{scope4.count}"

# Check the SQL
puts ""
puts "SQL:"
puts scope2.to_sql
