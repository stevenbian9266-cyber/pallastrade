"use client";

import type { LucideIcon } from "lucide-react";
import { ImageIcon } from "lucide-react";
import Image, { type ImageProps } from "next/image";
import { useState } from "react";
import { cn } from "@/lib/utils";

type ProductImageProps = Omit<ImageProps, "src"> & {
  src: string | null | undefined;
  /** Responsive srcset (multi-size webp variant URLs, e.g. `"url 720w, url 2000w"`). */
  srcSet?: string;
  iconClassName?: string;
  icon?: LucideIcon;
};

export function ProductImage({
  src,
  srcSet,
  iconClassName = "w-8 h-8",
  icon: Icon = ImageIcon,
  onError,
  fetchPriority,
  ...rest
}: ProductImageProps): React.JSX.Element {
  const [hasError, setHasError] = useState(false);

  if (!src || hasError) {
    return (
      <div
        className="absolute inset-0 flex items-center justify-center bg-gray-100 text-gray-300"
        role="img"
        aria-label={typeof rest.alt === "string" ? rest.alt : "Product image"}
      >
        <Icon className={iconClassName} />
      </div>
    );
  }

  // When a multi-size srcset is provided we render a plain <img> with the
  // CDN-served webp variant URLs directly — the backend already produced
  // sized/optimized variants, so running them through the Next.js optimizer
  // again would double-encode and waste bandwidth.
  if (srcSet) {
    return (
      // biome-ignore lint/performance/noImgElement: CDN 已优化的 webp 变体直出，避免 Next 二次编码
      <img
        src={src}
        srcSet={srcSet}
        sizes={rest.sizes}
        alt={typeof rest.alt === "string" ? rest.alt : ""}
        loading={fetchPriority === "high" ? "eager" : "lazy"}
        onError={(e) => {
          setHasError(true);
          onError?.(e);
        }}
        className={cn(
          rest.fill
            ? "absolute inset-0 h-full w-full object-cover"
            : "block h-auto w-full",
          rest.className,
        )}
      />
    );
  }

  return (
    <Image
      src={src}
      onError={(e) => {
        setHasError(true);
        onError?.(e);
      }}
      fetchPriority={fetchPriority}
      loading={fetchPriority === "high" ? "eager" : undefined}
      {...rest}
    />
  );
}
