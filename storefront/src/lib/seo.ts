import type {
  Category,
  CustomField,
  Media,
  Product,
  Variant,
} from "@pallastrade/sdk";
import { ensureProtocol, getStoreName, getStoreUrl } from "@/lib/store";
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
    };
  } else if (product.price?.amount && product.price?.currency) {
    schema.offers = {
      "@type": "Offer",
      url: canonicalUrl,
      priceCurrency: product.price.currency,
      price: product.price.amount,
      availability: AVAILABILITY_URL[productAvailabilityState(product)],
    };
  }

  // Brand from a custom field (FR-003 / AC-011).
  const brandName = findBrandName(product);
  if (brandName) {
    schema.brand = { "@type": "Brand", name: brandName };
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
