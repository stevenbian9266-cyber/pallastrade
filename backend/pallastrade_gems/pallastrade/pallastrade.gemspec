# -*- encoding: utf-8 -*-
# stub: PallasTrade 5.6.0.rc1 ruby lib

Gem::Specification.new do |s|
  s.name = "pallastrade".freeze
  s.version = "5.6.0.rc1".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://github.com/stevenbian9266-cyber/pallastrade/issues", "changelog_uri" => "https://github.com/stevenbian9266-cyber/pallastrade/releases", "documentation_uri" => "https://pallastrade.cn/docs/", "source_code_uri" => "https://github.com/stevenbian9266-cyber/pallastrade/tree/main/backend/pallastrade_gems/pallastrade" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Steven Bian".freeze]
  s.date = "2026-07-15"
  s.description = "A complete open source e-commerce solution with multi-store, multi-currency and multi-language capabilities".freeze
  s.email = "stevenbian9266@gmail.com".freeze
  s.homepage = "https://pallastrade.cn".freeze
  s.required_ruby_version = Gem::Requirement.new(">= 3.2".freeze)
  s.requirements = ["none".freeze]
  s.rubygems_version = "3.5.22".freeze
  s.summary = "A complete open source e-commerce solution".freeze

  s.installed_by_version = "4.0.3".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<pallastrade_core>.freeze, ["= 5.6.0.rc1".freeze])
  s.add_runtime_dependency(%q<pallastrade_api>.freeze, ["= 5.6.0.rc1".freeze])
end
