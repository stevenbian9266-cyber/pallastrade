import type {
  Category,
  CustomField,
  Media,
  Product,
  ShippingEstimate,
  Variant,
} from "@pallastrade/sdk";
import {
  ensureProtocol,
  getDefaultCountry,
  getStoreName,
  getStoreUrl,
} from "@/lib/store";
import {
  type AvailabilityState,
  aggregateAvailability,
  availabilityFlagsForProduct,
  availabilityFlagsForVariant,
  deriveAvailabilityState,
} from "@/lib/utils/variant-selection";

/**
 * Default social image path (stored in public/).
 * Brand OG image 1200x630 — see docs/standards/logo.md.
 */
export const SOCIAL_IMAGE_PATH = "/pallastrade-og.png";

/**
 * Build a full canonical URL from a store URL and a relative path.
 */
export function buildCanonicalUrl(storeUrl: string, path: string): string {
  const base = ensureProtocol(storeUrl).replace(/\/$/, "");
  const cleanPath = path.startsWith("/") ? path : `/${path}`;
  return `${base}${cleanPath}`;
}

/**
 * Strip HTML tags from a string.
 */
export function stripHtml(html: string): string {
  return html.replace(/<[^>]*>/g, "").trim();
}

/** schema.org availability URL for a presentation state. */
const AVAILABILITY_URL: Record<AvailabilityState, string> = {
  in_stock: "https://schema.org/InStock",
  preorder: "https://schema.org/PreOrder",
  backorder: "https://schema.org/BackOrder",
  out_of_stock: "https://schema.org/OutOfStock",
};

function productAvailabilityState(product: Product): AvailabilityState {
  return deriveAvailabilityState(availabilityFlagsForProduct(product));
}

function variantAvailabilityState(variant: Variant): AvailabilityState {
  return deriveAvailabilityState(availabilityFlagsForVariant(variant));
}

/**
 * schema.org 枚举值映射（PRD-20260917-catalog-json-ld-phase2 FR-005）。
 *
 * API 下发的是**小写蛇形内部值**（`finite_window` 等）而不是 schema.org URI ——
 * 业务数据不该被硬编码成某个搜索引擎的词汇表；把词汇表留在展示层，
 * schema.org 改版时只改这里。
 */
const RETURN_POLICY_CATEGORY_URL: Record<string, string> = {
  not_permitted: "https://schema.org/MerchantReturnNotPermitted",
  finite_window: "https://schema.org/MerchantReturnFiniteReturnWindow",
  unlimited_window: "https://schema.org/MerchantReturnUnlimitedWindow",
};

const RETURN_POLICY_METHOD_URL: Record<string, string> = {
  by_mail: "https://schema.org/ReturnByMail",
  in_store: "https://schema.org/ReturnInStore",
};

const RETURN_POLICY_FEES_URL: Record<string, string> = {
  free: "https://schema.org/FreeReturn",
  customer_pays: "https://schema.org/ReturnShippingFees",
};

/** 结构化退货条款（来自退货政策的 `merchant_return_policy`）。 */
export interface MerchantReturnPolicyTerms {
  category: string;
  days: number | null;
  method: string | null;
  fees: string | null;
  countries: string[];
}

/**
 * `buildProductJsonLd` 的可选上下文。
 *
 * 全部可选：调用方没有这些数据时，对应字段就**不出现**在结构化数据里 ——
 * 宁可字段缺失，也不要发布一条编造的政策（会被判为结构化数据错误，比不输出更糟）。
 */
export interface ProductJsonLdContext {
  /** PDP 已经取到的运费估算（复用，不为此新增请求）。 */
  shippingEstimate?: ShippingEstimate | null;
  /** 访问者国家（ISO-2），用作 `shippingDestination`。 */
  country?: string | null;
  /** 退货政策上配置的结构化条款。 */
  returnPolicy?: MerchantReturnPolicyTerms | null;
  /** 退货政策在站内的完整地址，用作 `MerchantReturnPolicy.url`。 */
  returnPolicyUrl?: string | null;
}

/**
 * 价格的失效日期（`YYYY-MM-DD`）。
 *
 * 三种情况一律返回 `null`（即不输出 `priceValidUntil`）：
 *   1. 未命中价目表（回落默认价格）—— 没有「有效期」这个概念；
 *   2. 价目表没有时间窗；
 *   3. 时间窗已经过去 —— 搜索引擎只关心未来还成立的价格。
 */
function priceValidUntil(price: Product["price"]): string | null {
  const raw = price?.price_list_ends_at;
  if (!raw) return null;

  const endsAt = new Date(raw);
  if (Number.isNaN(endsAt.getTime())) return null;
  if (endsAt.getTime() < Date.now()) return null;

  return endsAt.toISOString().slice(0, 10);
}

/** `OfferShippingDetails`（运费 + 目的地 + 时效）。 */
interface OfferShippingDetails {
  "@type": "OfferShippingDetails";
  shippingRate?: { "@type": "MonetaryAmount"; value: string; currency: string };
  shippingDestination?: { "@type": "DefinedRegion"; addressCountry: string };
  deliveryTime?: {
    "@type": "ShippingDeliveryTime";
    transitTime: {
      "@type": "QuantitativeValue";
      minValue: number;
      maxValue: number;
      unitCode: "DAY";
    };
  };
}

/**
 * 把 PDP 的运费估算映射成 schema.org `shippingDetails`（FR-003）。
 *
 * **数字商品与不可用估算一律返回 null** —— 给数字商品承诺运费是错的。
 *
 * 关于 `shippingRate`：只有「确定免费」才写 0。API 给的估价是**本地化展示串**
 * （如 `"$5.00"`），解析它等于猜，猜错会给出一个错误的运费数字，比不写更糟；
 * 所以非免费时省略 `shippingRate`，只保留目的地与时效（两项都是结构化的数值）。
 */
function buildShippingDetails(
  estimate: ShippingEstimate | null | undefined,
  country: string | null | undefined,
  currency: string | null | undefined,
): OfferShippingDetails | null {
  if (!estimate || estimate.digital || !estimate.available) return null;

  const details: OfferShippingDetails = { "@type": "OfferShippingDetails" };

  if (estimate.free_shipping && currency) {
    details.shippingRate = {
      "@type": "MonetaryAmount",
      value: "0",
      currency,
    };
  }

  const destination = country?.trim().toUpperCase();
  if (destination) {
    details.shippingDestination = {
      "@type": "DefinedRegion",
      addressCountry: destination,
    };
  }

  const minDays = estimate.min_days;
  const maxDays = estimate.max_days ?? estimate.min_days;
  if (typeof minDays === "number" && typeof maxDays === "number") {
    details.deliveryTime = {
      "@type": "ShippingDeliveryTime",
      transitTime: {
        "@type": "QuantitativeValue",
        minValue: minDays,
        maxValue: maxDays,
        unitCode: "DAY",
      },
    };
  }

  return details;
}

/** `MerchantReturnPolicy`。 */
interface MerchantReturnPolicy {
  "@type": "MerchantReturnPolicy";
  returnPolicyCategory: string;
  url?: string;
  merchantReturnDays?: number;
  returnMethod?: string;
  returnFees?: string;
  applicableCountry?: string | string[];
}

/**
 * 把退货政策上的结构化条款映射成 schema.org `hasMerchantReturnPolicy`（FR-005）。
 *
 * 两道门槛，任一不满足就返回 null（整体省略）：
 *   1. **类目认不出** —— 与后端归一化同一原则：不认识就当作没填；
 *   2. **有限窗口却没天数** —— 这是一条**残缺政策**，会被搜索引擎判为
 *      结构化数据错误，比不输出更糟。
 *
 * `applicableCountry` 是 Google 的必填项：条款里没写就用门店的默认国家 ——
 * 那是商家在后台配过的值，不是我们猜的。
 */
function buildMerchantReturnPolicy(
  terms: MerchantReturnPolicyTerms | null | undefined,
  url: string | null | undefined,
): MerchantReturnPolicy | null {
  if (!terms) return null;

  const category = RETURN_POLICY_CATEGORY_URL[terms.category];
  if (!category) return null;

  const days = terms.days ?? 0;
  if (terms.category === "finite_window" && days <= 0) return null;

  const policy: MerchantReturnPolicy = {
    "@type": "MerchantReturnPolicy",
    returnPolicyCategory: category,
  };

  if (url) policy.url = url;
  if (terms.category === "finite_window") policy.merchantReturnDays = days;

  const method = terms.method
    ? RETURN_POLICY_METHOD_URL[terms.method]
    : undefined;
  if (method) policy.returnMethod = method;

  const fees = terms.fees ? RETURN_POLICY_FEES_URL[terms.fees] : undefined;
  if (fees) policy.returnFees = fees;

  const countries = (terms.countries ?? [])
    .map((code) => code.trim().toUpperCase())
    .filter(Boolean);
  const applicable =
    countries.length > 0 ? countries : [getDefaultCountry().toUpperCase()];

  if (applicable.length > 0) {
    policy.applicableCountry =
      applicable.length === 1 ? applicable[0] : applicable;
  }

  return policy;
}

/**
 * Brand comes from a merchant-managed custom field while there is no Brand
 * model — `catalog.brand` / `brand` / `*.brand` keys, or a field labelled
 * "brand". Missing → omitted from the schema (never invent a value).
 */
function findBrandName(product: Product): string | null {
  const fields = (product.custom_fields || []) as CustomField[];
  const field = fields.find((candidate) => {
    const key = candidate.key?.toLowerCase() ?? "";
    return (
      key === "brand" ||
      key === "catalog.brand" ||
      key.endsWith(".brand") ||
      candidate.label?.trim().toLowerCase() === "brand"
    );
  });
  const value = field?.value;
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

/**
 * Build JSON-LD Product schema.
 * https://schema.org/Product
 */
export function buildProductJsonLd(
  product: Product,
  canonicalUrl: string,
  context: ProductJsonLdContext = {},
): Record<string, unknown> {
  const schema: Record<string, unknown> = {
    "@context": "https://schema.org",
    "@type": "Product",
    name: product.name,
    url: canonicalUrl,
  };

  if (product.description) {
    schema.description = stripHtml(product.description);
  }

  if (product.default_variant?.sku) {
    schema.sku = product.default_variant.sku;
  }

  const imageUrls = (product.media || [])
    .map((img: Media) => img.original_url || img.large_url)
    .filter(Boolean);
  // Fall back to thumbnail_url if no media from expand
  if (imageUrls.length === 0 && product.thumbnail_url) {
    imageUrls.push(product.thumbnail_url);
  }
  if (imageUrls.length > 0) {
    schema.image = imageUrls;
  }

  // Offers (PRD-20260915-catalog-pdp-state-correctness AC-009/AC-010): a
  // single SKU keeps a plain Offer; multi-SKU products expose the price range
  // via AggregateOffer with the most favourable availability across variants.
  const variants = (product.variants || []).filter(Boolean);
  const variantAmounts = variants
    .map((variant) => variant.price?.amount)
    .filter((amount): amount is string => amount != null)
    .map((amount) => Number.parseFloat(amount))
    .filter((amount) => Number.isFinite(amount));

  // 第二阶段字段（PRD-20260917-catalog-json-ld-phase2 FR-002/FR-003/FR-005）。
  // 两个报价分支共享同一份，保证 AggregateOffer 与 Offer 口径一致（AC-005）；
  // 每一项都可能缺失，**缺失就整项不出现**，不是输出 null。
  const validUntil = priceValidUntil(product.price);
  const shippingDetails = buildShippingDetails(
    context.shippingEstimate,
    context.country,
    product.price?.currency,
  );
  const merchantReturnPolicy = buildMerchantReturnPolicy(
    context.returnPolicy,
    context.returnPolicyUrl,
  );

  const offerExtras = {
    ...(validUntil ? { priceValidUntil: validUntil } : {}),
    ...(shippingDetails ? { shippingDetails } : {}),
    ...(merchantReturnPolicy
      ? { hasMerchantReturnPolicy: merchantReturnPolicy }
      : {}),
  };

  if (
    variants.length > 1 &&
    variantAmounts.length > 0 &&
    product.price?.currency
  ) {
    schema.offers = {
      "@type": "AggregateOffer",
      url: canonicalUrl,
      priceCurrency: product.price.currency,
      lowPrice: Math.min(...variantAmounts),
      highPrice: Math.max(...variantAmounts),
      offerCount: variants.length,
      availability:
        AVAILABILITY_URL[
          aggregateAvailability(variants.map(variantAvailabilityState))
        ],
      ...offerExtras,
    };
  } else if (product.price?.amount && product.price?.currency) {
    schema.offers = {
      "@type": "Offer",
      url: canonicalUrl,
      priceCurrency: product.price.currency,
      price: product.price.amount,
      availability: AVAILABILITY_URL[productAvailabilityState(product)],
      ...offerExtras,
    };
  }

  // Brand from a custom field (FR-003 / AC-011).
  const brandName = findBrandName(product);
  if (brandName) {
    schema.brand = { "@type": "Brand", name: brandName };
  }

  // 谁在卖（FR-001）。门店 URL 在生产环境未配置时为 undefined ——
  // 与其给一个编不出来的地址，不如不输出 `seller`。
  const sellerName = getStoreName().trim();
  const sellerUrl = getStoreUrl();
  if (sellerName && sellerUrl) {
    schema.seller = {
      "@type": "Organization",
      name: sellerName,
      url: sellerUrl,
    };
  }

  // P0-4: aggregate rating over approved reviews (only when there is at
  // least one approved review; rejected/pending reviews are excluded).
  if (product.average_rating != null && (product.review_count ?? 0) > 0) {
    schema.aggregateRating = {
      "@type": "AggregateRating",
      ratingValue: product.average_rating,
      reviewCount: product.review_count,
      bestRating: 5,
    };
  }

  return schema;
}

/**
 * Build JSON-LD BreadcrumbList schema from a category with ancestors.
 * https://schema.org/BreadcrumbList
 */
export function buildBreadcrumbJsonLd(
  category: Category,
  basePath: string,
  storeUrl: string,
  product?: { name: string; slug: string },
): Record<string, unknown> {
  const items: Array<{ name: string; url: string }> = [
    { name: "Home", url: buildCanonicalUrl(storeUrl, basePath) },
  ];

  if (category.ancestors) {
    for (const ancestor of category.ancestors) {
      if (!ancestor.is_root) {
        items.push({
          name: ancestor.name,
          url: buildCanonicalUrl(
            storeUrl,
            `${basePath}/c/${ancestor.permalink}`,
          ),
        });
      }
    }
  }

  items.push({
    name: category.name,
    url: buildCanonicalUrl(storeUrl, `${basePath}/c/${category.permalink}`),
  });

  if (product) {
    items.push({
      name: product.name,
      url: buildCanonicalUrl(storeUrl, `${basePath}/products/${product.slug}`),
    });
  }

  return {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: items.map((item, index) => ({
      "@type": "ListItem",
      position: index + 1,
      name: item.name,
      item: item.url,
    })),
  };
}

/**
 * Build JSON-LD ItemList schema for a category page.
 * https://schema.org/ItemList
 */
export function buildCategoryItemListJsonLd(
  products: Array<{
    name: string;
    slug: string;
    thumbnail_url?: string | null;
  }>,
  categoryName: string,
  canonicalUrl: string,
): Record<string, unknown> {
  return {
    "@context": "https://schema.org",
    "@type": "ItemList",
    name: categoryName,
    url: canonicalUrl,
    numberOfItems: products.length,
    itemListElement: products.map((product, index) => ({
      "@type": "ListItem",
      position: index + 1,
      name: product.name,
      url: `${canonicalUrl.split("/c/")[0] || ""}/products/${product.slug}`,
      ...(product.thumbnail_url ? { image: product.thumbnail_url } : {}),
    })),
  };
}

/**
 * Build JSON-LD Organization schema from environment variables.
 * https://schema.org/Organization
 */
export function buildOrganizationJsonLd(): Record<string, unknown> {
  const storeName = getStoreName();
  const storeUrl = getStoreUrl();
  const logoUrl = process.env.STORE_LOGO_URL;
  const facebook = process.env.STORE_FACEBOOK;
  const twitter = process.env.STORE_TWITTER;
  const instagram = process.env.STORE_INSTAGRAM;
  const supportEmail = process.env.STORE_SUPPORT_EMAIL;

  const schema: Record<string, unknown> = {
    "@context": "https://schema.org",
    "@type": "Organization",
    name: storeName,
    ...(storeUrl ? { url: storeUrl } : {}),
  };

  if (logoUrl) {
    schema.logo = logoUrl;
  }

  const sameAs: string[] = [];
  if (facebook) sameAs.push(facebook);
  if (twitter) {
    sameAs.push(
      twitter.startsWith("http")
        ? twitter
        : `https://twitter.com/${twitter.replace("@", "")}`,
    );
  }
  if (instagram) {
    sameAs.push(
      instagram.startsWith("http")
        ? instagram
        : `https://instagram.com/${instagram.replace("@", "")}`,
    );
  }
  if (sameAs.length > 0) {
    schema.sameAs = sameAs;
  }

  if (supportEmail) {
    schema.contactPoint = {
      "@type": "ContactPoint",
      email: supportEmail,
      contactType: "customer service",
    };
  }

  return schema;
}

/**
 * Build JSON-LD WebSite schema with SearchAction (site search endpoint).
 * GEO/SEO: tells search + generative engines about the store's search
 * capability (PRD-20260810-storefront-... AC-112).
 * https://schema.org/WebSite
 */
export function buildWebsiteJsonLd(
  storeUrl: string,
  searchBaseUrl: string,
): Record<string, unknown> {
  return {
    "@context": "https://schema.org",
    "@type": "WebSite",
    name: getStoreName(),
    url: storeUrl,
    potentialAction: {
      "@type": "SearchAction",
      target: {
        "@type": "EntryPoint",
        urlTemplate: `${searchBaseUrl}?q={search_term_string}`,
      },
      "query-input": "required name=search_term_string",
    },
  };
}
