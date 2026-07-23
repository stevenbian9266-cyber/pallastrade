# encoding: UTF-8
lib = File.expand_path('../lib/', __FILE__)
$LOAD_PATH.unshift lib unless $LOAD_PATH.include?(lib)

require 'pallastrade_stripe/version'

Gem::Specification.new do |s|
  s.platform    = Gem::Platform::RUBY
  s.name        = 'pallastrade_stripe'
  s.version     = PallasTradeStripe::VERSION
  s.summary     = "Official PallasTrade Commerce Stripe payment gateway extension"
  s.required_ruby_version = '>= 3.2'

  s.author    = 'Steven Bian'
  s.email     = 'stevenbian9266@gmail.com'
  s.homepage  = 'https://github.com/stevenbian9266-cyber/pallastrade'

  s.metadata = {
    'bug_tracker_uri' => 'https://github.com/stevenbian9266-cyber/pallastrade/issues',
    'changelog_uri' => "https://github.com/stevenbian9266-cyber/pallastrade/releases",
    'documentation_uri' => 'https://pallastrade.cn/docs/',
    'source_code_uri' => "https://github.com/stevenbian9266-cyber/pallastrade/tree/main/platform/payments/pallastrade_stripe"
  }

  s.files        = Dir["{app,config,db,lib,vendor}/**/*", "Rakefile", "README.md"].reject { |f| f.match(/^spec/) && !f.match(/^spec\/fixtures/) }
  s.require_path = 'lib'
  s.requirements << 'none'

  pallastrade_version = '>= 5.4.0.beta'
  s.add_dependency 'pallastrade', pallastrade_version
  s.add_dependency 'pallastrade_admin', pallastrade_version

  s.add_dependency 'stripe', '>= 10.1', '< 19'
  s.add_dependency 'stripe_event', '~> 2.14'

  s.add_development_dependency 'dotenv'
  s.add_development_dependency 'pallastrade_dev_tools'
  s.add_development_dependency 'vcr'
  s.add_development_dependency 'webmock'
  s.add_development_dependency 'i18n-tasks'
end
