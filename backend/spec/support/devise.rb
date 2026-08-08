require 'rspec/rails'

if defined?(Warden)
  include Warden::Test::Helpers
  Warden.test_mode!
end

if defined?(Devise)
  RSpec.configure do |config|
    config.before(:each, type: :controller) do
      @request.env['devise.mapping'] = Devise.mappings[:user]
    end

    config.include Devise::Test::ControllerHelpers, type: :controller

    # Allow `sign_in <admin>` in request specs (Devise::Test::IntegrationHelpers)
    config.include Devise::Test::IntegrationHelpers, type: :request

    config.include Warden::Test::Helpers
    config.before :suite do
      Warden.test_mode!
    end
  end
end
