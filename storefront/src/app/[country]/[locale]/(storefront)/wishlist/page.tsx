import type { Metadata } from "next";
import { getTranslations } from "next-intl/server";
import { WishlistList } from "./WishlistList";

interface WishlistPageProps {
  params: Promise<{
    country: string;
    locale: string;
  }>;
}

export async function generateMetadata({
  params,
}: WishlistPageProps): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({
    locale: locale as Locale,
    namespace: "wishlist",
  });

  return {
    title: t("title"),
    // Saved items live in the browser: keep them out of search indexes.
    robots: { index: false },
  };
}

export default async function WishlistPage({ params }: WishlistPageProps) {
  const { country, locale } = await params;
  const basePath = `/${country}/${locale}`;
  const t = await getTranslations({
    locale: locale as Locale,
    namespace: "wishlist",
  });

  return (
    <div className="container mx-auto px-4 sm:px-6 lg:px-8 py-10">
      <h1 className="text-2xl font-medium text-gray-900 mb-6">{t("title")}</h1>
      <WishlistList basePath={basePath} />
    </div>
  );
}
