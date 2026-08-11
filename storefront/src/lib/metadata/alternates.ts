import { getClient, getLocaleOptions } from "@/lib/pallastrade";
import { buildCanonicalUrl } from "@/lib/seo";
import { getDefaultCountry, getDefaultLocale, getStoreUrl } from "@/lib/store";

export interface CountryLocale {
  country: string;
  locale: string;
}

/**
 * Resolve all available country/locale combinations from PallasTrade markets.
 * Falls back to the default country/locale configured via env vars.
 */
export async function resolveAllCountryLocales(): Promise<CountryLocale[]> {
  const localeOptions = await getLocaleOptions();
  try {
    const { data: markets } = await getClient().markets.list(localeOptions);
    const seen = new Set<string>();
    const result: CountryLocale[] = [];

    for (const market of markets) {
      for (const country of market.countries ?? []) {
        const iso = country.iso.toLowerCase();
        if (seen.has(iso)) continue;
        seen.add(iso);
        result.push({
          country: iso,
          locale:
            market.default_locale || localeOptions.locale || getDefaultLocale(),
        });
      }
    }

    return result.length > 0
      ? result
      : [
          {
            country: getDefaultCountry(),
            locale: getDefaultLocale(),
          },
        ];
  } catch {
    return [
      {
        country: getDefaultCountry(),
        locale: getDefaultLocale(),
      },
    ];
  }
}

/**
 * Build hreflang alternate URLs for a given path across all country/locale combos.
 * Each entry maps a locale (e.g., "en-US") to its full URL.
 */
export async function buildHreflangAlternates(
  path: string,
): Promise<Record<string, string>> {
  const storeUrl = getStoreUrl();
  if (!storeUrl) return {};

  const countryLocales = await resolveAllCountryLocales();
  const alternates: Record<string, string> = {};

  for (const { country, locale } of countryLocales) {
    const hreflang = `${locale}-${country.toUpperCase()}`;
    const url = buildCanonicalUrl(storeUrl, `/${country}/${locale}${path}`);
    alternates[hreflang] = url;
  }

  return alternates;
}

/**
 * Build og:locale:alternate entries for OpenGraph multi-language declarations.
 */
export async function buildOgLocaleAlternates(): Promise<string[]> {
  const countryLocales = await resolveAllCountryLocales();
  return countryLocales.map(
    ({ locale, country }) => `${locale}_${country.toUpperCase()}`,
  );
}
