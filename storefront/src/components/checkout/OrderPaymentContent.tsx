"use client";

import type { Order, PaymentMethod } from "@pallastrade/sdk";
import { usePathname, useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useCallback, useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import type { StripePaymentFormHandle } from "@/components/checkout/StripePaymentForm";
import { StripePaymentForm } from "@/components/checkout/StripePaymentForm";
import { Button } from "@/components/ui/button";
import { ProductImage } from "@/components/ui/product-image";
import {
  completeOrder,
  completeOrderPaymentSession,
  createOrderPaymentSession,
} from "@/lib/data/order-payment";
import { extractBasePath } from "@/lib/utils/path";

interface OrderPaymentContentProps {
  order: Order;
}

/**
 * 订单流程标准电商改造 P1（2026-08-30）：Checkout 纯支付页（标准流程订单）。
 * 收货/物流只读；仅支付。支付完成 → 订单 paid → 跳转 order-placed。
 */
export function OrderPaymentContent({ order }: OrderPaymentContentProps) {
  const t = useTranslations("checkout");
  const tc = useTranslations("common");
  const router = useRouter();
  const pathname = usePathname();
  const basePath = extractBasePath(pathname);

  const paymentMethods: PaymentMethod[] = order.payment_methods ?? [];
  const [selectedMethodId, setSelectedMethodId] = useState(
    paymentMethods[0]?.id ?? "",
  );
  const selectedMethod =
    paymentMethods.find((m) => m.id === selectedMethodId) ?? paymentMethods[0];

  const [stripeSecret, setStripeSecret] = useState<string | null>(null);
  const [stripeSessionId, setStripeSessionId] = useState<string | null>(null);
  const [processing, setProcessing] = useState(false);
  const stripeHandleRef = useRef<StripePaymentFormHandle | null>(null);

  const isPaid = order.state === "paid" || order.state === "completed";

  const handleStripeReady = useCallback((handle: StripePaymentFormHandle) => {
    stripeHandleRef.current = handle;
  }, []);

  // 已支付 → 直接跳完成页
  useEffect(() => {
    if (isPaid) {
      router.replace(`${basePath}/order-placed/${order.id}`);
    }
  }, [isPaid, order.id, basePath, router]);

  const handlePay = async () => {
    if (!selectedMethod) return;
    setProcessing(true);
    try {
      const gatewayType = selectedMethod.type;
      const isSessionBased = selectedMethod.session_required === true;

      if (isSessionBased) {
        // 创建订单支付会话 → 获取 client_secret（Stripe Checkout Session）
        const result = await createOrderPaymentSession(
          order.id,
          selectedMethod.id,
        );
        if (!result.success) {
          toast.error(result.error);
          setProcessing(false);
          return;
        }
        const session = result.session as {
          id: string;
          client_secret?: string | null;
        };
        setStripeSessionId(session.id);

        if (gatewayType === "stripe" && session.client_secret) {
          setStripeSecret(session.client_secret);
          setProcessing(false);
          return; // 渲染 StripePaymentForm，用户确认后走 handleStripePay
        }
        // 其他 session-based（PayPal/Adyen）：直接完成会话（provider 回调驱动）
        await completeOrderPaymentSession(order.id, session.id);
        await completeOrder(order.id);
        router.push(`${basePath}/order-placed/${order.id}`);
        return;
      }

      // 非 session（Check/COD/银行转账）：无在线支付，订单保持 pending（线下收款），
      // 直接跳完成页。
      router.push(`${basePath}/order-placed/${order.id}`);
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "Payment failed");
    } finally {
      setProcessing(false);
    }
  };

  const handleStripePay = async () => {
    if (!stripeHandleRef.current || !stripeSessionId) return;
    setProcessing(true);
    try {
      const returnUrl = `${window.location.origin}${basePath}/order-placed/${order.id}`;
      const result = await stripeHandleRef.current.confirmPayment(returnUrl);
      if (result.error) {
        toast.error(result.error);
        setProcessing(false);
        return;
      }
      // 支付确认成功 → 完成会话 + 完成订单
      await completeOrderPaymentSession(order.id, stripeSessionId);
      const done = await completeOrder(order.id);
      router.push(`${basePath}/order-placed/${order.id}`);
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "Payment failed");
    } finally {
      setProcessing(false);
    }
  };

  return (
    <div className="container mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <h1 className="text-3xl font-bold text-gray-900 mb-8">{t("payment")}</h1>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        {/* 只读信息 */}
        <div className="lg:col-span-2 space-y-8">
          {/* 收货信息（只读） */}
          <section className="bg-white rounded-xl border border-gray-200 p-6">
            <h2 className="text-lg font-medium text-gray-900 mb-4">
              {t("shippingAddress")}
            </h2>
            {order.shipping_address ? (
              <div className="text-sm text-gray-700">
                <p>
                  {order.shipping_address.first_name}{" "}
                  {order.shipping_address.last_name}
                </p>
                <p>{order.shipping_address.address1}</p>
                {order.shipping_address.address2 && (
                  <p>{order.shipping_address.address2}</p>
                )}
                <p>
                  {order.shipping_address.city}
                  {order.shipping_address.state_abbr
                    ? `, ${order.shipping_address.state_abbr}`
                    : ""}{" "}
                  {order.shipping_address.postal_code}
                </p>
                {order.shipping_address.country_iso && (
                  <p>{order.shipping_address.country_iso}</p>
                )}
                {order.shipping_address.phone && (
                  <p>{order.shipping_address.phone}</p>
                )}
              </div>
            ) : (
              <p className="text-sm text-gray-500">{t("noShippingAddress")}</p>
            )}
          </section>

          {/* 支付方式 */}
          <section className="bg-white rounded-xl border border-gray-200 p-6">
            <h2 className="text-lg font-medium text-gray-900 mb-4">
              {t("paymentMethod")}
            </h2>

            {stripeSecret ? (
              <div>
                <StripePaymentForm
                  clientSecret={stripeSecret}
                  onReady={handleStripeReady}
                />
                <Button
                  size="lg"
                  className="w-full mt-6"
                  disabled={processing}
                  onClick={handleStripePay}
                >
                  {processing
                    ? t("processing")
                    : t("payAmount", {
                        amount: order.display_total ?? "",
                      })}
                </Button>
              </div>
            ) : (
              <div className="flex flex-col gap-3">
                {paymentMethods.map((method) => (
                  <label
                    key={method.id}
                    className="flex items-center gap-3 p-3 rounded-lg border border-gray-200 cursor-pointer hover:border-indigo-300"
                  >
                    <input
                      type="radio"
                      name="payment-method"
                      checked={selectedMethodId === method.id}
                      onChange={() => setSelectedMethodId(method.id ?? "")}
                      className="w-4 h-4 text-indigo-600 focus:ring-indigo-500"
                    />
                    <span className="font-medium text-gray-900">
                      {method.name}
                    </span>
                  </label>
                ))}

                <Button
                  size="lg"
                  className="w-full mt-6"
                  disabled={!selectedMethod || processing}
                  onClick={handlePay}
                >
                  {processing
                    ? t("processing")
                    : t("payAmount", {
                        amount: order.display_total ?? "",
                      })}
                </Button>
              </div>
            )}
          </section>
        </div>

        {/* 金额摘要 */}
        <div className="lg:col-span-1">
          <div className="bg-white rounded-xl border border-gray-200 p-6 sticky top-24">
            <h2 className="text-lg font-medium text-gray-900 mb-4">
              {tc("orderSummary")}
            </h2>

            <div className="space-y-4 divide-y divide-gray-100">
              {(order.items ?? []).map((item) => (
                <div key={item.id} className="flex gap-4 pt-4 first:pt-0">
                  <div className="relative w-16 h-16 bg-gray-100 rounded-lg overflow-hidden flex-shrink-0">
                    <ProductImage
                      src={item.thumbnail_url}
                      alt={item.name}
                      fill
                      className="object-cover"
                      sizes="64px"
                    />
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-gray-900 truncate">
                      {item.name}
                    </p>
                    <p className="text-sm text-gray-500">× {item.quantity}</p>
                  </div>
                  <p className="text-sm font-semibold text-gray-900">
                    {item.display_total}
                  </p>
                </div>
              ))}
            </div>

            <dl className="mt-6 space-y-4 border-t border-gray-100 pt-4">
              <div className="flex justify-between">
                <dt className="text-gray-500">{tc("subtotal")}</dt>
                <dd className="text-gray-900">{order.display_item_total}</dd>
              </div>
              {order.delivery_total && parseFloat(order.delivery_total) > 0 && (
                <div className="flex justify-between">
                  <dt className="text-gray-500">{tc("shipping")}</dt>
                  <dd className="text-gray-900">
                    {order.display_delivery_total}
                  </dd>
                </div>
              )}
              {order.tax_total && parseFloat(order.tax_total) > 0 && (
                <div className="flex justify-between">
                  <dt className="text-gray-500">{tc("tax")}</dt>
                  <dd className="text-gray-900">{order.display_tax_total}</dd>
                </div>
              )}
              <div className="flex justify-between border-t pt-4">
                <dt className="text-lg font-medium text-gray-900">
                  {tc("total")}
                </dt>
                <dd className="text-lg font-bold text-gray-900">
                  {order.display_total}
                </dd>
              </div>
            </dl>
          </div>
        </div>
      </div>
    </div>
  );
}
