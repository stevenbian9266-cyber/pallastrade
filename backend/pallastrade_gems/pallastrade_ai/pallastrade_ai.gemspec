# -*- encoding: utf-8 -*-
# stub: pallastrade_ai 1.0.0 ruby lib

Gem::Specification.new do |s|
  s.name = "pallastrade_ai".freeze
  s.version = "1.0.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = {
    "bug_tracker_uri" => "https://github.com/stevenbian9266-cyber/pallastrade/issues",
    "changelog_uri" => "https://github.com/stevenbian9266-cyber/pallastrade/releases",
    "documentation_uri" => "https://pallastrade.cn/docs/",
    "source_code_uri" => "https://github.com/stevenbian9266-cyber/pallastrade/tree/main/backend/pallastrade_gems/pallastrade_ai"
  } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Steven Bian".freeze]
  s.date = "2026-07-24"
  s.email = "stevenbian9266@gmail.com".freeze
  s.homepage = "https://github.com/stevenbian9266-cyber/pallastrade".freeze
  s.required_ruby_version = Gem::Requirement.new(">= 3.2".freeze)
  s.requirements = ["none".freeze]
  s.rubygems_version = "4.0.2".freeze
  s.summary = "PallasTrade AI Tools Platform 鈥?provider management, gateway, and capability registry".freeze

  s.installed_by_version = "4.0.3".freeze
  s.specification_version = 4

  s.add_runtime_dependency(%q<pallastrade>.freeze, [">= 5.6.0.rc1".freeze])
  s.add_runtime_dependency(%q<pallastrade_core>.freeze, [">= 5.6.0.rc1".freeze])
  s.add_runtime_dependency(%q<pallastrade_api>.freeze, [">= 5.6.0.rc1".freeze])
  s.add_runtime_dependency(%q<pallastrade_admin>.freeze, [">= 5.6.0.rc1".freeze])
  s.add_runtime_dependency(%q<faraday>.freeze, [">= 2.0".freeze, "< 3.0".freeze])
  s.add_runtime_dependency(%q<faraday-retry>.freeze, [">= 2.0".freeze])

  s.add_development_dependency(%q<dotenv>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<jsonapi-rspec>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<pallastrade_dev_tools>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<webmock>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<i18n-tasks>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<rspec-rails>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<factory_bot_rails>.freeze, [">= 0".freeze])
end
