"use client";

import type { Product } from "@pallastrade/sdk";
import { Heart } from "lucide-react";
import { useTranslations } from "next-intl";
import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import {
  dispatchLocalEvent,
  readLocalValue,
  writeLocalValue,
} from "@/lib/utils/local-store";
import {
  isWishlisted,
  parseWishlist,
  serializeWishlist,
  toggleWishlistEntry,
  WISHLIST_EVENT,
  WISHLIST_KEY,
  type WishlistEntry,
} from "@/lib/utils/wishlist";

interface WishlistButtonProps {
  product: Product;
  className?: string;
}

/**
 * Wishlist toggle, browser-local V1 (PRD-20260915-catalog-batch-c1-discovery
 * FR-003). The saved state is read after mount so the server render and the
 * first client render agree (hydration-safe), and the same-page event keeps the
 * header badge in sync.
 *
 * A lightweight secondary action (`outline` + `sm`) on purpose: it sits next to
 * the availability line and must never compete with Add to Cart / Buy Now for
 * the same row.
 */
export function WishlistButton({ product, className }: WishlistButtonProps) {
  const t = useTranslations("wishlist");
  const [entries, setEntries] = useState<WishlistEntry[] | null>(null);

  useEffect(() => {
    setEntries(parseWishlist(readLocalValue(WISHLIST_KEY)));
  }, []);

  const saved = entries ? isWishlisted(entries, product.id) : false;

  const handleToggle = () => {
    const next = toggleWishlistEntry(entries ?? [], product);

    setEntries(next);
    writeLocalValue(WISHLIST_KEY, serializeWishlist(next));
    dispatchLocalEvent(WISHLIST_EVENT);
  };

  return (
    <Button
      type="button"
      variant="outline"
      size="sm"
      className={className}
      onClick={handleToggle}
      aria-pressed={saved}
      aria-label={saved ? t("removeAria") : t("add")}
    >
      <Heart className={saved ? "size-5 fill-current" : "size-5"} />
      <span>{saved ? t("remove") : t("add")}</span>
    </Button>
  );
}
