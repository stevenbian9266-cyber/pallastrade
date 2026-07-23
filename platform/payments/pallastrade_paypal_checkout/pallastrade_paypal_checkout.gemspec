# encoding: UTF-8
lib = File.expand_path('../lib/', __FILE__)
$LOAD_PATH.unshift lib unless $LOAD_PATH.include?(lib)

require 'pallastrade_paypal_checkout/version'

Gem::Specification.new do |s|
  s.platform    = Gem::Platform::RUBY
  s.name        = 'pallastrade_paypal_checkout'
  s.version     = PallasTradePaypalCheckout::VERSION
  s.summary     = "PallasTrade Commerce PayPal Checkout payment gateway integration"
  s.required_ruby_version = '>= 3.0'

  s.author    = 'Steven Bian'
  s.email     = 'stevenbian9266@gmail.com'
  s.homepage  = 'https://github.com/stevenbian9266-cyber/pallastrade'

  s.metadata = {
    'bug_tracker_uri' => 'https://github.com/stevenbian9266-cyber/pallastrade/issues',
    'changelog_uri' => "https://github.com/stevenbian9266-cyber/pallastrade/releases",
    'documentation_uri' => 'https://pallastrade.cn/docs/',
    'source_code_uri' => "https://github.com/stevenbian9266-cyber/pallastrade/tree/main/platform/payments/pallastrade_paypal_checkout"
  }

  s.files        = Dir["{app,config,db,lib,vendor}/**/*", "Rakefile", "README.md"].reject { |f| f.match(/^spec/) && !f.match(/^spec\/fixtures/) }
  s.require_path = 'lib'
  s.requirements << 'none'

  pallastrade_opts = '>= 5.4.0'
  s.add_dependency 'pallastrade', pallastrade_opts
  s.add_dependency 'pallastrade_admin', pallastrade_opts

  s.add_dependency 'paypal-server-sdk', '~> 1.1'

  s.add_development_dependency 'dotenv'
  s.add_development_dependency 'pallastrade_dev_tools'
  s.add_development_dependency 'vcr'
  s.add_development_dependency 'webmock'
end
