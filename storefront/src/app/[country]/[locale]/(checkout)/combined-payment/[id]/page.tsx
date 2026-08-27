import { CombinedPaymentCheckout } from "@/components/checkout/CombinedPaymentCheckout";

interface CombinedPaymentPageProps {
  params: Promise<{ id: string; country: string; locale: string }>;
}

/**
 * 合并支付收银台页（P5, 2026-08-27）：账户订单多选 → 组合 → 单次扣款。
 */
export default async function CombinedPaymentPage({
  params,
}: CombinedPaymentPageProps) {
  const { id, country, locale } = await params;

  return (
    <div className="min-h-[60vh] bg-gray-50">
      <div className="mx-auto max-w-3xl px-4 py-6">
        <CombinedPaymentCheckout
          combinationId={id}
          country={country}
          locale={locale}
        />
      </div>
    </div>
  );
}
