if defined?(PallasTrade::Admin)
  require 'pallastrade/admin/testing_support/capybara_utils'
  require 'pallastrade/admin/testing_support/tom_select'

  RSpec.configure do |config|
    config.include PallasTrade::Admin::TestingSupport::CapybaraUtils
    config.include PallasTrade::Admin::TestingSupport::TomSelect
  end
end
