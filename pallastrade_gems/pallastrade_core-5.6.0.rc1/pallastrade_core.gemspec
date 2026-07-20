# -*- encoding: utf-8 -*-
# stub: pallastrade_core 5.6.0.rc1 ruby lib

Gem::Specification.new do |s|
  s.name = "pallastrade_core".freeze
  s.version = "5.6.0.rc1".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 1.8.23".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://github.com/PallasTrade/PallasTrade/issues", "changelog_uri" => "https://github.com/PallasTrade/PallasTrade/releases/tag/v5.6.0.rc1", "documentation_uri" => "https://docs.PallasTradecommerce.org/", "source_code_uri" => "https://github.com/PallasTrade/PallasTrade/tree/v5.6.0.rc1" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Sean Schofield".freeze, "Spark Solutions Sp. z o.o.".freeze, "Vendo Connect Inc.".freeze]
  s.date = "2026-07-15"
  s.description = "PallasTrade Models, Helpers, Services and core libraries".freeze
  s.email = "hello@PallasTradecommerce.org".freeze
  s.homepage = "https://PallasTradecommerce.org".freeze
  s.licenses = ["BSD-3-Clause".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 3.2".freeze)
  s.rubygems_version = "3.5.22".freeze
  s.summary = "The bare bones necessary for PallasTrade".freeze

  s.installed_by_version = "4.0.3".freeze

  s.specification_version = 4

  s.add_development_dependency(%q<i18n-tasks>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<rails>.freeze, [">= 7.2".freeze, "< 8.2".freeze])
  s.add_runtime_dependency(%q<acts_as_list>.freeze, [">= 0.8".freeze])
  s.add_runtime_dependency(%q<acts-as-taggable-on>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<awesome_nested_set>.freeze, ["~> 3.3".freeze, ">= 3.3.1".freeze])
  s.add_runtime_dependency(%q<benchmark>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<carmen>.freeze, [">= 1.0".freeze])
  s.add_runtime_dependency(%q<cancancan>.freeze, ["~> 3.2".freeze])
  s.add_runtime_dependency(%q<countries>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<friendly_id>.freeze, ["~> 5.2".freeze, ">= 5.2.1".freeze])
  s.add_runtime_dependency(%q<geocoder>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<highline>.freeze, [">= 2".freeze, "< 4".freeze])
  s.add_runtime_dependency(%q<jwt>.freeze, ["~> 3.1".freeze])
  s.add_runtime_dependency(%q<money>.freeze, ["~> 6.13".freeze])
  s.add_runtime_dependency(%q<monetize>.freeze, ["~> 1.9".freeze])
  s.add_runtime_dependency(%q<name_of_person>.freeze, ["~> 1.1".freeze])
  s.add_runtime_dependency(%q<ostruct>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<paranoia>.freeze, [">= 2.4".freeze])
  s.add_runtime_dependency(%q<ransack>.freeze, [">= 4.1".freeze])
  s.add_runtime_dependency(%q<rexml>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<state_machines-activerecord>.freeze, ["~> 0.100".freeze])
  s.add_runtime_dependency(%q<state_machines-activemodel>.freeze, ["~> 0.100".freeze])
  s.add_runtime_dependency(%q<stringex>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<tracking_number>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<validates_zipcode>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<image_processing>.freeze, ["~> 1.2".freeze])
  s.add_runtime_dependency(%q<active_storage_validations>.freeze, [">= 1.3".freeze, "< 4".freeze])
  s.add_runtime_dependency(%q<mobility>.freeze, ["~> 1.3".freeze, ">= 1.3.2".freeze])
  s.add_runtime_dependency(%q<mobility-ransack>.freeze, ["~> 1.2".freeze])
  s.add_runtime_dependency(%q<mobility-actiontext>.freeze, ["~> 1.1".freeze])
  s.add_runtime_dependency(%q<friendly_id-mobility>.freeze, ["~> 1.0".freeze])
  s.add_runtime_dependency(%q<wannabe_bool>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<safely_block>.freeze, [">= 0.4".freeze, "< 2.0".freeze])
  s.add_runtime_dependency(%q<phonelib>.freeze, ["~> 0.10".freeze])
  s.add_runtime_dependency(%q<ar_lazy_preload>.freeze, ["~> 2.0".freeze])
  s.add_runtime_dependency(%q<bcrypt>.freeze, ["~> 3.1".freeze])
  s.add_runtime_dependency(%q<sqids>.freeze, ["~> 0.2".freeze])
  s.add_runtime_dependency(%q<ssrf_filter>.freeze, ["~> 1.0".freeze])
  s.add_runtime_dependency(%q<pagy>.freeze, [">= 43.3".freeze])
end
