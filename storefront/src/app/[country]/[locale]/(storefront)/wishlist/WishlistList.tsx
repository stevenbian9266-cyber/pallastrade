"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";
import { useEffect, useState } from "react";
import { ProductCard } from "@/components/products/ProductCard";
import {
  dispatchLocalEvent,
  readLocalValue,
  writeLocalValue,
} from "@/lib/utils/local-store";
import {
  parseWishlist,
  removeWishlistEntry,
  serializeWishlist,
  WISHLIST_EVENT,
  WISHLIST_KEY,
  type WishlistEntry,
} from "@/lib/utils/wishlist";

/**
 * Wishlist contents (PRD-20260915-catalog-batch-c1-discovery FR-003/AC-008).
 * Reads after mount, so the server-rendered shell stays hydration-safe, and
 * reacts to removals from other tabs.
 */
export function WishlistList({ basePath }: { basePath: string }) {
  const t = useTranslations("wishlist");
  const [entries, setEntries] = useState<WishlistEntry[] | null>(null);

  useEffect(() => {
    const sync = () => setEntries(parseWishlist(readLocalValue(WISHLIST_KEY)));

    sync();
    window.addEventListener(WISHLIST_EVENT, sync);
    window.addEventListener("storage", sync);

    return () => {
      window.removeEventListener(WISHLIST_EVENT, sync);
      window.removeEventListener("storage", sync);
    };
  }, []);

  const handleRemove = (productId: string) => {
    const next = removeWishlistEntry(entries ?? [], productId);

    setEntries(next);
    writeLocalValue(WISHLIST_KEY, serializeWishlist(next));
    dispatchLocalEvent(WISHLIST_EVENT);
  };

  // Skeleton while the browser list is being read (first paint) so the page has
  // an explicit loading state instead of a blank gap.
  if (entries === null) {
    return (
      <div
        aria-busy="true"
        data-testid="wishlist-loading"
        className="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3"
      >
        {[0, 1, 2].map((key) => (
          <div key={key} className="h-64 rounded-md bg-gray-100" />
        ))}
      </div>
    );
  }

  if (entries.length === 0) {
    return (
      <div className="text-center py-16" data-testid="wishlist-empty">
        <p className="text-gray-500 mb-6">{t("empty")}</p>
        <Link
          href={`${basePath}/products`}
          className="text-primary underline-offset-4 hover:underline"
        >
          {t("browse")}
        </Link>
      </div>
    );
  }

  return (
    <ul className="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
      {entries.map((entry) => (
        <li key={entry.id} className="flex flex-col">
          <ProductCard product={entry.product} basePath={basePath} />
          <button
            type="button"
            onClick={() => handleRemove(entry.id)}
            className="mt-3 self-start text-sm text-gray-500 underline hover:text-gray-900"
          >
            {t("remove")}
          </button>
        </li>
      ))}
    </ul>
  );
}
