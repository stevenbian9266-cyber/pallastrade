import { Headset, RotateCcw, ShieldCheck, Truck } from "lucide-react";
import { getTranslations } from "next-intl/server";

/**
 * Brand trust bar — 4 value props (shipping / authenticity / returns / support).
 *
 * # PRD-20260810-storefront-对商城前台进行重新规划 AC-108
 */
interface ValuePropsProps {
  locale: string;
}

export async function ValueProps({ locale }: ValuePropsProps) {
  const t = await getTranslations({
    locale: locale as Locale,
    namespace: "home",
  });

  const props = [
    {
      icon: Truck,
      title: t("fastShipping"),
      description: t("shippingDescription"),
    },
    {
      icon: ShieldCheck,
      title: t("authenticProducts"),
      description: t("authenticDescription"),
    },
    {
      icon: RotateCcw,
      title: t("easyReturns"),
      description: t("returnsDescription"),
    },
    {
      icon: Headset,
      title: t("support"),
      description: t("supportDescription"),
    },
  ];

  return (
    <section
      aria-labelledby="value-props-heading"
      className="border-b border-gray-200 py-14"
    >
      <div className="container mx-auto px-4 sm:px-6 lg:px-8">
        <h2 id="value-props-heading" className="sr-only">
          {t("whyShopWithUs")}
        </h2>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-8">
          {props.map(({ icon: Icon, title, description }) => (
            <div key={title} className="flex flex-col items-center text-center">
              <div className="flex size-12 items-center justify-center rounded-full bg-primary/10 text-primary">
                <Icon className="size-6" aria-hidden="true" />
              </div>
              <h3 className="mt-4 text-base font-semibold text-gray-900">
                {title}
              </h3>
              <p className="mt-2 text-sm text-gray-600">{description}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
