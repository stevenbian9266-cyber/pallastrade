import type { Product, ShippingEstimate } from "@pallastrade/sdk";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  buildProductJsonLd,
  buildWebsiteJsonLd,
  type MerchantReturnPolicyTerms,
} from "@/lib/seo";

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

// # PRD-20260917-catalog-json-ld-phase2 AC-001 AC-002 AC-003 AC-004 AC-005
// # PRD-20260917-catalog-json-ld-phase2 AC-006 AC-008 AC-009 AC-010 AC-011 AC-012
describe("buildProductJsonLd — JSON-LD phase 2", () => {
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

  const estimate = (overrides: Record<string, unknown> = {}) =>
    ({
      available: true,
      digital: false,
      min_days: 3,
      max_days: 7,
      free_shipping: false,
      free_shipping_threshold: null,
      methods: [],
      ...overrides,
    }) as unknown as ShippingEstimate;

  const terms = (
    overrides: Partial<MerchantReturnPolicyTerms> = {},
  ): MerchantReturnPolicyTerms => ({
    category: "finite_window",
    days: 30,
    method: "by_mail",
    fees: "free",
    countries: ["US"],
    ...overrides,
  });

  const offersOf = (schema: Record<string, unknown>) =>
    schema.offers as Record<string, unknown>;

  const futureIso = new Date(Date.now() + 30 * 24 * 3600 * 1000).toISOString();

  beforeEach(() => {
    vi.stubEnv("NEXT_PUBLIC_SITE_URL", "https://shop.example.com");
    vi.stubEnv("NEXT_PUBLIC_STORE_NAME", "Pallastrade Shop");
    vi.stubEnv("NEXT_PUBLIC_DEFAULT_COUNTRY", "us");
  });

  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it("exposes the seller from store config (AC-001)", () => {
    expect(buildProductJsonLd(product(), url).seller).toEqual({
      "@type": "Organization",
      name: "Pallastrade Shop",
      url: "https://shop.example.com",
    });
  });

  it("omits the seller when the storefront URL is unconfigured (AC-001)", () => {
    vi.stubEnv("NEXT_PUBLIC_SITE_URL", "");
    vi.stubEnv("NEXT_PUBLIC_VERCEL_PROJECT_PRODUCTION_URL", "");

    expect("seller" in buildProductJsonLd(product(), url)).toBe(false);
  });

  it("emits priceValidUntil from the applied price list window (AC-002)", () => {
    const schema = buildProductJsonLd(
      product({
        price: {
          amount: "20.0",
          currency: "USD",
          price_list_ends_at: futureIso,
        },
      } as unknown as Partial<Product>),
      url,
    );

    expect(offersOf(schema).priceValidUntil).toBe(futureIso.slice(0, 10));
  });

  it("omits priceValidUntil when no price list applies (AC-002)", () => {
    expect(
      "priceValidUntil" in offersOf(buildProductJsonLd(product(), url)),
    ).toBe(false);
  });

  it("omits priceValidUntil once the window has closed (AC-002)", () => {
    const past = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
    const schema = buildProductJsonLd(
      product({
        price: { amount: "20.0", currency: "USD", price_list_ends_at: past },
      } as unknown as Partial<Product>),
      url,
    );

    expect("priceValidUntil" in offersOf(schema)).toBe(false);
  });

  it("maps the already-fetched estimate into shippingDetails (AC-003)", () => {
    const schema = buildProductJsonLd(product(), url, {
      shippingEstimate: estimate({ free_shipping: true }),
      country: "us",
    });
    const details = offersOf(schema).shippingDetails as Record<string, unknown>;

    expect(details["@type"]).toBe("OfferShippingDetails");
    expect(details.shippingRate).toEqual({
      "@type": "MonetaryAmount",
      value: "0",
      currency: "USD",
    });
    expect(details.shippingDestination).toEqual({
      "@type": "DefinedRegion",
      addressCountry: "US",
    });

    const transit = (
      details.deliveryTime as { transitTime: Record<string, unknown> }
    ).transitTime;
    expect(transit.minValue).toBe(3);
    expect(transit.maxValue).toBe(7);
    expect(transit.unitCode).toBe("DAY");
  });

  it("does not claim a shipping rate unless it is known to be free (AC-003)", () => {
    const schema = buildProductJsonLd(product(), url, {
      shippingEstimate: estimate({ free_shipping: false }),
      country: "us",
    });
    const details = offersOf(schema).shippingDetails as Record<string, unknown>;

    // API 给的是本地化展示串（如 "$5.00"），解析它等于猜 —— 宁可不写这个数字。
    expect("shippingRate" in details).toBe(false);
  });

  it("omits shippingDetails for digital goods (AC-004)", () => {
    const schema = buildProductJsonLd(product(), url, {
      shippingEstimate: estimate({ digital: true, available: false }),
      country: "us",
    });

    expect("shippingDetails" in offersOf(schema)).toBe(false);
  });

  it("omits shippingDetails when the estimate call failed (AC-004)", () => {
    const schema = buildProductJsonLd(product(), url, {
      shippingEstimate: null,
      country: "us",
    });

    expect("shippingDetails" in offersOf(schema)).toBe(false);
  });

  it("attaches both fields to the AggregateOffer branch too (AC-005)", () => {
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
        in_stock: true,
        purchasable: true,
        preorder: false,
        backorderable: false,
      },
    ] as unknown as Product["variants"];

    const schema = buildProductJsonLd(product({ variants }), url, {
      shippingEstimate: estimate({ free_shipping: true }),
      country: "us",
      returnPolicy: terms(),
      returnPolicyUrl: `${url}/returns`,
    });

    expect(offersOf(schema)["@type"]).toBe("AggregateOffer");
    expect("shippingDetails" in offersOf(schema)).toBe(true);
    expect("hasMerchantReturnPolicy" in offersOf(schema)).toBe(true);
  });

  it("omits every phase-2 key when no data is available (AC-006)", () => {
    const offers = offersOf(buildProductJsonLd(product(), url));

    expect("priceValidUntil" in offers).toBe(false);
    expect("shippingDetails" in offers).toBe(false);
    expect("hasMerchantReturnPolicy" in offers).toBe(false);
  });

  it("omits hasMerchantReturnPolicy when the policy has no terms (AC-009)", () => {
    const schema = buildProductJsonLd(product(), url, { returnPolicy: null });

    expect("hasMerchantReturnPolicy" in offersOf(schema)).toBe(false);
  });

  it("omits a finite-window policy that carries no days (AC-010)", () => {
    const schema = buildProductJsonLd(product(), url, {
      returnPolicy: terms({ days: null }),
    });

    // 一条「有限窗口但没说多少天」的残缺政策比不输出更糟（会被判为结构化数据错误）。
    expect("hasMerchantReturnPolicy" in offersOf(schema)).toBe(false);
  });

  it("maps the structured return terms to schema.org (AC-011)", () => {
    const schema = buildProductJsonLd(product(), url, {
      returnPolicy: terms(),
      returnPolicyUrl: `${url}/returns`,
    });
    const policy = offersOf(schema).hasMerchantReturnPolicy as Record<
      string,
      unknown
    >;

    expect(policy["@type"]).toBe("MerchantReturnPolicy");
    expect(policy.returnPolicyCategory).toBe(
      "https://schema.org/MerchantReturnFiniteReturnWindow",
    );
    expect(policy.merchantReturnDays).toBe(30);
    expect(policy.returnMethod).toBe("https://schema.org/ReturnByMail");
    expect(policy.returnFees).toBe("https://schema.org/FreeReturn");
    expect(policy.applicableCountry).toBe("US");
    expect(policy.url).toBe(`${url}/returns`);
  });

  it("falls back to the store default country when none is configured (AC-012)", () => {
    const schema = buildProductJsonLd(product(), url, {
      returnPolicy: terms({ countries: [] }),
    });
    const policy = offersOf(schema).hasMerchantReturnPolicy as Record<
      string,
      unknown
    >;

    expect(policy.applicableCountry).toBe("US");
  });

  it("never emits merchantReturnDays outside a finite window (AC-011)", () => {
    const schema = buildProductJsonLd(product(), url, {
      returnPolicy: terms({ category: "unlimited_window" }),
    });
    const policy = offersOf(schema).hasMerchantReturnPolicy as Record<
      string,
      unknown
    >;

    expect(policy.returnPolicyCategory).toBe(
      "https://schema.org/MerchantReturnUnlimitedWindow",
    );
    expect("merchantReturnDays" in policy).toBe(false);
  });

  it("stays parseable and exposes no bare angle brackets (AC-008)", () => {
    const schema = buildProductJsonLd(
      product({ name: "Shirt <script>alert(1)</script>" }),
      url,
      {
        shippingEstimate: estimate(),
        country: "us",
        returnPolicy: terms(),
        returnPolicyUrl: url,
      },
    );

    // 与 `components/seo/JsonLd.tsx` 相同的转义方式。
    const serialized = JSON.stringify(schema).replaceAll("<", "\\u003c");

    expect(serialized).not.toContain("<");
    expect(() => JSON.parse(serialized)).not.toThrow();
  });
});
