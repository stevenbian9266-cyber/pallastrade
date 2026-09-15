import type { Product } from "@pallastrade/sdk";
import { getTranslations } from "next-intl/server";
import { LazyProductCarousel } from "@/components/products/LazyProductCarousel";
import { getRelatedProducts } from "@/lib/data/products";
import {
  categoryIdsFor,
  RELATED_PRODUCTS_LIMIT,
} from "@/lib/utils/related-products";

interface RelatedProductsProps {
  product: Product;
  basePath: string;
  locale: Locale;
  country: string;
  currency?: string;
}

/**
 * Rule-based "related products" rail (PRD-20260915-catalog-batch-c1-discovery
 * FR-001/FR-002): same categories, buyable now, never the product on screen.
 *
 * Renders nothing when the product has no categories or nothing matches, so the
 * page never shows an empty heading.
 */
export async function RelatedProducts({
  product,
  basePath,
  locale,
  country,
  currency,
}: RelatedProductsProps) {
  const categoryIds = categoryIdsFor(product);
  if (categoryIds.length === 0) return null;

  const related = await getRelatedProducts({
    categoryIds,
    excludeProductId: product.id,
    limit: RELATED_PRODUCTS_LIMIT,
    locale,
    country,
  });
  if (related.length === 0) return null;

  const t = await getTranslations({ locale, namespace: "products" });

  return (
    <section
      aria-labelledby="related-products-heading"
      className="container mx-auto px-4 sm:px-6 lg:px-8 py-10"
    >
      <h2
        id="related-products-heading"
        className="text-lg font-medium text-gray-900 mb-6"
      >
        {t("relatedTitle")}
      </h2>
      <LazyProductCarousel
        products={related}
        basePath={basePath}
        currency={currency}
      />
    </section>
  );
}
