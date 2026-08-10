"use client";

import type { Category } from "@pallastrade/sdk";
import { ChevronDown, ChevronRight } from "lucide-react";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { useState } from "react";

/**
 * Persistent category navigation bar (常驻顶部分类导航条).
 *
 * Desktop only (`hidden md:block`) — the mobile drawer (MobileMenu) remains the
 * entry point on small screens. Supports BOTH hover and click to open the
 * dropdown, and renders up to three levels (root → child → grandchild).
 *
 * Interaction model:
 * - Hovering a root <li> opens its dropdown (desktop habit).
 * - Clicking the chevron toggles the dropdown (explicit click support).
 * - Hovering a child row opens its grandchild flyout (click chevron toggles too).
 * - The category name link always navigates to the category page.
 *
 * # PRD-20260810-storefront-对商城前台进行重新规划 AC-102
 */
interface CategoryNavProps {
  rootCategories: Category[];
  basePath: string;
}

export function CategoryNav({ rootCategories, basePath }: CategoryNavProps) {
  const t = useTranslations("header");
  const [openCategoryId, setOpenCategoryId] = useState<string | null>(null);
  const [openChildId, setOpenChildId] = useState<string | null>(null);

  const closeAll = () => {
    setOpenCategoryId(null);
    setOpenChildId(null);
  };

  const toggleCategory = (id: string) => {
    setOpenCategoryId((current) => (current === id ? null : id));
    setOpenChildId(null);
  };

  const navLinkClass =
    "inline-flex items-center gap-1 px-3 py-2.5 font-medium text-gray-700 hover:text-primary transition-colors";

  return (
    <nav
      aria-label={t("categories")}
      className="hidden md:block border-b border-gray-200 bg-white"
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
            const isOpen = openCategoryId === category.id;

            return (
              <li
                key={category.id}
                className="relative"
                onMouseEnter={() => {
                  if (hasChildren) setOpenCategoryId(category.id);
                }}
                onMouseLeave={closeAll}
              >
                <div className="flex items-center">
                  <Link
                    href={`${basePath}/c/${category.permalink}`}
                    className={navLinkClass}
                    onClick={closeAll}
                  >
                    {category.name}
                  </Link>
                  {hasChildren && (
                    <button
                      type="button"
                      onClick={() => toggleCategory(category.id)}
                      aria-expanded={isOpen}
                      aria-label={`${t("categories")}: ${category.name}`}
                      className={`inline-flex items-center px-1 py-2.5 text-gray-400 transition-colors hover:text-primary cursor-pointer ${
                        isOpen ? "text-primary" : ""
                      }`}
                    >
                      <ChevronDown
                        className={`size-3.5 transition-transform ${
                          isOpen ? "rotate-180" : ""
                        }`}
                      />
                    </button>
                  )}
                </div>

                {hasChildren && isOpen && (
                  <div className="absolute left-0 top-full z-40 min-w-56 rounded-lg border border-gray-200 bg-white p-2 shadow-lg">
                    <ul className="grid gap-0.5">
                      {category.children?.map((child) => {
                        const childHasChildren =
                          !!child.children && child.children.length > 0;
                        const childIsOpen = openChildId === child.id;
                        return (
                          <li
                            key={child.id}
                            className="relative"
                            onMouseEnter={() => {
                              if (childHasChildren) setOpenChildId(child.id);
                            }}
                          >
                            <div className="flex items-center justify-between rounded-md">
                              <Link
                                href={`${basePath}/c/${child.permalink}`}
                                className="flex-1 rounded-md px-3 py-2 text-sm text-gray-700 transition-colors hover:bg-gray-50 hover:text-primary"
                                onClick={closeAll}
                              >
                                {child.name}
                              </Link>
                              {childHasChildren && (
                                <button
                                  type="button"
                                  onClick={() =>
                                    setOpenChildId((current) =>
                                      current === child.id ? null : child.id,
                                    )
                                  }
                                  aria-expanded={childIsOpen}
                                  aria-label={`${t("categories")}: ${child.name}`}
                                  className="inline-flex items-center px-1.5 py-2 text-gray-400 transition-colors hover:text-primary cursor-pointer"
                                >
                                  <ChevronRight
                                    className={`size-3.5 transition-transform ${
                                      childIsOpen ? "rotate-90" : ""
                                    }`}
                                  />
                                </button>
                              )}
                            </div>

                            {childHasChildren && childIsOpen && (
                              <div className="absolute left-full top-0 z-40 min-w-52 rounded-lg border border-gray-200 bg-white p-2 shadow-lg">
                                <ul className="grid gap-0.5">
                                  {child.children?.map((grandchild) => (
                                    <li key={grandchild.id}>
                                      <Link
                                        href={`${basePath}/c/${grandchild.permalink}`}
                                        className="block rounded-md px-3 py-2 text-sm text-gray-700 transition-colors hover:bg-gray-50 hover:text-primary"
                                        onClick={closeAll}
                                      >
                                        {grandchild.name}
                                      </Link>
                                    </li>
                                  ))}
                                </ul>
                              </div>
                            )}
                          </li>
                        );
                      })}
                    </ul>
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

