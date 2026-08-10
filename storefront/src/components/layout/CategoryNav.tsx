"use client";

import type { Category } from "@pallastrade/sdk";
import { ChevronDown } from "lucide-react";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { useEffect, useRef, useState } from "react";

/**
 * Persistent category navigation bar (常驻顶部分类导航条).
 *
 * Desktop only (`hidden md:block`) — the mobile drawer (MobileMenu) is the
 * small-screen entry point.
 *
 * Multi-level category panel with BOTH hover and click:
 * - **Hover a root category** → its sub-category menu panel opens (mouse
 *   entering the panel keeps it open; leaving the whole nav bar closes it).
 * - **Click a root category name** → toggles the panel (click "locks" it open
 *   even after the mouse leaves — click again or click outside to close).
 * - The panel lists ALL level-2 children as columns, each with its level-3
 *   grandchildren inline, plus a "View all" footer link.
 *
 * # PRD-20260810-storefront-对商城前台进行重新规划 AC-102
 */
interface CategoryNavProps {
  rootCategories: Category[];
  basePath: string;
}

export function CategoryNav({ rootCategories, basePath }: CategoryNavProps) {
  const t = useTranslations("header");
  const [hoveredId, setHoveredId] = useState<string | null>(null);
  const [clickedId, setClickedId] = useState<string | null>(null);
  const navRef = useRef<HTMLElement>(null);

  // Hover opens the panel; a click "locks" it open even after hover leaves.
  const openId = hoveredId ?? clickedId;

  const close = () => {
    setHoveredId(null);
    setClickedId(null);
  };

  // Close when clicking outside the nav.
  useEffect(() => {
    if (openId === null) return;
    const onPointerDown = (event: MouseEvent) => {
      if (navRef.current && !navRef.current.contains(event.target as Node)) {
        close();
      }
    };
    document.addEventListener("mousedown", onPointerDown);
    return () => document.removeEventListener("mousedown", onPointerDown);
  }, [openId]);

  const toggleClick = (id: string) =>
    setClickedId((current) => (current === id ? null : id));

  const navLinkClass =
    "inline-flex items-center gap-1 px-3 py-2.5 font-medium text-gray-700 hover:text-primary transition-colors";

  return (
    <nav
      ref={navRef}
      aria-label={t("categories")}
      className="hidden md:block border-b border-gray-200 bg-white"
      onMouseLeave={() => setHoveredId(null)}
    >
      <div className="container mx-auto px-4 sm:px-6 lg:px-8">
        <ul className="flex items-center text-sm overflow-x-auto whitespace-nowrap [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
          <li>
            <Link href={basePath || "/"} className={navLinkClass}>
              {t("home")}
            </Link>
          </li>
          <li>
            <Link href={`${basePath}/products`} className={navLinkClass}>
              {t("allProducts")}
            </Link>
          </li>
          {rootCategories.map((category) => {
            const hasChildren =
              !!category.children && category.children.length > 0;
            const isOpen = openId === category.id;

            return (
              <li
                key={category.id}
                className="relative"
                onMouseEnter={() => {
                  if (hasChildren) setHoveredId(category.id);
                }}
              >
                <button
                  type="button"
                  onClick={() => toggleClick(category.id)}
                  aria-expanded={isOpen}
                  aria-haspopup="true"
                  className="inline-flex cursor-pointer items-center gap-1 px-3 py-2.5 font-medium text-gray-700 transition-colors hover:text-primary"
                >
                  {category.name}
                  {hasChildren && (
                    <ChevronDown
                      className={`size-3.5 transition-transform ${
                        isOpen ? "rotate-180 text-primary" : "text-gray-400"
                      }`}
                    />
                  )}
                </button>

                {hasChildren && isOpen && (
                  <div className="absolute left-0 top-full z-40 w-[640px] rounded-b-lg border border-t-0 border-gray-200 bg-white p-4 shadow-lg">
                    <div className="grid grid-cols-2 md:grid-cols-3 gap-6">
                      {category.children?.map((child) => (
                        <div key={child.id}>
                          <Link
                            href={`${basePath}/c/${child.permalink}`}
                            onClick={close}
                            className="text-sm font-semibold text-gray-900 transition-colors hover:text-primary"
                          >
                            {child.name}
                          </Link>
                          {child.children && child.children.length > 0 && (
                            <ul className="mt-2 space-y-1.5">
                              {child.children.map((grandchild) => (
                                <li key={grandchild.id}>
                                  <Link
                                    href={`${basePath}/c/${grandchild.permalink}`}
                                    onClick={close}
                                    className="text-sm text-gray-600 transition-colors hover:text-primary"
                                  >
                                    {grandchild.name}
                                  </Link>
                                </li>
                              ))}
                            </ul>
                          )}
                        </div>
                      ))}
                    </div>
                    <div className="mt-4 border-t border-gray-100 pt-3">
                      <Link
                        href={`${basePath}/c/${category.permalink}`}
                        onClick={close}
                        className="text-sm font-medium text-primary transition-colors hover:text-primary/80"
                      >
                        {t("viewAllCategory", { category: category.name })}
                        &rarr;
                      </Link>
                    </div>
                  </div>
                )}
              </li>
            );
          })}
        </ul>
      </div>
    </nav>
  );
}



