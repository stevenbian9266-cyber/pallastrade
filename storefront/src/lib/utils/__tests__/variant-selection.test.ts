import type { Product, Variant } from "@pallastrade/sdk";
import { describe, expect, it, vi } from "vitest";
import {
  type AvailabilityFlags,
  type AvailabilityState,
  aggregateAvailability,
  applyVariantDeepLink,
  availabilityFlagsForProduct,
  availabilityFlagsForVariant,
  buildVariantHref,
  deriveAvailabilityState,
  resolveInitialVariant,
} from "@/lib/utils/variant-selection";

function variant(id: string, overrides: Partial<Variant> = {}): Variant {
  return {
    id,
    purchasable: false,
    in_stock: false,
    backorderable: false,
    preorder: false,
    ...overrides,
  } as Variant;
}

function product(overrides: Partial<Product> = {}): Product {
  return {
    id: "prod_1",
    name: "Shirt",
    slug: "shirt",
    ...overrides,
  } as Product;
}

// # PRD-20260915-catalog-pdp-state-correctness AC-001 AC-002
describe("resolveInitialVariant", () => {
  it("selects the deep-linked variant when the id is valid (AC-001)", () => {
    const first = variant("variant_1");
    const second = variant("variant_2");
    const resolved = resolveInitialVariant(
      product({ variants: [first, second] }),
      "variant_2",
    );
    expect(resolved?.id).toBe("variant_2");
  });

  it("accepts the default variant id from the URL (AC-001)", () => {
    const master = variant("variant_master");
    const resolved = resolveInitialVariant(
      product({ variants: [], default_variant: master }),
      "variant_master",
    );
    expect(resolved?.id).toBe("variant_master");
  });

  it("falls back to the default variant on an unknown id (AC-002)", () => {
    const master = variant("variant_master");
    const resolved = resolveInitialVariant(
      product({ variants: [variant("variant_1")], default_variant: master }),
      "variant_gone",
    );
    expect(resolved?.id).toBe("variant_master");
  });

  it("falls back to the first purchasable variant, then the first (AC-002)", () => {
    const soldOut = variant("variant_1");
    const purchasable = variant("variant_2", { purchasable: true });
    expect(
      resolveInitialVariant(product({ variants: [soldOut, purchasable] }), null)
        ?.id,
    ).toBe("variant_2");
    expect(
      resolveInitialVariant(product({ variants: [soldOut] }), null)?.id,
    ).toBe("variant_1");
  });

  it("returns null when the product has no variants at all", () => {
    expect(resolveInitialVariant(product(), undefined)).toBeNull();
  });
});

// # PRD-20260915-catalog-pdp-state-correctness AC-008
describe("deriveAvailabilityState", () => {
  const cases: Array<[string, AvailabilityFlags, AvailabilityState]> = [
    [
      "in stock wins over pre-order/backorder",
      { inStock: true, purchasable: true, preorder: true, backorderable: true },
      "in_stock",
    ],
    [
      "purchasable pre-order",
      {
        inStock: false,
        purchasable: true,
        preorder: true,
        backorderable: false,
      },
      "preorder",
    ],
    [
      "purchasable backorder",
      {
        inStock: false,
        purchasable: true,
        preorder: false,
        backorderable: true,
      },
      "backorder",
    ],
    [
      "pre-order allowance exhausted",
      {
        inStock: false,
        purchasable: false,
        preorder: true,
        backorderable: false,
      },
      "out_of_stock",
    ],
    [
      "not purchasable at all",
      {
        inStock: false,
        purchasable: false,
        preorder: false,
        backorderable: false,
      },
      "out_of_stock",
    ],
  ];

  it.each(cases)("%s → %s", (_label, flags, expected) => {
    expect(deriveAvailabilityState(flags)).toBe(expected);
  });
});

// # PRD-20260915-catalog-pdp-state-correctness AC-010
describe("aggregateAvailability", () => {
  it("prefers the most favourable state across variants", () => {
    expect(
      aggregateAvailability(["out_of_stock", "preorder", "in_stock"]),
    ).toBe("in_stock");
    expect(aggregateAvailability(["out_of_stock", "backorder"])).toBe(
      "backorder",
    );
    expect(aggregateAvailability(["out_of_stock"])).toBe("out_of_stock");
    expect(aggregateAvailability([])).toBe("out_of_stock");
  });
});

// # PRD-20260915-catalog-pdp-state-correctness AC-008
describe("availability flag mapping", () => {
  it("maps variant flags to availability inputs", () => {
    expect(
      availabilityFlagsForVariant(
        variant("v", {
          in_stock: true,
          purchasable: true,
          preorder: false,
          backorderable: true,
        }),
      ),
    ).toEqual({
      inStock: true,
      purchasable: true,
      preorder: false,
      backorderable: true,
    });
  });

  it("maps product flags with false fallbacks", () => {
    expect(availabilityFlagsForProduct(product())).toEqual({
      inStock: false,
      purchasable: false,
      preorder: false,
      backorderable: false,
    });
  });
});

// # PRD-20260915-catalog-pdp-state-correctness AC-003
describe("applyVariantDeepLink", () => {
  it("replaces the URL with the variant href", () => {
    const replace = vi.fn();
    applyVariantDeepLink("/us/en/products/shirt", "variant_2", replace);
    expect(replace).toHaveBeenCalledWith(
      "/us/en/products/shirt?variant=variant_2",
    );
  });

  it("is a no-op without a variant id", () => {
    const replace = vi.fn();
    applyVariantDeepLink("/us/en/products/shirt", null, replace);
    expect(replace).not.toHaveBeenCalled();
  });
});

// # PRD-20260915-catalog-pdp-state-correctness AC-003
describe("buildVariantHref", () => {
  it("sets the variant param and preserves other query params", () => {
    expect(
      buildVariantHref(
        "/us/en/products/shirt",
        "?category_id=ctg_1",
        "variant_2",
      ),
    ).toBe("/us/en/products/shirt?category_id=ctg_1&variant=variant_2");
  });

  it("replaces an existing variant param", () => {
    expect(
      buildVariantHref(
        "/us/en/products/shirt",
        "?variant=variant_1",
        "variant_2",
      ),
    ).toBe("/us/en/products/shirt?variant=variant_2");
  });

  it("drops the param when the variant is cleared", () => {
    expect(
      buildVariantHref(
        "/us/en/products/shirt",
        "?variant=variant_1&category_id=ctg_1",
        null,
      ),
    ).toBe("/us/en/products/shirt?category_id=ctg_1");
    expect(buildVariantHref("/us/en/products/shirt", "", null)).toBe(
      "/us/en/products/shirt",
    );
  });
});
