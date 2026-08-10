import type { Category } from "@pallastrade/sdk";
import Link from "next/link";
import { JsonLd } from "@/components/seo/JsonLd";
import { CategoryNav } from "@/components/layout/CategoryNav";
import { Footer } from "@/components/layout/Footer";
import { Header } from "@/components/layout/Header";
import { getCategories } from "@/lib/data/categories";
import {
  buildCanonicalUrl,
  buildOrganizationJsonLd,
  buildWebsiteJsonLd,
} from "@/lib/seo";
import { getStoreUrl } from "@/lib/store";

interface StorefrontLayoutProps {
  children: React.ReactNode;
  params: Promise<{ country: string; locale: string }>;
}

function CategoryLinks({
  categories,
  basePath,
}: {
  categories: Category[];
  basePath: string;
}) {
  return (
    <ul>
      {categories.map((category) => (
        <li key={category.id}>
          <Link href={`${basePath}/c/${category.permalink}`}>
            {category.name}
          </Link>
          {category.children && category.children.length > 0 && (
            <CategoryLinks categories={category.children} basePath={basePath} />
          )}
        </li>
      ))}
    </ul>
  );
}

export default async function StorefrontLayout({
  children,
  params,
}: StorefrontLayoutProps) {
  const { country, locale } = await params;
  const basePath = `/${country}/${locale}`;

  const rootCategories = await getCategories({
    depth_eq: 0,
    expand: ["children.children"],
  })
    .then((res) => res.data)
    .catch((error) => {
      console.error("StorefrontLayout: failed to load categories", error);
      return [] as Category[];
    });

  const storeUrl = getStoreUrl();
  const websiteJsonLd = storeUrl
    ? buildWebsiteJsonLd(
        storeUrl,
        buildCanonicalUrl(storeUrl, `${basePath}/products`),
      )
    : null;

  return (
    <>
      <JsonLd data={buildOrganizationJsonLd()} />
      {websiteJsonLd && <JsonLd data={websiteJsonLd} />}
      <Header
        rootCategories={rootCategories}
        basePath={basePath}
        locale={locale as Locale}
      />
      <CategoryNav rootCategories={rootCategories} basePath={basePath} />
      {rootCategories.length > 0 && (
        <nav aria-label="Category navigation" className="sr-only">
          <CategoryLinks categories={rootCategories} basePath={basePath} />
        </nav>
      )}
      <main className="flex-1">{children}</main>
      <Footer
        rootCategories={rootCategories}
        basePath={basePath}
        locale={locale as Locale}
      />
    </>
  );
}
