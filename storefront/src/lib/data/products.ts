"use server";

import type { Product, ProductListParams } from "@pallastrade/sdk";
import { cacheLife, cacheTag } from "next/cache";
import { PRODUCT_CARD_FIELDS } from "@/lib/data/cached";
import { getAccessToken, getClient, getLocaleOptions } from "@/lib/pallastrade";
import { buildRelatedQuery, pickRelated } from "@/lib/utils/related-products";

/**
 * Cached product list fetch. Cache key is derived from all function
 * arguments by Next.js "use cache":
 *
 * - locale/country: determines language and market-specific pricing
 * - userToken: per-user cache segmentation (separate arg, NOT passed to
 *   SDK). Authenticated users may see different prices (B2B, loyalty).
 *   Each user's JWT is unique so the cache is segmented per user.
 *   Guest users pass undefined.
 */
export async function cachedListProducts(
  params: ProductListParams | undefined,
  options: { locale?: string; country?: string },
  _userToken?: string,
) {
  "use cache: remote";
  cacheLife("tenMinutes");
  cacheTag("products");
  return getClient().products.list(params, options);
}

export async function getProducts(params?: ProductListParams) {
  const options = await getLocaleOptions();
  const userToken = await getAccessToken();
  return cachedListProducts(params, options, userToken);
}

/**
 * Related products rail (PRD-20260915-catalog-batch-c1-discovery FR-001):
 * rule-based, no algorithm — same categories, buyable now, and never the product
 * the shopper is looking at. Shares the cached list fetch (and its cache tag).
 */
export async function getRelatedProducts(params: {
  categoryIds: string[];
  excludeProductId?: string | number;
  limit?: number;
  locale?: string;
  country?: string;
}): Promise<Product[]> {
  if (params.categoryIds.length === 0) return [];

  const options =
    params.locale && params.country
      ? { locale: params.locale, country: params.country }
      : await getLocaleOptions();
  const userToken = await getAccessToken();

  const response = await cachedListProducts(
    {
      ...buildRelatedQuery(params.categoryIds, { limit: params.limit }),
      fields: PRODUCT_CARD_FIELDS,
    },
    options,
    userToken,
  );

  return pickRelated(response.data ?? [], {
    excludeIds: [params.excludeProductId],
    limit: params.limit,
  });
}

/**
 * Persistent cached product detail fetch. Cache key is derived from:
 *
 * - slugOrId, expand: identify the product and response shape
 * - locale/country: determines language and market-specific pricing
 * - userToken: per-user cache segmentation (separate arg, NOT passed to
 *   SDK). Authenticated users may see different prices (B2B, loyalty).
 *   Guest users pass undefined, so all guests share one entry.
 */
export async function cachedGetProduct(
  slugOrId: string,
  expand: string[],
  options: { locale?: string; country?: string },
  _userToken?: string,
) {
  "use cache: remote";
  cacheLife("tenMinutes");
  cacheTag("products", `product:${slugOrId}`);
  return getClient().products.get(slugOrId, { expand }, options);
}

export async function getProduct(
  slugOrId: string,
  params?: { expand?: string[] },
) {
  const options = await getLocaleOptions();
  const userToken = await getAccessToken();
  return cachedGetProduct(slugOrId, params?.expand ?? [], options, userToken);
}

async function cachedGetProductFilters(
  params: Record<string, unknown> | undefined,
  options: { locale?: string; country?: string },
  _userToken?: string,
) {
  "use cache: remote";
  cacheLife("tenMinutes");
  cacheTag("product-filters");
  return getClient().products.filters(params, options);
}

export async function getProductFilters(params?: Record<string, unknown>) {
  const options = await getLocaleOptions();
  const userToken = await getAccessToken();
  return cachedGetProductFilters(params, options, userToken);
}
