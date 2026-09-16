import type { Category } from "@pallastrade/sdk";
import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { Breadcrumbs } from "@/components/navigation/Breadcrumbs";
import { RecentlyViewed } from "@/components/products/RecentlyViewed";
import { RecentlyViewedTracker } from "@/components/products/RecentlyViewedTracker";
import { RelatedProducts } from "@/components/products/RelatedProducts";
import { JsonLd } from "@/components/seo/JsonLd";
import { getCachedProduct, PRODUCT_PAGE_EXPAND } from "@/lib/data/cached";
import { isAuthenticated } from "@/lib/data/cookies";
import { getProductReviews } from "@/lib/data/reviews";
import { generateProductMetadata } from "@/lib/metadata/product";
import {
  buildBreadcrumbJsonLd,
  buildCanonicalUrl,
  buildProductJsonLd,
} from "@/lib/seo";
import { getStoreUrl } from "@/lib/store";
import { ProductDetails } from "./ProductDetails";

interface ProductPageProps {
  params: Promise<{
    country: string;
    locale: string;
    slug: string;
  }>;
  searchParams: Promise<{
    category_id?: string;
    variant?: string;
  }>;
}

export async function generateMetadata({
  params,
}: ProductPageProps): Promise<Metadata> {
  const { country, locale, slug } = await params;
  return generateProductMetadata({ country, locale, slug });
}

function findBreadcrumbCategory(
  categories: Category[],
  categoryId?: string,
): Category | undefined {
  if (categories.length === 0) return undefined;
  if (categoryId) {
    const match = categories.find((c) => c.id === categoryId);
    if (match) return match;
  }
  return categories[0];
}

export default async function ProductPage({
  params,
  searchParams,
}: ProductPageProps) {
  const { country, locale, slug } = await params;
  const { category_id, variant } = await searchParams;
  const basePath = `/${country}/${locale}`;

  let product;
  try {
    product = await getCachedProduct(slug, PRODUCT_PAGE_EXPAND);
  } catch {
    notFound();
  }

  const storeUrl = getStoreUrl();
  const canonicalUrl = storeUrl
    ? buildCanonicalUrl(
        storeUrl,
        `/${country}/${locale}/products/${product.slug}`,
      )
    : undefined;

  const breadcrumbCategory = findBreadcrumbCategory(
    product.categories || [],
    category_id,
  );

  // P0-4 / F-1: approved reviews (first page + rating distribution) + auth state.
  const [reviewList, authenticated] = await Promise.all([
    getProductReviews(product.id),
    isAuthenticated(),
  ]);

  return (
    <>
      {canonicalUrl && (
        <JsonLd data={buildProductJsonLd(product, canonicalUrl)} />
      )}
      {breadcrumbCategory && storeUrl && (
        <JsonLd
          data={buildBreadcrumbJsonLd(breadcrumbCategory, basePath, storeUrl, {
            name: product.name,
            slug: product.slug,
          })}
        />
      )}
      <div className="container mx-auto px-4 sm:px-6 lg:px-8 pt-6">
        {breadcrumbCategory && (
          <Breadcrumbs
            category={breadcrumbCategory}
            basePath={basePath}
            productName={product.name}
            locale={locale}
          />
        )}
      </div>
      <ProductDetails
        product={product}
        basePath={basePath}
        initialVariantId={variant ?? null}
        reviews={reviewList.reviews}
        reviewMeta={reviewList.meta}
        averageRating={product.average_rating ?? null}
        reviewCount={product.review_count ?? 0}
        isAuthenticated={authenticated}
      />

      {/* Discovery rails (PRD-20260915-catalog-batch-c1-discovery) */}
      <RecentlyViewedTracker product={product} />
      <RelatedProducts
        product={product}
        basePath={basePath}
        locale={locale as Locale}
        country={country}
        currency={product.price?.currency ?? undefined}
      />
      <RecentlyViewed
        basePath={basePath}
        currentProductId={product.id}
        currency={product.price?.currency ?? undefined}
      />
    </>
  );
}
