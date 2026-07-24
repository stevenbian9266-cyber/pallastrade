# -*- encoding: utf-8 -*-
# stub: pallastrade_adyen 0.11.0 ruby lib

Gem::Specification.new do |s|
  s.name = "pallastrade_adyen".freeze
  s.version = "0.11.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://github.com/stevenbian9266-cyber/pallastrade/issues", "changelog_uri" => "https://github.com/stevenbian9266-cyber/pallastrade/releases", "documentation_uri" => "https://pallastrade.cn/docs/", "source_code_uri" => "https://github.com/stevenbian9266-cyber/pallastrade/tree/main/backend/pallastrade_gems/pallastrade_adyen" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Steven Bian".freeze]
  s.date = "1980-01-02"
  s.email = "stevenbian9266@gmail.com".freeze
  s.homepage = "https://github.com/stevenbian9266-cyber/pallastrade".freeze
  s.required_ruby_version = Gem::Requirement.new(">= 3.2".freeze)
  s.requirements = ["none".freeze]
  s.rubygems_version = "4.0.3".freeze
  s.summary = "PallasTrade Commerce Adyen Extension".freeze

  s.installed_by_version = "4.0.3".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<pallastrade>.freeze, [">= 5.3.0".freeze])
  s.add_runtime_dependency(%q<pallastrade_admin>.freeze, [">= 5.3.0".freeze])
  s.add_runtime_dependency(%q<adyen-ruby-api-library>.freeze, [">= 10.3".freeze, "< 12.0".freeze])
  s.add_development_dependency(%q<pallastrade_dev_tools>.freeze, [">= 0.6.0".freeze])
  s.add_development_dependency(%q<vcr>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<webmock>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<pry-rails>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<timecop>.freeze, [">= 0".freeze])
end
