puts "=== Payment Methods ==="
PallasTrade::PaymentMethod.all.each do |pm|
  puts "  id=#{pm.id}, type=#{pm.type}, name=#{pm.name}, active=#{pm.active}"
end

puts "\n=== Orders ==="
PallasTrade::Order.all.each do |o|
  puts "  ##{o.number}, state=#{o.state}, total=#{o.total}, payment_state=#{o.payment_state}"
end

puts "\n=== Checking Stripe Gateway ==="
stripe = PallasTrade::PaymentMethod.find_by(type: 'PallasTradeStripe::Gateway')
old_stripe = PallasTrade::PaymentMethod.find_by(type: 'PallasTradeStripe::Gateway')
puts "New Stripe: #{stripe.inspect}"
puts "Old Stripe: #{old_stripe.inspect}"
