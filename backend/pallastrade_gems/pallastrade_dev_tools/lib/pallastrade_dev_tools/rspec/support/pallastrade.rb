require 'rspec/rails'
require 'ffaker'

require 'pallastrade/testing_support/authorization_helpers'
require 'pallastrade/testing_support/factories'
require 'pallastrade/testing_support/preferences'
require 'pallastrade/testing_support/jobs'
require 'pallastrade/testing_support/store'
require 'pallastrade/testing_support/controller_requests'
require 'pallastrade/testing_support/url_helpers'
require 'pallastrade/testing_support/order_walkthrough'
require 'pallastrade/testing_support/capybara_config'
require 'pallastrade/testing_support/rspec_retry_config'
require 'pallastrade/testing_support/image_helpers'
require 'pallastrade/core/controller_helpers/strong_parameters'

require 'pallastrade/api/testing_support/v3/base'

module PallasTrade
  module TestingSupport
    module ApiHelpers
      def json_response
        case body = JSON.parse(response.body)
        when Hash
          body.with_indifferent_access
        when Array
          body
        end
      end
    end
  end
end

RSpec.configure do |config|
  config.include PallasTrade::TestingSupport::Preferences
  config.include PallasTrade::TestingSupport::UrlHelpers
  config.include PallasTrade::TestingSupport::ControllerRequests, type: :controller
  config.include PallasTrade::TestingSupport::ImageHelpers
  config.include PallasTrade::Core::ControllerHelpers::StrongParameters, type: :controller
  config.include PallasTrade::TestingSupport::ApiHelpers, type: :request

  config.before(:each) do
    PallasTrade::LegacyWebhooks.disabled = true if defined?(PallasTrade::LegacyWebhooks) && PallasTrade::LegacyWebhooks.respond_to?(:disabled=)
    reset_pallastrade_preferences
  end
end
