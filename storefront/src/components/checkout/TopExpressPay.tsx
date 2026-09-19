"use client";

import type { Cart } from "@pallastrade/sdk";
import { useTranslations } from "next-intl";
import { useMemo } from "react";
import { ExpressCheckoutButton } from "@/components/checkout/ExpressCheckoutButton";
import {
  type PaymentMethodWithEntries,
  paymentEntriesFor,
} from "@/components/checkout/PaymentSection";
import { isExpressWalletKind } from "@/lib/checkout/wallet-availability";

/**
 * PRD-20260919-payments-checkout-top-express-pay-locale（2026-09-19）——
 * 结账页**顶部快捷支付区**（FR-001）：把服务端投影中全部可渲染的 express 入口
 * 直接以钱包按钮呈现（横向自适应、点击即付），位于 H1 之下、第 1 节之前。
 *
 * PRD-20260919-checkout-express-always-visible-and-pi-params（2026-09-19）——
 * **常显口径**（FR-005）：只要服务端下发了 express 入口，本区就**始终渲染**；
 * 设备能力不足时不再整区消失，而是原地降级为「说明 + 重试」（子组件 notice 模式）。
 *
 * 红线与口径：
 * - 入口集合只来自服务端 `payment_methods[].entries`（零前台筛选）；
 * - 不可承载的 kind 不进入顶部区（仍保留在第 5 节列表，不隐藏）；
 * - 设备不可用 / 超时 / 未配置 → 区域保留 + 原因文案 + 重试（零噪音不等于零信息）；
 * - 仅当服务端**没有**任何 express 入口时才整区不渲染。
 */
export interface TopExpressPayProps {
  cart: Cart;
  basePath: string;
  /** 统一下单页的全部支付方式投影（服务端 `payment_methods`）。 */
  methods: PaymentMethodWithEntries[];
  /** 支付完成后的 best-effort 回调（与第 5 节钱包槽位保持同一行为）。 */
  onComplete: () => void | Promise<void>;
}

export function TopExpressPay({
  cart,
  basePath,
  methods,
  onComplete,
}: TopExpressPayProps) {
  const t = useTranslations("expressCheckout");

  // 服务端 express 入口中 Stripe 元素可承载的 kind（apple_pay / google_pay / link）。
  const kinds = useMemo(() => {
    const seen = new Set<string>();
    const result: string[] = [];
    for (const method of methods) {
      for (const entry of paymentEntriesFor(method)) {
        if (entry.frontend_kind !== "express") continue;
        if (!isExpressWalletKind(entry.method_key)) continue;
        if (seen.has(entry.method_key)) continue;
        seen.add(entry.method_key);
        result.push(entry.method_key);
      }
    }
    return result;
  }, [methods]);

  // 顶部区钱包使用的 publishable 凭据：取「拥有 express 入口」的支付方式
  // 下发的 client_config（D10 服务端下发优先，缺省回落构建期环境变量）。
  const clientConfig = useMemo(() => {
    const owner = methods.find((method) =>
      paymentEntriesFor(method).some(
        (entry) =>
          entry.frontend_kind === "express" &&
          isExpressWalletKind(entry.method_key),
      ),
    );
    return owner?.client_config ?? null;
  }, [methods]);

  // 服务端无任何可承载的 express 入口 → 本区无内容可言（为零噪音而不渲染）。
  if (kinds.length === 0) return null;

  return (
    <section
      data-testid="top-express-payment"
      className="mb-8 rounded-xl border border-gray-200 bg-white p-6"
    >
      <h2 className="text-lg font-medium text-gray-900">{t("title")}</h2>
      <div className="mt-4">
        <ExpressCheckoutButton
          cart={cart}
          basePath={basePath}
          maxColumns={2}
          showDivider
          entryKinds={kinds}
          // FR-005：notice 模式 —— 设备不可用时在区内给出原因与重试，而不是整块消失。
          degradedDisplay="notice"
          clientConfig={clientConfig}
          onComplete={onComplete}
        />
      </div>
    </section>
  );
}
