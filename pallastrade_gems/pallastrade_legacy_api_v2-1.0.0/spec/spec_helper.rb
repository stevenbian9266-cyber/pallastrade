# frozen_string_literal: true

if ENV['COVERAGE']
  # Run Coverage report
  require 'simplecov'
  SimpleCov.start 'rails' do
    add_group 'Serializers', 'app/serializers'
    add_group 'Libraries', 'lib/pallastrade'

    add_filter '/bin/'
    add_filter '/db/'
    add_filter '/script/'
    add_filter '/spec/'
    add_filter '/lib/pallastrade/api/testing_support/'

    coverage_dir "#{ENV['COVERAGE_DIR']}/legacy_api_v2_" + ENV.fetch('CIRCLE_NODE_INDEX', 0) if ENV['COVERAGE_DIR']
    command_name "test_#{ENV.fetch('CIRCLE_NODE_INDEX', 0)}"
  end
end

# This file is copied to spec/ when you run 'rails generate rspec:install'
ENV['RAILS_ENV'] ||= 'test'

begin
  require File.expand_path('dummy/config/environment', __dir__)
rescue LoadError
  puts 'Could not load dummy application. Please ensure you have run `bundle exec rake test_app`'
  exit
end

require 'rspec/rails'
require 'database_cleaner/active_record'
require 'ffaker'
require 'webmock/rspec'
require 'i18n/tasks'
require 'jsonapi/rspec'

# Requires supporting ruby files with custom matchers and macros, etc,
# in spec/support/ and its subdirectories.
Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each { |f| require f }

require 'pallastrade/testing_support/factories'
require 'pallastrade/testing_support/jobs'
require 'pallastrade/testing_support/store'
require 'pallastrade/testing_support/preferences'
require 'pallastrade/testing_support/image_helpers'
require 'pallastrade/testing_support/next_instance_of'
require 'pallastrade/testing_support/rspec_retry_config'

require 'pallastrade_legacy_api_v2/testing_support/v2/base'
require 'pallastrade_legacy_api_v2/testing_support/v2/current_order'
require 'pallastrade_legacy_api_v2/testing_support/v2/platform_contexts'
require 'pallastrade_legacy_api_v2/testing_support/v2/serializers_params'
require 'pallastrade_legacy_api_v2/testing_support/serializers'
require 'pallastrade_legacy_api_v2/testing_support/factories'

require 'pallastrade_posts/factories'
require 'pallastrade_legacy_product_properties/factories'

def json_response
  case body = JSON.parse(response.body)
  when Hash
    body.with_indifferent_access
  when Array
    body
  end
end

RSpec.configure do |config|
  config.backtrace_exclusion_patterns = [%r{gems/activesupport}, %r{gems/actionpack}, %r{gems/rspec}]
  config.color = true
  config.fail_fast = ENV['FAIL_FAST'] || false
  config.infer_spec_type_from_file_location!
  config.raise_errors_for_deprecations!
  config.use_transactional_fixtures = true

  config.include JSONAPI::RSpec
  config.include FactoryBot::Syntax::Methods
  config.include PallasTrade::TestingSupport::Preferences
  config.include PallasTrade::TestingSupport::ImageHelpers

  config.before(:suite) do
    PallasTrade::Events.disable!
    # Clean out the database state before the tests run
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end

  # Re-enable events for specs that need them
  config.around(:each, events: true) do |example|
    PallasTrade::Events.enable { example.run }
  end

  config.before do
    reset_pallastrade_preferences

    # Request specs to paths with ?locale=xx don't reset the locale afterwards
    # Some tests assume that the current locale is :en, so we ensure it here
    I18n.locale = :en

    # Reset PallasTrade::Current to avoid stale memoized values between tests
    PallasTrade::Current.reset
  end

  config.around(:each) do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end

  config.order = :random
end
