import type { Category } from "@pallastrade/sdk";
import { ArrowRight } from "lucide-react";
import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { getCategories } from "@/lib/data/categories";

/**
 * Home category showcase — root category cards linking to each category page.
 * Renders nothing (graceful degrade) when there are no root categories.
 *
 * # PRD-20260810-storefront-对商城前台进行重新规划 AC-106
 */
interface CategoryShowcaseProps {
  basePath: string;
  locale: string;
}

export async function CategoryShowcase({
  basePath,
  locale,
}: CategoryShowcaseProps) {
  const t = await getTranslations({
    locale: locale as Locale,
    namespace: "home",
  });

  const rootCategories = await getCategories({
    depth_eq: 0,
    expand: ["children"],
  })
    .then((res) => res.data)
    .catch((error) => {
      console.error("CategoryShowcase: failed to load categories", error);
      return [] as Category[];
    });

  if (rootCategories.length === 0) {
    return null;
  }

  return (
    <section
      aria-labelledby="category-showcase-heading"
      className="bg-gray-50 py-16"
    >
      <div className="container mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex items-center justify-between mb-8">
          <h2
            id="category-showcase-heading"
            className="text-2xl md:text-3xl font-bold text-gray-900"
          >
            {t("browseByCategory")}
          </h2>
          <Link
            href={`${basePath}/products`}
            className="text-sm font-medium text-primary hover:text-primary/80 transition-colors"
          >
            {t("viewAll")} &rarr;
          </Link>
        </div>
        <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
          {rootCategories.map((category) => (
            <Link
              key={category.id}
              href={`${basePath}/c/${category.permalink}`}
              className="group flex flex-col justify-between rounded-xl border border-gray-200 bg-white p-5 transition-all hover:border-primary/40 hover:shadow-md"
            >
              <span className="text-base font-semibold text-gray-900 group-hover:text-primary transition-colors">
                {category.name}
              </span>
              <span className="mt-4 inline-flex items-center gap-1 text-sm text-gray-500 group-hover:text-primary transition-colors">
                {t("shopCategory")}
                <ArrowRight className="size-4 transition-transform group-hover:translate-x-0.5" />
              </span>
            </Link>
          ))}
        </div>
      </div>
    </section>
  );
}
