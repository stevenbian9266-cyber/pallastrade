Rails.application.config.after_initialize do
  require 'mobility/action_text'

  # Mobility validates locales through I18n even though translated commerce
  # content deliberately supports more locales than the installed admin UI
  # translation bundles. Register the canonical content locale set so market
  # locales such as +pt+ can be read, written, and indexed.
  I18n.available_locales = (
    I18n.available_locales.map(&:to_s) + PallasTrade::Locales::ALL
  ).uniq
end

Mobility.configure do |config|
  config.plugins do
    ransack
    backend :table
    active_record
    reader
    writer
    backend_reader
    query
    cache
    store_based_fallbacks
    locale_accessors
    presence
    dirty
    column_fallback
  end
end
