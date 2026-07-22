require 'net/http'
require 'json'
require 'uri'

BASE = 'http://localhost:3000'

# Step 1: Get a product
uri = URI("#{BASE}/api/v3/store/products?per_page=1")
res = Net::HTTP.get_response(uri)
products = JSON.parse(res.body)['data']
variant_id = products.first['id']
puts "Product: #{products.first['attributes']['name']} (variant_id=#{variant_id})"

# Step 2: Get/Create a cart (guest)
# The storefront uses POST to create a cart via the storefront proxy
# Let's check cart endpoints
uri = URI("#{BASE}/api/v3/store/cart")
http = Net::HTTP.new(uri.host, uri.port)
req = Net::HTTP::Get.new(uri)
res = http.request(req)
cart = JSON.parse(res.body)['data']
cart_token = cart['attributes']['token']
puts "Cart token: #{cart_token}"

# Step 3: Add item to cart
uri = URI("#{BASE}/api/v3/store/cart/add_item")
req = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
req['X-PallasTrade-Cart-Token'] = cart_token
req.body = { variant_id: variant_id, quantity: 1 }.to_json
res = http.request(req)
result = JSON.parse(res.body)
puts "Add to cart: #{result.inspect[0..200]}"
