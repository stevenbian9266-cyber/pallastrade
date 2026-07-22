# Direct API check from inside container
require 'net/http'
require 'json'

uri = URI('http://localhost:3000/api/store/v1/products/semi-automatic-espresso-machine')
res = Net::HTTP.get_response(uri)
data = JSON.parse(res.body)
attrs = data['data']['attributes']
puts "meta_title: #{attrs['meta_title'].inspect}"
puts "meta_description: #{attrs['meta_description'].inspect}"
puts "meta_keywords: #{attrs['meta_keywords'].inspect}"
