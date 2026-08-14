import type { Media } from "@pallastrade/sdk";

/**
 * Build an HTML `srcset` attribute from a media record's available multi-size
 * webp variant URLs (Rails ActiveStorage variants served via CDN).
 *
 * Returns `undefined` when there is nothing to build (no media or no sized
 * URLs), so callers can fall back to the single `src` URL unchanged.
 *
 * Widths mirror the backend variant sizes in
 * `PallasTrade::Config.product_image_variant_sizes`.
 */
export function buildImageSrcSet(
  media:
    | Pick<Media, "small_url" | "medium_url" | "large_url" | "xlarge_url">
    | null
    | undefined,
): string | undefined {
  if (!media) return undefined;

  const candidates: Array<[string | null | undefined, number]> = [
    [media.small_url, 256],
    [media.medium_url, 400],
    [media.large_url, 720],
    [media.xlarge_url, 2000],
  ];

  const parts = candidates
    .filter(([url]) => Boolean(url))
    .map(([url, width]) => `${url} ${width}w`);

  return parts.length > 0 ? parts.join(", ") : undefined;
}
