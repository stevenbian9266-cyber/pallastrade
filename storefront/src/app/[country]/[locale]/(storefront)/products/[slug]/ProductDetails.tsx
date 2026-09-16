"use client";

import type {
  Media,
  Product,
  ShippingEstimate as ShippingEstimateData,
  Variant,
} from "@pallastrade/sdk";
import { Loader2, ShoppingBag } from "lucide-react";
import { usePathname, useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useCallback, useEffect, useMemo, useState } from "react";
import { AvailabilityStatus } from "@/components/products/AvailabilityStatus";
import { BackInStockNotify } from "@/components/products/BackInStockNotify";
import { BuyNowButton } from "@/components/products/BuyNowButton";
import { MediaGallery } from "@/components/products/MediaGallery";
import { ProductCustomFields } from "@/components/products/ProductCustomFields";
import {
  ProductReviews,
  type ReviewMeta,
  type ReviewView,
} from "@/components/products/ProductReviews";
import { ShippingEstimate } from "@/components/products/ShippingEstimate";
import { VariantPicker } from "@/components/products/VariantPicker";
import { WishlistButton } from "@/components/products/WishlistButton";
import { Button } from "@/components/ui/button";
import { QuantityPicker } from "@/components/ui/quantity-picker";
import { useCart } from "@/contexts/CartContext";
import { useStore } from "@/contexts/StoreContext";
import { trackAddToCart, trackViewItem } from "@/lib/analytics/gtm";
import {
  applyVariantDeepLink,
  availabilityFlagsForProduct,
  availabilityFlagsForVariant,
  deriveAvailabilityState,
  resolveInitialVariant,
} from "@/lib/utils/variant-selection";

interface ProductDetailsProps {
  product: Product;
  basePath: string;
  /** Deep-link variant from the server (`?variant=`), if any. */
  initialVariantId?: string | null;
  reviews?: ReviewView[];
  /** F-1: first-page pagination + rating distribution from the API envelope. */
  reviewMeta?: ReviewMeta | null;
  averageRating?: number | null;
  reviewCount?: number;
  isAuthenticated?: boolean;
  /** Catalog F-2: advisory shipping window for the PDP block. */
  shippingEstimate?: ShippingEstimateData | null;
}

export function ProductDetails({
  product,
  basePath,
  initialVariantId = null,
  reviews = [],
  reviewMeta = null,
  averageRating = null,
  reviewCount = 0,
  isAuthenticated = false,
  shippingEstimate = null,
}: ProductDetailsProps) {
  const { addItem } = useCart();
  const { currency } = useStore();
  const t = useTranslations("products");
  const router = useRouter();
  const pathname = usePathname();

  // Filter variants list
  const variants = useMemo(() => {
    return (product.variants || []).filter(Boolean);
  }, [product.variants]);

  const hasVariants = variants.length > 0;
  const optionTypes = product.option_types || [];

  // Deep link (`?variant=`) wins over the default variant; unknown ids fall
  // back deterministically (PRD-20260915-catalog-pdp-state-correctness
  // AC-001 / AC-002).
  const [initialVariant] = useState<Variant | null>(() =>
    resolveInitialVariant(product, initialVariantId),
  );
  const [selectedVariant, setSelectedVariant] = useState<Variant | null>(
    initialVariant,
  );

  // Keep the URL in sync with the selected SKU so links stay shareable
  // (AC-003); other query params (e.g. category_id) are preserved.
  const handleVariantChange = useCallback(
    (variant: Variant | null) => {
      setSelectedVariant(variant);
      applyVariantDeepLink(pathname, variant?.id, (href) =>
        router.replace(href, { scroll: false }),
      );
    },
    [pathname, router],
  );

  const [quantity, setQuantity] = useState(1);
  const [loading, setLoading] = useState(false);

  // Track the view once per product with the variant the page was opened with
  // so GA4 `view_item` SKU matches the shared / advertised URL variant
  // (AC-004). Variant switches deliberately do not re-fire this event.
  useEffect(() => {
    trackViewItem(product, currency, initialVariant);
  }, [product, currency, initialVariant]);

  const galleryImages = useMemo((): Media[] => {
    return product.media || [];
  }, [product.media]);

  const variantImageIndex = useMemo((): number | null => {
    if (!selectedVariant) return null;
    const index = galleryImages.findIndex((m) =>
      m.variant_ids.includes(selectedVariant.id),
    );
    return index >= 0 ? index : null;
  }, [selectedVariant, galleryImages]);

  const price = selectedVariant?.price ?? product.price;
  const originalPrice =
    selectedVariant?.original_price ?? product.original_price;
  const displayPrice = price?.display_amount;
  // Catalog F-2: the selected SKU's bucket wins over the product's.
  const stockStatus =
    selectedVariant?.stock_status ?? product.stock_status ?? null;
  const currentAmountCents = price?.amount_in_cents;
  const originalAmountCents = originalPrice?.amount_in_cents;
  const compareAtAmountCents = price?.compare_at_amount_in_cents;
  const onSale =
    (currentAmountCents != null &&
      originalAmountCents != null &&
      currentAmountCents < originalAmountCents) ||
    (compareAtAmountCents != null &&
      currentAmountCents != null &&
      currentAmountCents < compareAtAmountCents);

  const strikethroughPrice = onSale
    ? ((originalPrice?.display_amount &&
      originalPrice.display_amount !== displayPrice
        ? originalPrice.display_amount
        : price?.display_compare_at_amount) ?? null)
    : null;

  // Purchasability
  const isPurchasable = hasVariants
    ? (selectedVariant?.purchasable ?? false)
    : (product.purchasable ?? false);

  // Availability presentation state — derived from the Store API flags only
  // (FR-002 / AC-008): in stock > pre-order > backorder > sold out.
  const availability = deriveAvailabilityState(
    hasVariants && selectedVariant
      ? availabilityFlagsForVariant(selectedVariant)
      : availabilityFlagsForProduct(product),
  );

  const preorderShipsAt = hasVariants
    ? selectedVariant?.preorder_ships_at
    : product.preorder_ships_at;

  const handleAddToCart = async () => {
    const variantId =
      selectedVariant?.id ||
      product.default_variant?.id ||
      product.default_variant_id;
    if (!variantId) {
      throw new Error("No variant selected");
    }

    setLoading(true);
    await addItem(variantId, quantity);
    setLoading(false);
    trackAddToCart(product, selectedVariant, quantity, currency);
  };

  return (
    <div className="container mx-auto px-4 sm:px-6 lg:px-8  py-8">
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-12">
        {/* Media Gallery */}
        <div>
          <MediaGallery
            images={galleryImages}
            productName={product.name}
            activeIndex={variantImageIndex}
          />
        </div>

        {/* Product Info */}
        <div>
          <h1 className="text-3xl font-bold text-gray-900">{product.name}</h1>

          {/* Price */}
          <div className="mt-4 flex items-center gap-4">
            {displayPrice && (
              <span className="text-3xl font-bold text-gray-900">
                {displayPrice}
              </span>
            )}
            {onSale && strikethroughPrice && (
              <>
                <span className="text-xl text-gray-500 line-through">
                  {strikethroughPrice}
                </span>
                <span className="bg-red-100 text-red-800 text-sm font-medium px-2.5 py-0.5 rounded">
                  {t("sale")}
                </span>
              </>
            )}
          </div>

          {/* Availability status + wishlist toggle. The toggle is a light
              secondary action (`outline` + `sm`) and lives with the stock line
              so it never squeezes Add to Cart / Buy Now out of their row. */}
          <div
            className="mt-4 flex items-center justify-between gap-4"
            data-testid="availability-row"
          >
            <AvailabilityStatus
              availability={availability}
              preorderShipsAt={preorderShipsAt}
              stockStatus={stockStatus}
            />
            <WishlistButton product={product} />
          </div>

          {/* Catalog F-2: shipping window straight under the price/stock row. */}
          <ShippingEstimate estimate={shippingEstimate ?? null} />

          {/* Back-in-stock notification — only when the item cannot be bought.
              Pre-order / backorder stay purchasable and must not trade a sale
              for an email address. */}
          {availability === "out_of_stock" && (
            <BackInStockNotify
              productId={product.id}
              variantId={
                selectedVariant?.id ?? product.default_variant?.id ?? null
              }
            />
          )}

          {/* Variant Picker */}
          {hasVariants && optionTypes.length > 0 && (
            <div className="mt-8">
              <VariantPicker
                variants={variants}
                optionTypes={optionTypes}
                selectedVariant={selectedVariant}
                onVariantChange={handleVariantChange}
              />
            </div>
          )}

          {/* Quantity & Add to Cart */}
          <div className="mt-8 flex flex-col gap-4 sm:flex-row sm:items-center">
            <QuantityPicker
              quantity={quantity}
              onDecrement={() => setQuantity(Math.max(1, quantity - 1))}
              onIncrement={() => setQuantity(quantity + 1)}
              size="lg"
            />

            {/* Actions row: Add to Cart + Buy Now side by side, equal width */}
            <div className="grid flex-1 grid-cols-2 gap-4">
              {/* Add to Cart Button */}
              <Button
                size="lg"
                className="w-full"
                onClick={handleAddToCart}
                disabled={loading || !isPurchasable}
              >
                {loading ? (
                  <>
                    <Loader2 className="animate-spin h-5 w-5" />
                    {t("adding")}
                  </>
                ) : isPurchasable ? (
                  <>
                    <ShoppingBag className="w-5 h-5" />
                    {t("addToCart")}
                  </>
                ) : (
                  t("outOfStock")
                )}
              </Button>

              {/* Buy Now (P5, 2026-08-27): 快捷下单，不污染购物车 */}
              <div className="flex-1">
                <BuyNowButton
                  variantId={
                    selectedVariant?.id ||
                    product.default_variant?.id ||
                    product.default_variant_id ||
                    ""
                  }
                  disabled={!isPurchasable}
                  quantity={quantity}
                />
              </div>
            </div>
          </div>

          {/* Description */}
          {product.description && (
            <div className="mt-10 border-t pt-8">
              <h2 className="text-lg font-medium text-gray-900 mb-4">
                {t("description")}
              </h2>
              {/* Description is admin-authored HTML from the PallasTrade CMS backend (trusted source) */}
              <div
                className="text-gray-600 prose prose-sm max-w-none"
                dangerouslySetInnerHTML={{ __html: product.description }}
              />
            </div>
          )}

          {/* Custom Fields */}
          <ProductCustomFields customFields={product.custom_fields} />

          {/* Product Details */}
          <div className="mt-8 border-t pt-8">
            <h2 className="text-lg font-medium text-gray-900 mb-4">
              {t("details")}
            </h2>
            <dl className="space-y-3">
              {selectedVariant?.sku && (
                <div className="flex">
                  <dt className="w-32 text-gray-500 text-sm">{t("sku")}</dt>
                  <dd className="text-gray-900 text-sm">
                    {selectedVariant.sku}
                  </dd>
                </div>
              )}
              {selectedVariant?.options_text && (
                <div className="flex">
                  <dt className="w-32 text-gray-500 text-sm">{t("options")}</dt>
                  <dd className="text-gray-900 text-sm">
                    {selectedVariant.options_text}
                  </dd>
                </div>
              )}
            </dl>
          </div>
        </div>
      </div>

      {/* Product reviews (P0-4 / F-1) */}
      <ProductReviews
        productId={product.id}
        reviews={reviews}
        meta={reviewMeta}
        averageRating={averageRating}
        reviewCount={reviewCount}
        isAuthenticated={isAuthenticated}
      />
    </div>
  );
}
