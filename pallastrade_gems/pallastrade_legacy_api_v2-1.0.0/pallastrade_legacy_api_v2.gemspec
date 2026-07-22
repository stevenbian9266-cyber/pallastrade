# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift lib unless $LOAD_PATH.include?(lib)

require 'pallastrade_legacy_api_v2/version'

Gem::Specification.new do |s|
  s.name          = 'pallastrade_legacy_api_v2'
  s.version       = PallasTradeLegacyApiV2::VERSION
  s.authors       = ['Ryan Bigg', 'Spark Solutions Sp. z o.o.', 'Vendo Connect Inc.']
  s.email         = ['hello@pallastradecommerce.org']
  s.summary       = "PallasTrade's Legacy API v2"
  s.description   = 'Legacy API v2 endpoints for PallasTrade Commerce.'
  s.homepage      = 'https://pallastradecommerce.org'
  s.licenses      = ['AGPL-3.0-or-later', 'BSD-3-Clause']

  s.metadata = {
    'bug_tracker_uri' => 'https://github.com/pallastrade/pallastrade_legacy_api_v2/issues',
    'changelog_uri' => "https://github.com/pallastrade/pallastrade_legacy_api_v2/releases/tag/v#{s.version}",
    'documentation_uri' => 'https://docs.pallastradecommerce.org/',
    'source_code_uri' => "https://github.com/pallastrade/pallastrade_legacy_api_v2/tree/v#{s.version}"
  }

  s.required_ruby_version = '>= 3.2'

  s.files = Dir['{app,config,db,lib,vendor}/**/*', 'LICENSE.md', 'Rakefile', 'README.md'].reject do |f|
    f.match(/^spec/) && !f.match(%r{^spec/fixtures})
  end
  s.require_paths = ['lib']

  s.add_development_dependency 'jsonapi-rspec'
  s.add_development_dependency 'multi_json'

  s.add_dependency 'doorkeeper', '~> 5.3'
  s.add_dependency 'jsonapi-serializer', '~> 2.1'
  s.add_dependency 'pagy', '~> 43.0'

  s.add_dependency 'pallastrade', '>= 5.4.0.beta8'
  s.add_dependency 'pallastrade_posts'
  s.add_dependency 'pallastrade_legacy_product_properties'
end
