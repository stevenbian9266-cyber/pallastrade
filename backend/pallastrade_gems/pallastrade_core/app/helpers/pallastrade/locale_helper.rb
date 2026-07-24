module PallasTrade
  module LocaleHelper
    def all_locales_options
      supported_locales_for_all_stores.map { |locale| locale_presentation(locale) }
    end

    # Locales the admin UI is translated into, as [name, code] pairs for a
    # select. Self-contained (reads PallasTrade.available_locales directly) so it
    # works outside the storefront/admin controller stack — e.g. the pre-auth
    # login screen, which has no current store.
    def admin_locales_options
      PallasTrade.available_locales.map { |locale| locale_presentation(locale) }
    end

    def available_locales_options
      available_locales.map { |locale| locale_presentation(locale) }
    end

    # Locales a merchant may translate **content** into, as [name, code] pairs
    # for a select. Backed by `PallasTrade::Locales::ALL` (the canonical translation
    # locale set) rather than the installed UI-translation bundles, so a
    # market/store can adopt any supported locale instead of only ones already
    # in use.
    def translation_locales_options
      PallasTrade::Locales::ALL.map { |locale| locale_presentation(locale) }
    end

    def supported_locales_options
      return if current_store.nil?

      current_store.supported_locales_list.map { |locale| locale_presentation(locale) }
    end

    def locale_presentation(locale)
      [PallasTrade::Locale.new(code: locale).label, locale.to_s]
    end

    def should_render_locale_dropdown?
      return false if current_store.nil?

      current_store.supported_locales_list.size > 1
    end
  end
end
