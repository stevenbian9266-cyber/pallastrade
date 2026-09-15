import type { Product } from "@pallastrade/sdk";
import { describe, expect, it } from "vitest";
import { buildProductJsonLd, buildWebsiteJsonLd } from "@/lib/seo";

// # PRD-20260810-storefront-对商城前台进行重新规划 AC-112
describe("buildWebsiteJsonLd", () => {
  it("builds a WebSite schema with a SearchAction pointing at the search endpoint", () => {
    const schema = buildWebsiteJsonLd(
      "https://pallastrade.cn",
      "https://pallastrade.cn/us/en/products",
    );

    expect(schema["@type"]).toBe("WebSite");
    expect(schema.url).toBe("https://pallastrade.cn");

    const action = schema.potentialAction as Record<string, unknown>;
    expect(action["@type"]).toBe("SearchAction");
    const target = action.target as Record<string, unknown>;
    expect(target.urlTemplate).toBe(
      "https://pallastrade.cn/us/en/products?q={search_term_string}",
    );
    expect(action["query-input"]).toBe("required name=search_term_string");
  });
});

// # PRD-20260915-catalog-pdp-state-correctness AC-009 AC-010 AC-011
describe("buildProductJsonLd", () => {
  const url = "https://shop.example.com/us/en/products/shirt";

  const product = (overrides: Partial<Product> = {}): Product =>
    ({
      id: "prod_1",
      name: "Shirt",
      slug: "shirt",
      description: null,
      price: { amount: "20.0", currency: "USD" },
      in_stock: true,
      purchasable: true,
      preorder: false,
      backorderable: false,
      media: [],
      thumbnail_url: null,
      ...overrides,
    }) as unknown as Product;

  it("keeps a plain Offer for single-SKU products (AC-009)", () => {
    const schema = buildProductJsonLd(product(), url);
    const offers = schema.offers as Record<string, unknown>;
    expect(offers["@type"]).toBe("Offer");
    expect(offers.price).toBe("20.0");
    expect(offers.availability).toBe("https://schema.org/InStock");
  });

  it("builds an AggregateOffer price range for multi-SKU products (AC-009)", () => {
    const variants = [
      {
        id: "variant_1",
        price: { amount: "20.0", currency: "USD" },
        in_stock: true,
        purchasable: true,
        preorder: false,
        backorderable: false,
      },
      {
        id: "variant_2",
        price: { amount: "35.0", currency: "USD" },
        in_stock: false,
        purchasable: true,
        preorder: true,
        backorderable: false,
      },
    ] as unknown as Product["variants"];

    const schema = buildProductJsonLd(product({ variants }), url);
    const offers = schema.offers as Record<string, unknown>;
    expect(offers["@type"]).toBe("AggregateOffer");
    expect(offers.priceCurrency).toBe("USD");
    expect(offers.lowPrice).toBe(20);
    expect(offers.highPrice).toBe(35);
    expect(offers.offerCount).toBe(2);
    expect(offers.availability).toBe("https://schema.org/InStock");
  });

  it("maps single-SKU availability to PreOrder (AC-010)", () => {
    const schema = buildProductJsonLd(
      product({ in_stock: false, purchasable: true, preorder: true }),
      url,
    );
    expect((schema.offers as Record<string, unknown>).availability).toBe(
      "https://schema.org/PreOrder",
    );
  });

  it("maps multi-SKU availability to the most favourable state (AC-010)", () => {
    const variants = [
      {
        id: "variant_1",
        price: { amount: "20.0", currency: "USD" },
        in_stock: false,
        purchasable: true,
        preorder: false,
        backorderable: true,
      },
      {
        id: "variant_2",
        price: { amount: "25.0", currency: "USD" },
        in_stock: false,
        purchasable: false,
        preorder: false,
        backorderable: false,
      },
    ] as unknown as Product["variants"];

    const schema = buildProductJsonLd(product({ variants }), url);
    expect((schema.offers as Record<string, unknown>).availability).toBe(
      "https://schema.org/BackOrder",
    );
  });

  it("reads brand from a custom field and omits it when absent (AC-011)", () => {
    const withBrand = buildProductJsonLd(
      product({
        custom_fields: [
          {
            id: "cf_1",
            key: "catalog.brand",
            label: "Brand",
            value: "Acme",
            field_type: "short_text",
          },
        ],
      } as unknown as Partial<Product>),
      url,
    );
    expect((withBrand.brand as Record<string, unknown>).name).toBe("Acme");

    const withoutBrand = buildProductJsonLd(product(), url);
    expect(withoutBrand.brand).toBeUndefined();
  });
});
