import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { Button } from "@/components/ui/button";

/**
 * Home promo banner — wide gradient band with a single CTA.
 *
 * # PRD-20260810-storefront-对商城前台进行重新规划 AC-108
 */
interface PromoBannerProps {
  basePath: string;
  locale: string;
}

export async function PromoBanner({ basePath, locale }: PromoBannerProps) {
  const t = await getTranslations({
    locale: locale as Locale,
    namespace: "home",
  });

  return (
    <section
      aria-labelledby="promo-banner-heading"
      className="bg-gradient-to-r from-primary to-primary-700 text-white"
    >
      <div className="container mx-auto px-4 sm:px-6 lg:px-8 py-14 flex flex-col md:flex-row items-center justify-between gap-6">
        <div>
          <h2
            id="promo-banner-heading"
            className="text-2xl md:text-3xl font-bold"
          >
            {t("promoTitle")}
          </h2>
          <p className="mt-2 text-primary-100 max-w-xl">{t("promoSubtitle")}</p>
        </div>
        <Button size="lg" variant="secondary" className="shrink-0" asChild>
          <Link href={`${basePath}/products`}>{t("promoCta")}</Link>
        </Button>
      </div>
    </section>
  );
}
