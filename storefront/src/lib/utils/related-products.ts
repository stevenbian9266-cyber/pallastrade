import type { Product, ProductListParams } from "@pallastrade/sdk";

/**
 * Rule-based related products (PRD-20260915-catalog-batch-c1-discovery FR-001).
 *
 * V1 intentionally skips a recommendation algorithm: same categories (their
 * descendants included), buyable now, newest first. We ask for one extra row so
 * `pickRelated` can drop the product the shopper is already looking at without
 * ending up one short.
 */
export const RELATED_PRODUCTS_LIMIT = 8;

export interface RelatedQueryOptions {
  limit?: number;
  sort?: string;
}

export function buildRelatedQuery(
  categoryIds: string[],
  options: RelatedQueryOptions = {},
): ProductListParams {
  const { limit = RELATED_PRODUCTS_LIMIT, sort = "-available_on" } = options;

  return {
    in_categories: categoryIds,
    in_stock: true,
    limit: limit + 1,
    sort,
  };
}

/** Category ids of a product, de-duplicated and blank-free. */
export function categoryIdsFor(
  product: Pick<Product, "categories"> | null | undefined,
): string[] {
  const categories = product?.categories ?? [];
  return [
    ...new Set(categories.map((category) => category.id).filter(Boolean)),
  ];
}

/**
 * Drops the products a shopper should not see twice (the one on screen) and
 * trims the over-fetch back to the requested limit.
 */
export function pickRelated(
  products: Product[],
  options: {
    excludeIds?: (string | number | null | undefined)[];
    limit?: number;
  } = {},
): Product[] {
  const { excludeIds = [], limit = RELATED_PRODUCTS_LIMIT } = options;
  const excluded = new Set(
    excludeIds.filter((id): id is string | number => id != null).map(String),
  );

  return products
    .filter((product) => !excluded.has(String(product.id)))
    .slice(0, limit);
}
