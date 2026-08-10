import Link from "next/link";
import { getTranslations } from "next-intl/server";

/**
 * Brand story — authoritative, scannable "answer-ready" paragraph for GEO.
 * First sentence answers "what is this store" directly (PRD-20260810... AC-108/AC-115).
 */
interface BrandStoryProps {
  basePath: string;
  locale: string;
}

export async function BrandStory({ basePath, locale }: BrandStoryProps) {
  const t = await getTranslations({
    locale: locale as Locale,
    namespace: "home",
  });

  return (
    <section
      aria-labelledby="brand-story-heading"
      className="border-b border-gray-200 py-16"
    >
      <div className="container mx-auto px-4 sm:px-6 lg:px-8">
        <div className="mx-auto max-w-3xl text-center">
          <h2
            id="brand-story-heading"
            className="text-2xl md:text-3xl font-bold text-gray-900"
          >
            {t("brandTitle")}
          </h2>
          <p className="mt-5 text-lg leading-relaxed text-gray-700">
            {t("brandBody")}
          </p>
          <Link
            href={`${basePath}/products`}
            className="mt-6 inline-block text-sm font-semibold text-primary hover:text-primary/80 transition-colors"
          >
            {t("brandCta")} &rarr;
          </Link>
        </div>
      </div>
    </section>
  );
}
