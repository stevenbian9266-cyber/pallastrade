require 'factory_bot'
require 'rspec/rails'

FactoryBot.find_definitions

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
end

# enable factories decorators
Dir[Rails.root.join('spec/factories/pallastrade/**/*.rb')].sort.each do |factory|
  require factory if factory =~ /decorator/
end

# Load payment gem testing factories (Stripe, Adyen, PayPal)
begin
  require 'pallastrade_stripe/factories'
rescue LoadError
  # Stripe gem not available in this test context
end

# Load AI gem testing factories (AI Provider)
begin
  require 'pallastrade_ai/factories'
rescue LoadError
  # AI gem not available in this test context
end
