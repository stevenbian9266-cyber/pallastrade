# -*- encoding: utf-8 -*-
# stub: pallastrade_stripe 1.7.1 ruby lib

Gem::Specification.new do |s|
  s.name = "pallastrade_stripe".freeze
  s.version = "1.7.1".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://github.com/stevenbian9266-cyber/pallastrade/issues", "changelog_uri" => "https://github.com/stevenbian9266-cyber/pallastrade/releases", "documentation_uri" => "https://pallastrade.cn/docs/", "source_code_uri" => "https://github.com/stevenbian9266-cyber/pallastrade/tree/main/backend/pallastrade_gems/pallastrade_stripe-1.7.1" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Steven Bian".freeze]
  s.date = "1980-01-02"
  s.email = "stevenbian9266@gmail.com".freeze
  s.homepage = "https://github.com/stevenbian9266-cyber/pallastrade".freeze
  s.required_ruby_version = Gem::Requirement.new(">= 3.2".freeze)
  s.requirements = ["none".freeze]
  s.rubygems_version = "4.0.2".freeze
  s.summary = "Official PallasTrade Commerce Stripe payment gateway extension".freeze

  s.installed_by_version = "4.0.3".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<pallastrade>.freeze, [">= 5.4.0.beta".freeze])
  s.add_runtime_dependency(%q<pallastrade_admin>.freeze, [">= 5.4.0.beta".freeze])
  s.add_runtime_dependency(%q<stripe>.freeze, [">= 10.1".freeze, "< 19".freeze])
  s.add_runtime_dependency(%q<stripe_event>.freeze, ["~> 2.14".freeze])
  s.add_development_dependency(%q<dotenv>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<jsonapi-rspec>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<pallastrade_dev_tools>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<vcr>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<webmock>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<i18n-tasks>.freeze, [">= 0".freeze])
end
