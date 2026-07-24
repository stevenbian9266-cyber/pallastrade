module PallasTrade
  module Admin
    # View helpers for the legacy admin's layout direction (`<html dir>`).
    # RTL detection itself lives on PallasTrade::Locale (the single source of truth).
    module RtlHelper
      def rtl_locale?(locale = I18n.locale)
        PallasTrade::Locale.new(code: locale).rtl?
      end

      def html_dir(locale = I18n.locale)
        PallasTrade::Locale.new(code: locale).direction
      end
    end
  end
end
