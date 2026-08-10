import type { Category } from "@pallastrade/sdk";
import { ChevronDown, ChevronRight } from "lucide-react";
import Link from "next/link";
import { getTranslations } from "next-intl/server";

/**
 * Persistent category navigation bar (常驻顶部分类导航条).
 *
 * Desktop only (`hidden md:block`) — the mobile drawer (MobileMenu) remains the
 * entry point on small screens. Root categories render inline with hover
 * dropdowns for children (and grandchildren). Pure CSS hover (group-hover), no
 * JS, so it works with JS disabled and never affects TTI.
 *
 * # PRD-20260810-storefront-对商城前台进行重新规划 AC-102
 */
interface CategoryNavProps {
  rootCategories: Category[];
  basePath: string;
  locale: Locale;
}

export async function CategoryNav({
  rootCategories,
  basePath,
  locale,
}: CategoryNavProps) {
  const t = await getTranslations({ locale, namespace: "header" });

  const navLinkClass =
    "inline-flex items-center gap-1 px-3 py-2.5 font-medium text-gray-700 hover:text-primary transition-colors";

  return (
    <nav
      aria-label={t("categories")}
      className="hidden md:block border-b border-gray-200 bg-white"
    >
      <div className="container mx-auto px-4 sm:px-6 lg:px-8">
        <ul className="flex items-center text-sm">
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
          {rootCategories.map((category) => (
            <li key={category.id} className="group relative">
              <Link
                href={`${basePath}/c/${category.permalink}`}
                className={navLinkClass}
              >
                {category.name}
                {category.children && category.children.length > 0 && (
                  <ChevronDown className="size-3.5 text-gray-400 transition-colors group-hover:text-primary" />
                )}
              </Link>

              {category.children && category.children.length > 0 && (
                <div className="invisible absolute left-0 top-full z-40 min-w-52 translate-y-1 rounded-lg border border-gray-200 bg-white p-2 opacity-0 shadow-lg transition-all duration-150 group-hover:visible group-hover:translate-y-0 group-hover:opacity-100">
                  <ul className="grid gap-0.5">
                    {category.children.map((child) => (
                      <li key={child.id} className="group/child relative">
                        <Link
                          href={`${basePath}/c/${child.permalink}`}
                          className="flex items-center justify-between rounded-md px-3 py-2 text-sm text-gray-700 transition-colors hover:bg-gray-50 hover:text-primary"
                        >
                          {child.name}
                          {child.children && child.children.length > 0 && (
                            <ChevronRight className="size-3.5 text-gray-400" />
                          )}
                        </Link>

                        {child.children && child.children.length > 0 && (
                          <div className="invisible absolute left-full top-0 z-40 min-w-52 rounded-lg border border-gray-200 bg-white p-2 opacity-0 shadow-lg transition-all duration-150 group-hover/child:visible group-hover/child:opacity-100">
                            <ul className="grid gap-0.5">
                              {child.children.map((grandchild) => (
                                <li key={grandchild.id}>
                                  <Link
                                    href={`${basePath}/c/${grandchild.permalink}`}
                                    className="block rounded-md px-3 py-2 text-sm text-gray-700 transition-colors hover:bg-gray-50 hover:text-primary"
                                  >
                                    {grandchild.name}
                                  </Link>
                                </li>
                              ))}
                            </ul>
                          </div>
                        )}
                      </li>
                    ))}
                  </ul>
                </div>
              )}
            </li>
          ))}
        </ul>
      </div>
    </nav>
  );
}
