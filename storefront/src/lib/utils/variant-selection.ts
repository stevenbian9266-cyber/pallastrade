import type { Product, Variant } from "@pallastrade/sdk";

/**
 * PDP variant deep-link + availability helpers
 * (PRD-20260915-catalog-pdp-state-correctness).
 *
 * Kept as pure functions so the selection priority, the presentation state and
 * the URL construction are covered by table-driven unit tests.
 */

export type AvailabilityState =
  | "in_stock"
  | "preorder"
  | "backorder"
  | "out_of_stock";

export interface AvailabilityFlags {
  inStock: boolean;
  purchasable: boolean;
  preorder: boolean;
  backorderable: boolean;
}

/**
 * Presentation state priority (FR-002 / AC-008):
 * in stock > pre-order (oversell, carries a ship-by promise) > backorder
 * (oversell) > sold out.
 *
 * Pre-order/backorder only surface while the SKU is actually purchasable — a
 * pre-order whose oversell allowance ran out is presented as sold out.
 */
export function deriveAvailabilityState({
  inStock,
  purchasable,
  preorder,
  backorderable,
}: AvailabilityFlags): AvailabilityState {
  if (inStock) return "in_stock";
  if (purchasable && preorder) return "preorder";
  if (purchasable && backorderable) return "backorder";
  return "out_of_stock";
}

/**
 * Resolve the variant selected on first paint (FR-001 / AC-001 / AC-002).
 *
 * Priority: valid `?variant=` id → default variant → first purchasable variant
 * → first variant. Unknown ids fall back silently so stale/share links keep
 * working instead of erroring.
 */
export function resolveInitialVariant(
  product: Product,
  requestedVariantId?: string | null,
): Variant | null {
  const variants = (product.variants || []).filter(Boolean);
  const requested = requestedVariantId?.trim();

  if (requested) {
    const match = variants.find((variant) => variant.id === requested);
    if (match) return match;
    if (product.default_variant?.id === requested) {
      return product.default_variant;
    }
  }

  if (product.default_variant) return product.default_variant;
  if (variants.length > 0) {
    return variants.find((variant) => variant.purchasable) || variants[0];
  }
  return null;
}

/**
 * Build the PDP href with the `variant` deep-link param applied, preserving
 * every other query parameter already present on the page (FR-001 / AC-003).
 */
export function buildVariantHref(
  pathname: string,
  currentSearch: string,
  variantId: string | null,
): string {
  const params = new URLSearchParams(currentSearch);
  if (variantId) {
    params.set("variant", variantId);
  } else {
    params.delete("variant");
  }
  const query = params.toString();
  return query ? `${pathname}?${query}` : pathname;
}

/** Most favourable state across a variant set (FR-003 / AC-010). */
export function aggregateAvailability(
  states: AvailabilityState[],
): AvailabilityState {
  const priority: AvailabilityState[] = [
    "in_stock",
    "preorder",
    "backorder",
    "out_of_stock",
  ];
  return priority.find((state) => states.includes(state)) ?? "out_of_stock";
}

/** Availability flags for a specific variant (AC-008 input mapping). */
export function availabilityFlagsForVariant(
  variant: Variant,
): AvailabilityFlags {
  return {
    inStock: variant.in_stock ?? false,
    purchasable: variant.purchasable ?? false,
    preorder: variant.preorder ?? false,
    backorderable: variant.backorderable ?? false,
  };
}

/** Availability flags for a product without variants (AC-008 input mapping). */
export function availabilityFlagsForProduct(
  product: Product,
): AvailabilityFlags {
  return {
    inStock: product.in_stock ?? false,
    purchasable: product.purchasable ?? false,
    preorder: product.preorder ?? false,
    backorderable: product.backorderable ?? false,
  };
}

/**
 * Apply the selected SKU to the current URL (FR-001 / AC-003). No-op without a
 * variant id; the browser search string is read here so callers stay
 * guard-free.
 */
export function applyVariantDeepLink(
  pathname: string,
  variantId: string | null | undefined,
  replace: (href: string) => void,
): void {
  if (!variantId) return;
  const search = typeof window === "undefined" ? "" : window.location.search;
  replace(buildVariantHref(pathname, search, variantId));
}
