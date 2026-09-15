import dynamic from "next/dynamic";
import { ProductCardSkeleton } from "@/components/products/ProductCardSkeleton";

/**
 * Client product carousel behind a dynamic import — shared by every product
 * rail (featured / related / recently viewed) so the Swiper bundle is only
 * fetched when a rail actually renders, with a grid of skeletons meanwhile.
 */
export const LazyProductCarousel = dynamic(
  () =>
    import("@/components/products/ProductCarousel").then((mod) => ({
      default: mod.ProductCarousel,
    })),
  {
    loading: () => (
      <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-6">
        {[...Array(4)].map((_, i) => (
          <ProductCardSkeleton key={i} />
        ))}
      </div>
    ),
  },
);
