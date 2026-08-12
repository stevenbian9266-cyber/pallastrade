import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { NextIntlClientProvider } from "next-intl";
import { CartDrawer } from "@/components/cart/CartDrawer";
import { CookieBanner } from "@/components/cookie/CookieBanner";
import { JsonLd } from "@/components/seo/JsonLd";
import { Toaster } from "@/components/ui/sonner";
import { AuthProvider } from "@/contexts/AuthContext";
import { CartProvider } from "@/contexts/CartContext";
import { StoreProvider } from "@/contexts/StoreContext";
import { getMarkets } from "@/lib/data/markets";
import { generateStoreMetadata } from "@/lib/metadata/store";
import { buildOrganizationJsonLd } from "@/lib/seo";
import { getDefaultCountry, getDefaultLocale } from "@/lib/store";
import deMessages from "../../../../messages/de.json";
import enMessages from "../../../../messages/en.json";
import esMessages from "../../../../messages/es.json";
import frMessages from "../../../../messages/fr.json";
import plMessages from "../../../../messages/pl.json";

const messagesMap: Record<string, IntlMessages> = {
  en: enMessages,
  de: deMessages,
  es: esMessages,
  fr: frMessages,
  pl: plMessages,
};

interface CountryLocaleLayoutProps {
  children: React.ReactNode;
  params: Promise<{
    country: string;
    locale: string;
  }>;
}

export async function generateMetadata({
  params,
}: CountryLocaleLayoutProps): Promise<Metadata> {
  const { locale } = await params;
  return generateStoreMetadata({ locale });
}

export default async function CountryLocaleLayout({
  children,
  params,
}: CountryLocaleLayoutProps) {
  const { country, locale } = await params;

  const markets = await getMarkets({ country, locale })
    .then((res) => res.data)
    .catch(() => null);

  // Explicitly handle the "API down / 401" unknown state: treat it as no
  // markets so we never redirect into an infinite loop, and pass an empty
  // list to the client (degraded UI uses default locale/country).
  const marketList = markets ?? [];

  // Validate that the URL country belongs to an available market.
  // If not, redirect server-side to avoid SSR with wrong prices.
  // BUT: if markets failed to load (API down / 401), don't redirect —
  // that would create an infinite loop since every page load would fail
  // and redirect back to the default, which would fail again, etc.
  const isValidCountry = marketList.some((market) =>
    market.countries?.some(
      (c) => c.iso.toLowerCase() === country.toLowerCase(),
    ),
  );

  if (!isValidCountry && marketList.length > 0) {
    const defaultMarket = marketList.find((m) => m.default) ?? marketList[0];
    const fallbackCountry =
      defaultMarket?.countries?.[0]?.iso.toLowerCase() ?? getDefaultCountry();
    const fallbackLocale = defaultMarket?.default_locale ?? getDefaultLocale();

    // Guard against redirecting to the same URL (causes infinite loop)
    if (
      fallbackCountry !== country.toLowerCase() ||
      fallbackLocale !== locale
    ) {
      redirect(`/${fallbackCountry}/${fallbackLocale}`);
    }
  }

  // Load messages statically (no runtime data access) to avoid blocking prerender
  const messages = messagesMap[locale] || messagesMap.en;

  return (
    <NextIntlClientProvider
      messages={messages}
      locale={locale as "en" | "de" | "pl"}
    >
      <StoreProvider
        initialCountry={country}
        initialLocale={locale}
        initialMarkets={marketList}
      >
        <AuthProvider>
          <CartProvider>
            <JsonLd data={buildOrganizationJsonLd()} />
            {children}
            <CartDrawer />
            <Toaster />
            {/* Cookie consent banner — first-visit only (# PRD-20260812-storefront-cookie). */}
            <CookieBanner />
          </CartProvider>
        </AuthProvider>
      </StoreProvider>
    </NextIntlClientProvider>
  );
}
