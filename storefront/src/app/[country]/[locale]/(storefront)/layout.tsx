import type { Category } from "@pallastrade/sdk";
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
      <main className="flex-1">{children}</main>
      <Footer
        rootCategories={rootCategories}
        basePath={basePath}
        locale={locale as Locale}
      />
    </>
  );
}
