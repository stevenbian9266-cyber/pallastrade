"use client";

import { Bell, Check } from "lucide-react";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { getClient } from "@/lib/pallastrade";

interface BackInStockNotifyProps {
  productId: string;
}

/**
 * Back-in-stock notification — shown on a product page when the product is out
 * of stock. The customer leaves an email; we POST it to the Store API and the
 * backend notifies them via the `product.back_in_stock` event.
 */
export function BackInStockNotify({ productId }: BackInStockNotifyProps) {
  const t = useTranslations("products");
  const [email, setEmail] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [state, setState] = useState<"idle" | "loading" | "done">("idle");

  const handleSubmit = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const value = email.trim();
    if (!value) {
      setError(t("backInStockEmpty"));
      return;
    }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)) {
      setError(t("backInStockInvalid"));
      return;
    }
    setError(null);
    setState("loading");
    try {
      await getClient().backInStockSubscriptions.create(productId, {
        email: value,
      });
      setState("done");
    } catch {
      setError(t("backInStockError"));
      setState("idle");
    }
  };

  if (state === "done") {
    return (
      <p
        role="status"
        className="mt-2 inline-flex items-center gap-1.5 rounded-full bg-green-50 px-4 py-2 text-sm font-medium text-green-700"
      >
        <Check className="size-4" aria-hidden="true" />
        {t("backInStockSuccess")}
      </p>
    );
  }

  return (
    <div className="mt-4 rounded-lg border border-gray-200 bg-gray-50 p-4">
      <p className="flex items-center gap-1.5 text-sm font-medium text-gray-700">
        <Bell className="size-4" aria-hidden="true" />
        {t("backInStockTitle")}
      </p>
      <form onSubmit={handleSubmit} noValidate className="mt-2 flex gap-2">
        <Input
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          placeholder={t("backInStockPlaceholder")}
          aria-label={t("backInStockPlaceholder")}
          className="flex-1"
        />
        <Button type="submit" disabled={state === "loading"} size="sm">
          {state === "loading"
            ? t("backInStockSubmitting")
            : t("backInStockSubmit")}
        </Button>
      </form>
      {error && <p className="mt-1 text-sm text-red-600">{error}</p>}
    </div>
  );
}
