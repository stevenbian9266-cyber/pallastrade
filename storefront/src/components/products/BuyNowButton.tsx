"use client";

// PALLAS-CUSTOM: Buy Now 快捷下单按钮（PRD-20260824 FR-011）
// 点击后由父组件（ProductDetails）创建仅含当前商品的快捷购物车并跳转公用确认页。
// 未登录用户由父组件先跳转登录（带 redirect 回跳）。
import { Loader2, Zap } from "lucide-react";
import { useTranslations } from "next-intl";
import { Button } from "@/components/ui/button";

interface BuyNowButtonProps {
  disabled?: boolean;
  loading?: boolean;
  onClick: () => void;
}

export function BuyNowButton({
  disabled = false,
  loading = false,
  onClick,
}: BuyNowButtonProps) {
  const t = useTranslations("products");

  return (
    <Button
      size="lg"
      variant="outline"
      onClick={onClick}
      disabled={disabled || loading}
      data-testid="buy-now-button"
      className="flex-1"
    >
      {loading ? (
        <>
          <Loader2 className="animate-spin h-5 w-5" />
          {t("buying")}
        </>
      ) : (
        <>
          <Zap className="w-5 h-5" />
          {t("buyNow")}
        </>
      )}
    </Button>
  );
}
