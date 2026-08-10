import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { Button } from "@/components/ui/button";
import { getStoreName } from "@/lib/store";

interface HeroSectionProps {
  basePath: string;
  locale: string;
}

/**
 * Brand hero — tagline + value prop + primary/secondary CTAs.
 * No demo-only links (PRD-20260810-storefront-... AC-105).
 */
export async function HeroSection({ basePath, locale }: HeroSectionProps) {
  const t = await getTranslations({
    locale: locale as Locale,
    namespace: "home",
  });
  const storeName = getStoreName();

  return (
    <section className="relative overflow-hidden bg-gradient-to-br from-primary-50 via-white to-primary-100 border-b border-gray-200">
      {/* Decorative accent */}
      <div
        aria-hidden="true"
        className="absolute -top-24 -right-24 size-72 rounded-full bg-primary/5 blur-3xl"
      />
      <div className="relative container mx-auto px-4 sm:px-6 lg:px-8 py-16 md:py-24">
        <div className="text-center">
          <p className="text-sm font-semibold uppercase tracking-widest text-primary">
            {t("heroTagline", { storeName })}
          </p>
          <h1 className="mt-3 text-4xl md:text-6xl font-bold tracking-tight text-gray-900">
            {t("heroTitle")}
          </h1>
          <p className="mt-5 text-lg text-gray-600 max-w-2xl mx-auto">
            {t("heroDescription")}
          </p>
          <div className="mt-8 flex justify-center gap-4 flex-wrap">
            <Button size="lg" asChild>
              <Link href={`${basePath}/products`}>{t("shopNow")}</Link>
            </Button>
            <Button variant="outline" size="lg" asChild>
              <Link href={`${basePath}/products`}>{t("browseCategories")}</Link>
            </Button>
          </div>
        </div>
      </div>
    </section>
  );
}
