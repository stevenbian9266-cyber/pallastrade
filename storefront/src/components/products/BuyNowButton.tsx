"use client";

import { Zap } from "lucide-react";
import { usePathname, useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { createBuyNowCart } from "@/lib/data/buy-now";
import { extractBasePath } from "@/lib/utils/path";

interface BuyNowButtonProps {
  variantId: string;
  quantity: number;
  disabled?: boolean;
}

/**
 * Buy Now（P5, 2026-08-27）：详情页快捷下单——创建含当前商品的独立 cart
 * 直接进入确认页（不污染购物车）。
 */
export function BuyNowButton({
  variantId,
  quantity,
  disabled,
}: BuyNowButtonProps) {
  const t = useTranslations("products");
  const router = useRouter();
  const pathname = usePathname();
  const basePath = extractBasePath(pathname);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleBuyNow() {
    if (!variantId) return;
    setLoading(true);
    setError(null);
    const result = await createBuyNowCart(variantId, quantity);
    if ("error" in result) {
      setError(result.error);
      setLoading(false);
      return;
    }
    // 下单链路统一化（PRD-20260830-checkout）：Buy Now 进入统一下单页
    router.push(`${basePath}/checkout/${result.cart.id}`);
  }

  return (
    <div>
      <Button
        variant="outline"
        size="lg"
        className="w-full"
        onClick={handleBuyNow}
        disabled={disabled || loading || !variantId}
      >
        <Zap className="w-5 h-5" />
        {t("buyNow")}
      </Button>
      {error ? (
        <p className="mt-2 text-sm text-red-600" role="alert">
          {error}
        </p>
      ) : null}
    </div>
  );
}
