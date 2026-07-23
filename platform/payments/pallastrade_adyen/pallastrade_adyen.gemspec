# encoding: UTF-8
lib = File.expand_path('../lib/', __FILE__)
$LOAD_PATH.unshift lib unless $LOAD_PATH.include?(lib)

require 'pallastrade_adyen/version'

Gem::Specification.new do |s|
  s.platform    = Gem::Platform::RUBY
  s.name        = 'pallastrade_adyen'
  s.version     = PallasTradeAdyen::VERSION
  s.summary     = "PallasTrade Commerce Adyen Extension"
  s.required_ruby_version = '>= 3.2'

  s.author    = 'Steven Bian'
  s.email     = 'stevenbian9266@gmail.com'
  s.homepage  = 'https://github.com/stevenbian9266-cyber/pallastrade'

  s.metadata = {
    'bug_tracker_uri' => 'https://github.com/stevenbian9266-cyber/pallastrade/issues',
    'changelog_uri' => "https://github.com/stevenbian9266-cyber/pallastrade/releases",
    'documentation_uri' => 'https://pallastrade.cn/docs/',
    'source_code_uri' => "https://github.com/stevenbian9266-cyber/pallastrade/tree/main/platform/payments/pallastrade_adyen"
  }

  s.files        = Dir["{app,config,db,lib,vendor}/**/*", "Rakefile", "README.md"].reject { |f| f.match(/^spec/) && !f.match(/^spec\/fixtures/) }
  s.require_path = 'lib'
  s.requirements << 'none'

  pallastrade_version = '>= 5.3.0'
  s.add_dependency 'pallastrade', pallastrade_version
  s.add_dependency 'pallastrade_admin', pallastrade_version

  s.add_dependency 'adyen-ruby-api-library', '>= 10.3', '< 12.0'

  s.add_development_dependency 'pallastrade_dev_tools', '>= 0.6.0'
  s.add_development_dependency 'vcr'
  s.add_development_dependency 'webmock'
  s.add_development_dependency 'pry-rails'
  s.add_development_dependency 'timecop'
end
