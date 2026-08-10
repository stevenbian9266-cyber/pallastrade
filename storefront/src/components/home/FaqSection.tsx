import { ChevronDown } from "lucide-react";
import { getTranslations } from "next-intl/server";

/**
 * Home FAQ — visible Q&A list plus FAQPage JSON-LD (GEO).
 * The JSON-LD is built from the exact same translated Q&A shown in the UI so
 * structured data always matches visible content (PRD-20260810... AC-113).
 */
interface FaqSectionProps {
  locale: string;
}

export async function FaqSection({ locale }: FaqSectionProps) {
  const t = await getTranslations({
    locale: locale as Locale,
    namespace: "home",
  });

  const faqs = [
    {
      question: t("faqShippingQ"),
      answer: t("faqShippingA"),
    },
    {
      question: t("faqReturnsQ"),
      answer: t("faqReturnsA"),
    },
    {
      question: t("faqPaymentQ"),
      answer: t("faqPaymentA"),
    },
    {
      question: t("faqSupportQ"),
      answer: t("faqSupportA"),
    },
  ];

  const faqJsonLd = {
    "@context": "https://schema.org",
    "@type": "FAQPage",
    mainEntity: faqs.map((faq) => ({
      "@type": "Question",
      name: faq.question,
      acceptedAnswer: {
        "@type": "Answer",
        text: faq.answer,
      },
    })),
  };

  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(faqJsonLd) }}
      />
      <section
        aria-labelledby="faq-heading"
        className="border-b border-gray-200 py-16"
      >
        <div className="container mx-auto px-4 sm:px-6 lg:px-8">
          <div className="mx-auto max-w-3xl">
            <h2
              id="faq-heading"
              className="text-center text-2xl md:text-3xl font-bold text-gray-900"
            >
              {t("faqTitle")}
            </h2>
            <ul className="mt-10 divide-y divide-gray-200">
              {faqs.map((faq) => (
                <li key={faq.question} className="py-5">
                  <h3 className="flex items-center gap-2 text-base font-semibold text-gray-900">
                    <ChevronDown
                      className="size-4 shrink-0 text-primary"
                      aria-hidden="true"
                    />
                    {faq.question}
                  </h3>
                  <p className="mt-2 pl-6 text-sm leading-relaxed text-gray-600">
                    {faq.answer}
                  </p>
                </li>
              ))}
            </ul>
          </div>
        </div>
      </section>
    </>
  );
}
