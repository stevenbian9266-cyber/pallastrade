import type { Metadata } from "next";
import { getTranslations } from "next-intl/server";
import { CookieSettings } from "@/components/cookie/CookieSettings";

interface CookieSettingsPageProps {
  params: Promise<{
    country: string;
    locale: string;
  }>;
}

export async function generateMetadata({
  params,
}: CookieSettingsPageProps): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({
    locale: locale as Locale,
    namespace: "cookie",
  });
  return {
    title: t("settingsTitle"),
    description: t("settingsDescription"),
  };
}

/**
 * Standalone cookie preference page. The category toggles live in the shared
 * `CookieSettings` client component (also used by the banner's customize
 * panel); the persisted consent cookie updates immediately on save.
 *
 * # PRD-20260812-storefront-商城前台新增cookie功能 FR-004
 */
export default async function CookieSettingsRoute({
  params,
}: CookieSettingsPageProps) {
  const { locale } = await params;
  const t = await getTranslations({
    locale: locale as Locale,
    namespace: "cookie",
  });

  return (
    <div className="mx-auto max-w-3xl px-4 py-12 sm:px-6 lg:px-8">
      <h1 className="mb-2 text-3xl font-bold text-gray-900">
        {t("settingsTitle")}
      </h1>
      <CookieSettings />
    </div>
  );
}
