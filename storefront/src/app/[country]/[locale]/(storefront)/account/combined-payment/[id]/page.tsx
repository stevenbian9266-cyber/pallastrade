import { connection } from "next/server";
import { getTranslations } from "next-intl/server";
import { CombinedPaymentContent } from "@/components/account/CombinedPaymentContent";
import { getPaymentGroup } from "@/lib/data/payment-groups";

interface CombinedPaymentPageProps {
  params: Promise<{ country: string; locale: string; id: string }>;
}

export default async function CombinedPaymentPage({
  params,
}: CombinedPaymentPageProps) {
  await connection();
  const { country, locale, id } = await params;
  const t = await getTranslations({
    locale: locale as Locale,
    namespace: "combinedPayment",
  });
  const basePath = `/${country}/${locale}`;

  const result = await getPaymentGroup(id, { expand: ["orders"] });

  if (!result.success || !result.group) {
    return (
      <div className="max-w-2xl mx-auto py-12 text-center">
        <h1 className="text-2xl font-bold text-gray-900 mb-4">
          {t("notFound")}
        </h1>
        <p className="text-gray-500">{t("notFoundDescription")}</p>
      </div>
    );
  }

  return (
    <div className="max-w-2xl mx-auto">
      <h1 className="text-2xl font-bold text-gray-900 mb-6">
        {t("title")}
      </h1>
      <CombinedPaymentContent
        groupId={result.group.id}
        basePath={basePath}
      />
    </div>
  );
}
