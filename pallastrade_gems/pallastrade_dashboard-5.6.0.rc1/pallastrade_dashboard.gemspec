# -*- encoding: utf-8 -*-
# stub: pallastrade_dashboard 5.6.0.rc1 ruby lib

Gem::Specification.new do |s|
  s.name = "pallastrade_dashboard".freeze
  s.version = "5.6.0.rc1".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://github.com/PallasTrade/PallasTrade/issues", "changelog_uri" => "https://github.com/PallasTrade/PallasTrade/releases/tag/v5.6.0.rc1", "documentation_uri" => "https://PallasTradecommerce.org/docs/developer/dashboard/deployment", "source_code_uri" => "https://github.com/PallasTrade/PallasTrade/tree/v5.6.0.rc1" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Vendo Connect Inc.".freeze]
  s.date = "2026-07-15"
  s.description = "Serves a built PallasTrade React Dashboard at /dashboard with SPA semantics \u2014 the single-node topology where the dashboard and the Admin API share one origin. Developer Preview; becomes the default admin delivery in PallasTrade 6.".freeze
  s.email = "hello@PallasTradecommerce.org".freeze
  s.homepage = "https://PallasTradecommerce.org".freeze
  s.licenses = ["BSD-3-Clause".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 3.2".freeze)
  s.rubygems_version = "3.5.22".freeze
  s.summary = "Hosts the PallasTrade React Dashboard from your PallasTrade server".freeze

  s.installed_by_version = "4.0.3".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<pallastrade>.freeze, [">= 5.6.0.rc1".freeze])
end
