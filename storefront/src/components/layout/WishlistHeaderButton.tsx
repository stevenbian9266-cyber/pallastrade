"use client";

import { Heart } from "lucide-react";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { readLocalValue } from "@/lib/utils/local-store";
import {
  parseWishlist,
  WISHLIST_EVENT,
  WISHLIST_KEY,
} from "@/lib/utils/wishlist";

/**
 * Header entry point for the wishlist (PRD-20260915-catalog-batch-c1-discovery
 * FR-003), mirroring CartButton: icon + count badge, count filled after mount.
 */
export function WishlistHeaderButton({ basePath }: { basePath: string }) {
  const t = useTranslations("wishlist");
  const [count, setCount] = useState(0);

  useEffect(() => {
    const sync = () =>
      setCount(parseWishlist(readLocalValue(WISHLIST_KEY)).length);

    sync();
    window.addEventListener(WISHLIST_EVENT, sync);
    window.addEventListener("storage", sync);

    return () => {
      window.removeEventListener(WISHLIST_EVENT, sync);
      window.removeEventListener("storage", sync);
    };
  }, []);

  return (
    <Button variant="ghost" size="icon-lg" asChild className="relative">
      <Link href={`${basePath}/wishlist`} aria-label={t("title")}>
        <Heart className="size-5" />
        {count > 0 && (
          <span className="absolute top-0 right-0 bg-primary text-white text-xs font-medium rounded-full h-5 w-5 flex items-center justify-center">
            {count}
          </span>
        )}
      </Link>
    </Button>
  );
}
