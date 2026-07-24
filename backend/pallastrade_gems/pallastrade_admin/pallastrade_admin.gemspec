# -*- encoding: utf-8 -*-
# stub: pallastrade_admin 5.6.0.rc1 ruby lib

Gem::Specification.new do |s|
  s.name = "pallastrade_admin".freeze
  s.version = "5.6.0.rc1".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://github.com/stevenbian9266-cyber/pallastrade/issues", "changelog_uri" => "https://github.com/stevenbian9266-cyber/pallastrade/releases", "documentation_uri" => "https://pallastrade.cn/docs/", "source_code_uri" => "https://github.com/stevenbian9266-cyber/pallastrade/tree/main/backend/pallastrade_gems/pallastrade_admin" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Steven Bian".freeze]
  s.date = "2026-07-15"
  s.description = "Fully featured Admin Dashboard for PallasTrade Commerce. Manage your store, orders, products, and more.".freeze
  s.email = "stevenbian9266@gmail.com".freeze
  s.homepage = "https://pallastrade.cn".freeze
  s.required_ruby_version = Gem::Requirement.new(">= 3.2".freeze)
  s.rubygems_version = "3.5.22".freeze
  s.summary = "Admin Dashboard for PallasTrade Commerce maintained by Steven Bian".freeze

  s.installed_by_version = "4.0.3".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<pallastrade>.freeze, [">= 5.6.0.rc1".freeze])
  s.add_runtime_dependency(%q<active_link_to>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<breadcrumbs_on_rails>.freeze, ["~> 4.1".freeze])
  s.add_runtime_dependency(%q<chartkick>.freeze, ["~> 5.0".freeze])
  s.add_runtime_dependency(%q<tailwindcss-rails>.freeze, [">= 4.0".freeze])
  s.add_runtime_dependency(%q<tailwindcss-ruby>.freeze, [">= 4.0".freeze])
  s.add_runtime_dependency(%q<groupdate>.freeze, ["~> 6.2".freeze])
  s.add_runtime_dependency(%q<hightop>.freeze, ["~> 0.3".freeze])
  s.add_runtime_dependency(%q<importmap-rails>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<inline_svg>.freeze, ["~> 1.10".freeze])
  s.add_runtime_dependency(%q<local_time>.freeze, ["~> 3.0".freeze])
  s.add_runtime_dependency(%q<mapkick-rb>.freeze, ["~> 0.1".freeze])
  s.add_runtime_dependency(%q<turbo-rails>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<stimulus-rails>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<tinymce-rails>.freeze, ["~> 6.8.5".freeze])
  s.add_runtime_dependency(%q<ruby-oembed>.freeze, ["~> 0.18".freeze])
end
