# encoding: UTF-8
lib = File.expand_path('../lib/', __FILE__)
$LOAD_PATH.unshift lib unless $LOAD_PATH.include?(lib)

require 'pallastrade_legacy_product_properties/version'

Gem::Specification.new do |s|
  s.platform    = Gem::Platform::RUBY
  s.name        = 'pallastrade_legacy_product_properties'
  s.version     = PallasTradeLegacyProductProperties::VERSION
  s.summary     = "Legacy Product Properties for PallasTrade Commerce"
  s.description = "Legacy product properties system extracted from PallasTrade core. Replaced by Metafields in PallasTrade 5.x."
  s.required_ruby_version = '>= 3.2'

  s.author    = 'Vendo Connect Inc., Vendo Sp. z o.o.'
  s.email     = 'hello@pallastradecommerce.org'
  s.homepage  = 'https://github.com/pallastrade/pallastrade-legacy-product-properties'
  s.license   = 'MIT'

  s.files        = Dir["{app,config,db,lib}/**/*", "LICENSE.md", "Rakefile", "README.md"].reject { |f| f.match(/^spec/) && !f.match(/^spec\/fixtures/) }
  s.require_path = 'lib'
  s.requirements << 'none'

  pallastrade_version = '>= 5.4.0.beta'
  s.add_dependency 'pallastrade', pallastrade_version
  s.add_dependency 'pallastrade_admin', pallastrade_version

  s.add_development_dependency 'pallastrade_dev_tools'
end
