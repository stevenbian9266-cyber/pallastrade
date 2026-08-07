# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# TinyMCE-rails stores its skins under vendor/assets/javascripts.
# Propshaft doesn't auto-discover gem vendor paths in all Rails versions;
# register them explicitly so tinymce/skins/ui/oxide/skin.min.css resolves.
begin
  gem_root = Gem::Specification.find_by_name('tinymce-rails').gem_dir
  tinymce_assets = File.join(gem_root, 'vendor', 'assets', 'javascripts')
  Rails.application.config.assets.paths << tinymce_assets if File.directory?(tinymce_assets)
rescue Gem::MissingSpecError
  # tinymce-rails not installed — skip
end
