if Rails.application.config.respond_to?(:assets)
  Rails.application.config.assets.precompile << 'pallastrade_emails_manifest.js'
end
