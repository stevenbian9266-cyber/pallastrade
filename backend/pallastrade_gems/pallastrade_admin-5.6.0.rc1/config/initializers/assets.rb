if Rails.application.config.respond_to?(:assets)
  Rails.application.config.assets.precompile << 'pallastrade_admin_manifest.js'
end
