"use client";

import type {
  Cart,
  Country,
  DeliveryMethod,
  ShoppingCart,
  State,
} from "@pallastrade/sdk";
import {
  BadgeCheck,
  CircleAlert,
  CreditCard,
  Headset,
  Loader2,
  RefreshCcw,
  ShoppingBag,
  Truck,
} from "lucide-react";
import dynamic from "next/dynamic";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { toast } from "sonner";
import { AddOnsSection } from "@/components/checkout/AddOnsSection";
import { AddressFormFields } from "@/components/checkout/AddressFormFields";
import {
  CardPaymentForm,
  type CardPaymentFormHandle,
} from "@/components/checkout/CardPaymentForm";
import { CheckoutSectionTitle } from "@/components/checkout/CheckoutSectionTitle";
import { CouponCode } from "@/components/checkout/CouponCode";
import {
  type PaymentMethodWithEntries,
  PaymentSection,
  paymentEntriesFor,
} from "@/components/checkout/PaymentSection";
import { SaveInfoSection } from "@/components/checkout/SaveInfoSection";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { ProductImage } from "@/components/ui/product-image";
import { useCheckout } from "@/contexts/CheckoutContext";
import {
  isExpressWalletKind,
  type WalletAvailability,
  type WalletUnavailableReason,
} from "@/lib/checkout/wallet-availability";
import {
  type CheckoutQuote,
  diffQuotes,
  expectedVersions,
  normalizeQuote,
  type QuoteDiffRow,
  readQuoteSnapshot,
  writeQuoteSnapshot,
} from "@/lib/checkout-quote";
import { getCountry } from "@/lib/data/countries";
import { extractErrorCode, normalizeErrorMessage } from "@/lib/errors";
import {
  type AddressFormData,
  addressToFormData,
  emptyAddress,
  formDataToAddress,
} from "@/lib/utils/address";
import { safeParseFloat } from "@/lib/utils/format";
import { extractBasePath } from "@/lib/utils/path";

// D7（PRD-20260918-payments-d7-payment-section-express）：钱包按钮（cart 绑定）按需加载
// —— 仅在选中 `express` 入口时渲染（与 CartDrawer 同一引入方式，不新增第二条流程）。
const ExpressCheckoutButton = dynamic(
  () =>
    import("@/components/checkout/ExpressCheckoutButton").then((m) => ({
      default: m.ExpressCheckoutButton,
    })),
  { ssr: false },
);

interface UnifiedCheckoutProps {
  cart: ShoppingCart;
  shippingMethods: DeliveryMethod[];
  countries: Country[];
  isAuthenticated: boolean;
}

interface CouponHandlers {
  onApply: (code: string) => Promise<{ success: boolean; error?: string }>;
  onRemoveDiscount: (
    code: string,
  ) => Promise<{ success: boolean; error?: string }>;
  onRemoveGiftCard: (
    giftCardId: string,
  ) => Promise<{ success: boolean; error?: string }>;
}

/**
 * 折扣码/礼品卡应用后由 BFF 返回的完整 Cart（含 discount_total / tax_total /
 * gift_card 等字段）。未应用时基于 ShoppingCart 构造空壳以满足 CouponCode
 * 对 Cart 类型的读取。
 */
function buildCouponCart(cart: ShoppingCart, discountCart: Cart | null): Cart {
  if (discountCart) return discountCart;
  return {
    ...cart,
    discounts: [],
    gift_card: null,
    discount_total: null,
    display_discount_total: null,
    tax_total: null,
    display_tax_total: null,
    gift_card_total: null,
    display_gift_card_total: null,
    store_credit_total: null,
    display_store_credit_total: null,
    amount_due: null,
    display_total: cart.display_item_total,
  } as unknown as Cart;
}

function UnifiedOrderSummary({
  cart,
  discountCart,
  couponHandlers,
}: {
  cart: ShoppingCart;
  discountCart: Cart | null;
  couponHandlers: CouponHandlers;
}) {
  const t = useTranslations("checkout");
  const tc = useTranslations("common");
  const couponCart = buildCouponCart(cart, discountCart);

  // TOTAL SAVINGS — promotion discounts only（PRD-20260913-checkout-money-contract AC-003：
  // 礼品卡/店铺余额是支付手段，不计入“节省”）。
  const savings = Math.abs(safeParseFloat(couponCart.discount_total) || 0);
  const hasDiscounts =
    discountCart !== null && (savings > 0 || couponCart.discounts?.length > 0);

  const trustBenefits = [
    { icon: RefreshCcw, label: t("benefitMoneyBack") },
    { icon: BadgeCheck, label: t("benefitWarranty") },
    { icon: Headset, label: t("benefitSupport") },
    { icon: Truck, label: t("benefitFreeShipping") },
  ];

  return (
    <div data-testid="unified-order-summary">
      <div className="flex items-center gap-2 mb-4">
        <ShoppingBag className="w-5 h-5 text-gray-500" />
        <h2 className="text-lg font-bold text-gray-900">
          {tc("orderSummary")}
        </h2>
      </div>

      {/* Line items — quantity badge top-right */}
      <div className="space-y-4 pb-6">
        {cart.items.map((item) => (
          <div key={item.id} className="flex items-center gap-4">
            <div className="relative w-[64px] h-[64px] flex-shrink-0">
              <div className="relative w-full h-full rounded-lg overflow-hidden border border-gray-200 bg-gray-50">
                <ProductImage
                  src={item.thumbnail_url}
                  alt={item.name}
                  fill
                  className="object-cover"
                  iconClassName="w-6 h-6"
                />
              </div>
              <div className="absolute -top-2 -right-2 w-5 h-5 bg-[rgba(114,114,114,0.9)] text-white text-[11px] font-medium rounded-full flex items-center justify-center">
                {item.quantity}
              </div>
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium text-gray-900 leading-snug">
                {item.name}
              </p>
              {item.options_text && (
                <p className="text-xs text-gray-500 mt-0.5">
                  {item.options_text}
                </p>
              )}
            </div>
            <div className="text-sm text-gray-900">{item.display_amount}</div>
          </div>
        ))}
      </div>

      {/* Discount code / gift card module */}
      <div className="border-t border-gray-200 pt-4 pb-2">
        <CouponCode
          cart={couponCart}
          onApply={couponHandlers.onApply}
          onRemoveDiscount={couponHandlers.onRemoveDiscount}
          onRemoveGiftCard={couponHandlers.onRemoveGiftCard}
        />
      </div>

      {/* Price breakdown */}
      <dl className="border-t border-gray-200 pt-4 space-y-2">
        <div className="flex justify-between text-sm">
          <dt className="text-gray-700">{tc("subtotal")}</dt>
          <dd className="text-gray-900">{cart.display_item_total}</dd>
        </div>

        {/* Shipping — FREE highlighted green when a zero-cost method is selected */}
        <div className="flex justify-between text-sm">
          <dt className="text-gray-700">{tc("shipping")}</dt>
          <dd className="text-gray-900">{t("shippingCalculatedAtSubmit")}</dd>
        </div>

        {hasDiscounts && safeParseFloat(couponCart.discount_total) !== 0 && (
          <div className="flex justify-between text-sm">
            <dt className="text-gray-700">{tc("discount")}</dt>
            <dd className="text-green-700">
              {couponCart.display_discount_total}
            </dd>
          </div>
        )}

        {safeParseFloat(couponCart.tax_total) > 0 && (
          <div className="flex justify-between text-sm">
            <dt className="text-gray-700">{t("estimatedTaxes")}</dt>
            <dd className="text-gray-900">{couponCart.display_tax_total}</dd>
          </div>
        )}

        {couponCart.gift_card &&
          safeParseFloat(couponCart.gift_card_total) > 0 && (
            <div className="flex justify-between text-sm">
              <dt className="text-gray-700">{tc("giftCard")}</dt>
              <dd className="text-green-700">
                -{couponCart.display_gift_card_total}
              </dd>
            </div>
          )}

        <div className="flex justify-between items-baseline pt-3 border-t border-gray-100">
          <dt className="text-lg font-medium text-gray-900">{tc("total")}</dt>
          <dd className="text-lg font-bold text-gray-900">
            {discountCart?.display_total ?? cart.display_item_total}
          </dd>
        </div>
      </dl>

      {/* TOTAL SAVINGS — green band when any discount applies */}
      {hasDiscounts && savings > 0 && (
        <div
          data-testid="total-savings"
          className="mt-4 rounded-md bg-green-50 px-3 py-2 text-center text-[13px] font-bold text-green-700"
        >
          {t("totalSavings", {
            amount: couponCart.display_total
              ? buildSavingsLabel(couponCart, savings)
              : "",
          })}
        </div>
      )}

      {/* Why Buy From Us — trust benefits */}
      <div className="mt-6 pt-6 border-t border-gray-200">
        <h3 className="text-sm font-bold text-gray-900 mb-3">
          {t("whyBuyFromUs")}
        </h3>
        <ul className="space-y-2">
          {trustBenefits.map(({ icon: Icon, label }) => (
            <li
              key={label}
              className="flex items-center gap-2.5 text-[13px] text-gray-600"
            >
              <span className="flex h-7 w-7 items-center justify-center rounded-full bg-primary-50 shrink-0">
                <Icon className="h-4 w-4 text-primary" aria-hidden="true" />
              </span>
              {label}
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}

/** Format TOTAL SAVINGS amount from the applied discount cart. */
function buildSavingsLabel(cart: Cart, savings: number): string {
  const currency = cart.currency ?? "USD";
  try {
    return new Intl.NumberFormat("en", {
      style: "currency",
      currency,
    }).format(savings);
  } catch {
    return `${currency} ${savings.toFixed(2)}`;
  }
}

/**
 * 下单链路统一化（PRD-20260830-checkout，场景 A/B）：统一下单页 — 购物车模式。
 * 左侧：收件地址 + 商品信息 + 物流方式 + 支付方式选择（选中后显示对应支付表单）；
 * 右侧：订单小结 + Pay Now。
 * 支付流程（同页完成，不跳转独立支付页）：
 *   1) Pay Now → PATCH cart（保存邮箱/地址/物流）→ Carts::Submit 生成 or_ 订单；
 *   2) Stripe（自绘卡字段，PRD-20260831-payments-stripe-自绘卡支付表单）→ 创建
 *      PaymentIntent 会话（pi_..._secret）→ 自绘卡字段 createPaymentMethod +
 *      confirmCardPayment 完成支付；支付失败 → 跳 or_ 支付页可重试；
 *   3) 支付成功 → completeOrderPaymentSession + completeOrder → /order-placed。
 * 非会话类（Check/Store Credit）→ 提交后直接跳完成页（线下收款）。
 * 参考阿里国际站：确认 + 支付同一页面，选择支付方式即显示对应表单。
 */

/** PRD-20260913-checkout-txn-error-routing：库存类错误码（无 PSP 扣款，不进结果页）。 */
const STOCK_ERROR_CODES = new Set([
  "INSUFFICIENT_STOCK",
  "INVENTORY_CHANGED",
  "RESERVATION_EXPIRED",
]);

/**
 * PRD-20260915-checkout B3 FR-001：库存三态的专属标题。/ 恢复中。
 * （`not-ready` 仍用 `checkoutNotReady`，不在此表内。）
 */
const STOCK_ERROR_TITLES: Record<string, string> = {
  "insufficient-stock": "stockInsufficientTitle",
  "inventory-changed": "stockChangedTitle",
  "reservation-expired": "reservationExpiredTitle",
  "reservation-retrying": "reservationRetryingTitle",
};

/**
 * 结算页占位控件开关（PRD-20260914-checkout-placeholder-controls-governance FR-002）。
 *
 * Add-ons（无定价管线）、SMS opt-in（无发送通道）、Save Info（无持久化语义）三项的后端
 * 能力尚不存在 —— 渲染出来等于向顾客做出无效承诺。默认隐藏；组件与文案保留，改为 true
 * 即恢复（回滚成本 = 一个常量）。
 */
const SHOW_PLACEHOLDER_SECTIONS = false;

/**
 * 结算页 Marketing 订阅（PRD-20260914-checkout-placeholder-controls-governance FR-001）：
 * best-effort —— 失败只记日志，绝不阻断下单（NFR-1）。
 */
async function subscribeToMarketing(emailAddress: string): Promise<void> {
  try {
    await fetch("/api/checkout/newsletter", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email: emailAddress }),
    });
  } catch (error) {
    console.warn("[checkout] marketing subscribe failed", error);
  }
}

export function UnifiedCheckout({
  cart,
  shippingMethods,
  countries,
  isAuthenticated,
}: UnifiedCheckoutProps) {
  const t = useTranslations("checkout");
  const tcoupon = useTranslations("coupon");
  const router = useRouter();
  const pathname = usePathname();
  const basePath = extractBasePath(pathname);
  const { setSummaryContent } = useCheckout();

  const paymentMethods: PaymentMethodWithEntries[] = cart.payment_methods ?? [];
  // D7（PRD-20260918-payments-d7-payment-section-express）：cart 页同样按**入口**
  // 渲染（一入口一行）；`entries` 缺失的旧响应由 `paymentEntriesFor` 回退单入口。
  const paymentOptions = useMemo(
    () =>
      paymentMethods.flatMap((method) =>
        paymentEntriesFor(method).map((entry) => ({ entry, method })),
      ),
    [paymentMethods],
  );
  const [email, setEmail] = useState(cart.email ?? "");
  const [emailError, setEmailError] = useState<string | null>(null);
  // PRD-20260914-checkout-placeholder-controls-governance FR-001：Marketing 已接线
  // （提交时 best-effort 订阅，失败不阻断下单）。
  const [marketingOptIn, setMarketingOptIn] = useState(true);
  // SMS opt-in — 占位（无 SMS 后端）：仅在 SHOW_PLACEHOLDER_SECTIONS 下渲染。
  const [smsOptIn, setSmsOptIn] = useState(false);
  const [address, setAddress] = useState<AddressFormData>(
    cart.shipping_address
      ? addressToFormData(cart.shipping_address)
      : emptyAddress,
  );
  const [shippingMethodId, setShippingMethodId] = useState(
    cart.shipping_method_id ?? "",
  );
  // PRD: Credit card 默认选中（优先 Stripe，否则回退第一个可用方式）。
  // D7：选择粒度 = 入口（`option_id`）；默认取首个 `inline` 入口（卡），否则首个入口。
  const [selectedOptionId, setSelectedOptionId] = useState(
    paymentOptions.find((o) => o.entry.frontend_kind === "inline")?.entry
      .option_id ??
      paymentOptions[0]?.entry.option_id ??
      "",
  );
  const [states, setStates] = useState<State[]>([]);
  const [loadingStates, setLoadingStates] = useState(false);

  // D7 补口 3（2026-09-18）：**设备侧**不可用的入口（`option_id` → 原因）。
  // 服务端不知道设备能力，只有客户端知道 → 这里只**标注 + 回落**，**不删除**入口
  // （入口集合仍由服务端确定，守住 D8/D15c 红线）；行保持可点击 = 重试（见下）。
  const [unavailableEntries, setUnavailableEntries] = useState<
    Partial<Record<string, WalletUnavailableReason>>
  >({});
  /** 每个入口的重试令牌：递增 → 钱包槽位 `key` 变化 → 重新挂载并重新探测。 */
  const [walletProbeTokens, setWalletProbeTokens] = useState<
    Record<string, number>
  >({});
  const [walletProcessing, setWalletProcessing] = useState(false);
  /** 钱包组件上报设备能力：可用 → 清除标注（可恢复）；不可用 → 标注 + 回落 + 提示。 */
  const handleWalletAvailability = useCallback(
    (optionId: string, result: WalletAvailability) => {
      if (result.state === "available") {
        setUnavailableEntries((prev) => {
          if (!(optionId in prev)) return prev;
          const next = { ...prev };
          delete next[optionId];
          return next;
        });
        return;
      }
      if (result.state !== "unavailable") return;
      const reason = result.reason ?? "device";
      setUnavailableEntries((prev) => ({ ...prev, [optionId]: reason }));
      setSelectedOptionId((current) => {
        if (current !== optionId) return current;
        const usable = paymentOptions.filter(
          (o) =>
            o.entry.option_id !== optionId &&
            !(o.entry.option_id in unavailableEntries),
        );
        const fallback =
          usable.find((o) => o.entry.frontend_kind === "inline") ?? usable[0];
        return fallback?.entry.option_id ?? current;
      });
      toast.error(
        reason === "timeout"
          ? t("walletRetryHint")
          : reason === "unsupported" || reason === "unconfigured"
            ? t("walletUnsupported")
            : t("walletUnavailable"),
      );
    },
    [paymentOptions, t, unavailableEntries],
  );

  // ── Billing address（PRD 3.6：Use shipping address as billing address，
  //    默认勾选；取消时展开独立账单地址表单）──────────────────────────
  // PRD-20260913-checkout-billing-mode FR-010：初值按购物车已有的独立账单地址推导，
  // 避免默认「同配送」在提交时静默清除用户此前填写的账单地址。
  const [useShippingForBilling, setUseShippingForBilling] = useState(
    !cart.billing_address,
  );
  const [billAddress, setBillAddress] = useState<AddressFormData>(
    cart.billing_address
      ? addressToFormData(cart.billing_address)
      : emptyAddress,
  );
  const [billStates, setBillStates] = useState<State[]>([]);
  const [loadingBillStates, setLoadingBillStates] = useState(false);

  // ── 折扣码 / 礼品卡（右栏 Order summary，BFF /api/checkout/coupon）──
  const [discountCart, setDiscountCart] = useState<Cart | null>(null);

  // ── 支付（同页完成）──────────────────────────────────────────────
  // 会话类支付方式需创建订单支付会话获取 client_secret；订单 id 存 ref 防重入
  const [payProcessing, setPayProcessing] = useState(false);
  const [processingStage, setProcessingStage] = useState<
    "idle" | "submitting" | "confirming"
  >("idle");
  const cardFormRef = useRef<CardPaymentFormHandle | null>(null);
  const orderIdRef = useRef<string | null>(null);
  // PRD-20260913-checkout-txn-error-routing：页内错误提示（库存类 / 未就绪）。
  const [payError, setPayError] = useState<{
    kind:
      | "insufficient-stock"
      | "inventory-changed"
      | "reservation-expired"
      | "reservation-retrying"
      | "not-ready";
    message: string;
  } | null>(null);
  /**
   * 预留过期自动重试守卫（PRD-20260915-checkout B3 FR-001，用户 2026-09-15 决策）：
   * **仅** `RESERVATION_EXPIRED` 允许自动重试一次；失败后回落为手动动作，绝不循环。
   */
  const stockRetryRef = useRef(false);
  /** 自动重试触发器（需等 handlePayNow 的 finally 复位 payProcessing）。 */
  const [reservationRetryPending, setReservationRetryPending] = useState(false);
  // biome-ignore lint/correctness/useExhaustiveDependencies: 触发条件只看「待重试」与「本轮已结束」（handlePayNow 每次渲染都会重建，不能进依赖）
  useEffect(() => {
    // 入口守卫 `if (!canSubmit || payProcessing || !selectedMethod) return;`
    // 会拦掉同一轮内的递归调用 → 等 payProcessing 落回 false 再重试。
    if (!reservationRetryPending || payProcessing) return;
    setReservationRetryPending(false);
    void handlePayNow();
  }, [reservationRetryPending, payProcessing]);
  // PRD-20260914-checkout-quote-confirmation-loop：报价漂移的页内确认
  // （零跳转、零自动扣款；用户看得到 Shipping / Promotion / Amount due 的旧→新）
  const [quoteDiff, setQuoteDiff] = useState<{
    rows: QuoteDiffRow[];
    hasQuote: boolean;
  } | null>(null);
  /**
   * PRD-20260915-checkout-单页两段语义：Prepare 之后的「最终金额确认区」。
   * 点 Pay Now 先 prepare（update + submit → Order 权威报价），金额展示后才发起 Pay。
   */
  const [preparedOrder, setPreparedOrder] = useState<{
    id: string;
    quote: CheckoutQuote | null;
  } | null>(null);

  const selectedOption =
    paymentOptions.find((o) => o.entry.option_id === selectedOptionId) ??
    paymentOptions[0];
  const selectedMethod = selectedOption?.method;
  const selectedEntry = selectedOption?.entry;
  const paymentMethodId = selectedMethod?.id ?? "";
  const isSessionBased = selectedMethod?.session_required === true;
  const isStripe = selectedMethod?.type === "stripe";
  // D7：形态由服务端投影的 `frontend_kind` 决定（钱包 = express；卡字段 = inline）
  const selectedIsWallet = selectedEntry?.frontend_kind === "express";
  const selectedIsInline =
    !selectedIsWallet && selectedEntry?.frontend_kind === "inline";

  /** 前台不支持的钱包 kind（如 paypal / shop_pay）只标注一次，避免反复 toast。 */
  const unsupportedHandledRef = useRef<Set<string>>(new Set());
  useEffect(() => {
    if (selectedEntry?.frontend_kind !== "express") return;
    if (isExpressWalletKind(selectedEntry.method_key)) return;
    if (unsupportedHandledRef.current.has(selectedEntry.option_id)) return;
    unsupportedHandledRef.current.add(selectedEntry.option_id);
    handleWalletAvailability(selectedEntry.option_id, {
      state: "unavailable",
      reason: "unsupported",
    });
  }, [selectedEntry, handleWalletAvailability]);

  // 折扣码回调（BFF 保持 SDK 凭证/guest token 服务端）
  const handleCouponApply = useCallback(
    async (code: string) => {
      try {
        const res = await fetch("/api/checkout/coupon", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ cart_id: cart.id, code, kind: "discount" }),
        });
        const data = (await res.json()) as {
          cart?: Cart;
          error?: unknown;
        };
        if (!res.ok || !data.cart) {
          return {
            success: false,
            error: normalizeErrorMessage(data.error, tcoupon("applyFailed")),
          };
        }
        setDiscountCart(data.cart);
        return { success: true };
      } catch {
        return { success: false, error: tcoupon("applyFailed") };
      }
    },
    [cart.id, tcoupon],
  );

  const handleCouponRemove = useCallback(
    async (code: string) => {
      try {
        const res = await fetch("/api/checkout/coupon", {
          method: "DELETE",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ cart_id: cart.id, code, kind: "discount" }),
        });
        const data = (await res.json()) as {
          cart?: Cart;
          error?: unknown;
        };
        if (!res.ok || !data.cart) {
          return {
            success: false,
            error: normalizeErrorMessage(data.error, tcoupon("applyFailed")),
          };
        }
        setDiscountCart(data.cart);
        return { success: true };
      } catch {
        return { success: false, error: tcoupon("applyFailed") };
      }
    },
    [cart.id, tcoupon],
  );

  const handleGiftCardRemove = useCallback(
    async (giftCardId: string) => {
      try {
        const res = await fetch("/api/checkout/coupon", {
          method: "DELETE",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            cart_id: cart.id,
            gift_card_id: giftCardId,
            kind: "gift_card",
          }),
        });
        const data = (await res.json()) as {
          cart?: Cart;
          error?: unknown;
        };
        if (!res.ok || !data.cart) {
          return {
            success: false,
            error: normalizeErrorMessage(data.error, tcoupon("applyFailed")),
          };
        }
        setDiscountCart(data.cart);
        return { success: true };
      } catch {
        return { success: false, error: tcoupon("applyFailed") };
      }
    },
    [cart.id, tcoupon],
  );

  // 折扣码 handlers 用 ref 保持最新引用，避免 useTranslations 每次渲染产生新
  // 函数导致 summary 发布 effect 依赖变化 → setState 无限循环。
  const couponHandlersRef = useRef<CouponHandlers>({
    onApply: handleCouponApply,
    onRemoveDiscount: handleCouponRemove,
    onRemoveGiftCard: handleGiftCardRemove,
  });
  useLayoutEffect(() => {
    couponHandlersRef.current = {
      onApply: handleCouponApply,
      onRemoveDiscount: handleCouponRemove,
      onRemoveGiftCard: handleGiftCardRemove,
    };
  });

  // The checkout route group owns the real desktop sticky sidebar. Publish the
  // summary there instead of nesting another three-column grid inside its main
  // content column.
  useLayoutEffect(() => {
    setSummaryContent(
      <UnifiedOrderSummary
        cart={cart}
        discountCart={discountCart}
        couponHandlers={couponHandlersRef.current}
      />,
    );
    return () => setSummaryContent(null);
  }, [cart, discountCart, setSummaryContent]);

  // 国家变更 → 加载州/省（配送地址）
  useEffect(() => {
    if (!address.country_iso) {
      setStates([]);
      return;
    }
    let active = true;
    setLoadingStates(true);
    getCountry(address.country_iso)
      .then((country) => {
        if (active) setStates(country?.states ?? []);
      })
      .catch(() => setStates([]))
      .finally(() => {
        if (active) setLoadingStates(false);
      });
    return () => {
      active = false;
    };
  }, [address.country_iso]);

  // 国家变更 → 加载州/省（账单地址）
  useEffect(() => {
    if (!billAddress.country_iso) {
      setBillStates([]);
      return;
    }
    let active = true;
    setLoadingBillStates(true);
    getCountry(billAddress.country_iso)
      .then((country) => {
        if (active) setBillStates(country?.states ?? []);
      })
      .catch(() => setBillStates([]))
      .finally(() => {
        if (active) setLoadingBillStates(false);
      });
    return () => {
      active = false;
    };
  }, [billAddress.country_iso]);

  // 邮箱失焦校验（PRD 3.2）
  const handleEmailBlur = useCallback(() => {
    const trimmed = email.trim();
    if (!trimmed) {
      setEmailError(null);
      return;
    }
    const valid = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmed);
    setEmailError(valid ? null : t("invalidEmail"));
  }, [email, t]);

  const onAddressChange = (field: keyof AddressFormData, value: string) => {
    setAddress((prev) => {
      const next = { ...prev, [field]: value };
      // 国家变更清空州/省
      if (field === "country_iso") {
        next.state_abbr = "";
        next.state_name = "";
      }
      return next;
    });
  };

  const onBillAddressChange = (field: keyof AddressFormData, value: string) => {
    setBillAddress((prev) => {
      const next = { ...prev, [field]: value };
      // 国家变更清空州/省
      if (field === "country_iso") {
        next.state_abbr = "";
        next.state_name = "";
      }
      return next;
    });
  };

  // 地址完整性校验（必要字段）
  const addressComplete = Boolean(
    address.first_name &&
      address.last_name &&
      address.address1 &&
      address.city &&
      address.postal_code &&
      address.country_iso &&
      (address.state_abbr || address.state_name),
  );
  // PRD-20260913-checkout-billing-mode FR-011：自定义账单地址完整性
  const billAddressComplete = Boolean(
    billAddress.first_name &&
      billAddress.last_name &&
      billAddress.address1 &&
      billAddress.city &&
      billAddress.postal_code &&
      billAddress.country_iso,
  );
  // 注意：email 不参与 canSubmit——PRD 3.2 要求点击 Pay now 时邮箱为空要
  // 弹提示（而非直接 disabled），由 handlePayNow 前置校验处理。
  const canSubmit =
    addressComplete &&
    shippingMethodId.length > 0 &&
    paymentMethodId.length > 0;

  const handleCardReady = useCallback((handle: CardPaymentFormHandle) => {
    cardFormRef.current = handle;
  }, []);

  /** Prepare / Pay 共用的结账载荷（邮箱 / 地址 / 物流 / 账单语义）。 */
  const buildCheckoutPayload = () => ({
    email: email || undefined,
    shipping_address: formDataToAddress(address),
    shipping_method_id: shippingMethodId || undefined,
    // PRD-20260913-checkout-billing-mode FR-009：发送服务端显式账单语义
    // （不再发 `use_shipping` —— 旧字段在 Store API 参数白名单中被丢弃）。
    ...(useShippingForBilling
      ? { billing_mode: "same_as_shipping" as const }
      : {
          billing_mode: "custom" as const,
          billing_address: formDataToAddress(billAddress),
        }),
  });

  /**
   * PRD-20260915-checkout-单页两段语义 **第一段 Prepare**：保存填写内容并提交订单，
   * 取回 Order 权威报价（含运费/税费）。返回值后页面据此展示确认区；
   * 失败（含未建单）返回 null（已提示用户）。
   */
  const prepareOrder = async (): Promise<{
    id: string;
    quote: CheckoutQuote | null;
  } | null> => {
    setPayError(null);
    setPayProcessing(true);
    setProcessingStage("submitting");
    try {
      const response = await fetch("/api/checkout/prepare", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          cart_id: cart.id,
          checkout: buildCheckoutPayload(),
        }),
      });
      const result = (await response.json()) as {
        order_id?: string;
        order?: { id?: string };
        quote?: unknown;
        error?: unknown;
      };
      const orderId = result.order_id ?? result.order?.id;

      if (!response.ok || !orderId) {
        toast.error(normalizeErrorMessage(result.error, t("checkoutError")));
        return null;
      }

      orderIdRef.current = orderId;
      writeQuoteSnapshot(cart.id, result.quote);
      return { id: orderId, quote: normalizeQuote(result.quote) };
    } catch (error) {
      toast.error(error instanceof Error ? error.message : t("checkoutError"));
      return null;
    } finally {
      setPayProcessing(false);
      setProcessingStage("idle");
    }
  };

  // The same-origin Route Handler performs Cart update + idempotent submit +
  // PaymentSession start without a Server Action/RSC refresh. Stripe confirmation
  // therefore remains in this single Pay click.
  const handlePayNow = async () => {
    if (!canSubmit || payProcessing || !selectedMethod) return;
    // PRD 3.2 异常：点击 Pay now 时邮箱为空 → 提示
    if (!email.trim()) {
      setEmailError(t("emailRequired"));
      toast.error(t("emailRequired"));
      return;
    }
    if (emailError) {
      toast.error(emailError);
      return;
    }
    // PRD-20260913-checkout-billing-mode FR-011：取消「同配送」时必须提供完整
    // 账单地址（服务端 FR-003 同样拦截，此处避免无谓往返）。
    if (!useShippingForBilling && !billAddressComplete) {
      toast.error(t("billingAddressIncomplete"));
      return;
    }
    if (isSessionBased && isStripe && !cardFormRef.current?.validate()) return;

    // 两段语义（§0.1-1/2）：首次点击先 Prepare 拿 Order 权威报价；
    // 有权威金额 → 展示页内确认区，等用户确认再 Pay；
    // 无权威金额（服务端降级/读取失败）→ 直接 Pay，金额由支付控件自身展示。
    let target = preparedOrder;
    if (!target) {
      const prepared = await prepareOrder();
      if (!prepared) return;
      // 订单已建：必须记住它，否则重试（如预留过期自动重试）会重新提交购物车。
      setPreparedOrder(prepared);
      // 有权威金额 → 等用户确认后再 Pay；无权威金额（降级）→ 直接 Pay。
      if (prepared.quote) return;
      target = prepared;
    }
    const orderId = target.id;
    const confirmedQuote = target.quote;

    setPayError(null);
    setPayProcessing(true);
    setProcessingStage("submitting");
    try {
      const response = await fetch("/api/checkout/start", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          // 两段语义 Pay：只对 Prepare 建好的订单启动交易（不再 update/submit）。
          order_id: orderId,
          payment_method_id: selectedMethod.id,
          // D7：入口（method kind）—— 服务端按同一入口集合复算可用性。
          ...(selectedEntry?.method_key
            ? { option_kind: selectedEntry.method_key }
            : {}),
          session_required: isSessionBased,
          ...(isStripe && { payment_mode: "payment_intent" }),
          // PRD-20260914-checkout-quote-confirmation-loop FR-004：
          // 带回客户端已确认的报价版本（来自 Prepare 返回的 Order 权威报价）。
          ...expectedVersions(confirmedQuote ?? readQuoteSnapshot(cart.id)),
        }),
      });
      const result = (await response.json()) as {
        order?: { id: string };
        order_id?: string;
        session?: {
          id: string;
          external_data?: Record<string, unknown>;
        } | null;
        /** PRD-20260914-checkout-quote-confirmation-loop：当前报价（成功/冲突均有） */
        quote?: unknown;
        error?: unknown;
      };
      const targetOrderId = result.order?.id ?? result.order_id;
      if (targetOrderId) orderIdRef.current = targetOrderId;

      // PRD-20260914-checkout-placeholder-controls-governance FR-001 / NFR-1：
      // 营销订阅 best-effort —— 仅在订单已创建时触发；失败只记日志，绝不阻断下单。
      if (response.ok && targetOrderId && marketingOptIn && email) {
        void subscribeToMarketing(email);
      }

      if (!response.ok || !targetOrderId) {
        // PRD-20260913-checkout-txn-error-routing：按服务端 code 分流（FR-002..FR-007）。
        // 展示文案一律经 normalizeErrorMessage（React #31 防线，bugfix 2026-09-06）。
        const message = normalizeErrorMessage(result.error, t("checkoutError"));
        const errorCode = extractErrorCode(result.error);

        if (!targetOrderId) {
          toast.error(message);
          return;
        }
        if (
          errorCode === "quote_changed" ||
          errorCode === "checkout_version_conflict"
        ) {
          // PRD-20260914-checkout-quote-confirmation-loop FR-005/FR-006：
          // 报价漂移 → **留在页内**展示逐步差异并要求重新点击
          // （绝不跳转、绝不自动扣款；取代 PRD-20260913 的 or_ 跳转分支）。
          const latest = normalizeQuote(result.quote);
          setQuoteDiff({
            rows: diffQuotes(readQuoteSnapshot(cart.id), latest),
            hasQuote: latest !== null,
          });
          // 用服务端最新报价覆盖快照：用户重新点击时即携带新版本
          writeQuoteSnapshot(cart.id, result.quote);
          setPayError(null);
          return;
        }
        if (errorCode === "INVENTORY_RECOVERY_REQUIRED") {
          // FR-004/AC-004：已收款待恢复 → 结果页“无需重复支付”
          router.replace(
            `${basePath}/payment-result/${targetOrderId}?notice=recovery`,
          );
          return;
        }
        if (errorCode === "transaction_not_payable") {
          // FR-005：不可支付态 → 结果页“订单处理中”
          router.replace(
            `${basePath}/payment-result/${targetOrderId}?notice=processing`,
          );
          return;
        }
        if (errorCode && STOCK_ERROR_CODES.has(errorCode)) {
          // FR-003/AC-002/003：库存类（无 PSP 扣款）→ 页内提示 + 返回购物车
          // PRD-20260915-checkout B3 FR-001：三态各自专属文案与动作。
          if (errorCode === "RESERVATION_EXPIRED" && !stockRetryRef.current) {
            // 用户决策：预留过期允许自动重试**一次**（仅重走库存确认/启动，
            // 幂等于同一订单 —— 不新建 Order / Transaction）。
            stockRetryRef.current = true;
            setPayError({ kind: "reservation-retrying", message });
            setReservationRetryPending(true);
            return;
          }
          setPayError({
            kind:
              errorCode === "RESERVATION_EXPIRED"
                ? "reservation-expired"
                : errorCode === "INVENTORY_CHANGED"
                  ? "inventory-changed"
                  : "insufficient-stock",
            message,
          });
          return;
        }
        if (errorCode === "checkout_not_ready") {
          // FR-006/AC-008：未就绪 → 页内提示（无 CTA）
          setPayError({ kind: "not-ready", message });
          return;
        }
        // FR-007/AC-009：未知 code 且有 order_id → 保留现状跳结果页（防回归）
        router.replace(`${basePath}/payment-result/${targetOrderId}`);
        return;
      }

      // FR-002：成功 → 刷新报价快照（下一次点击携带该版本；形状不合法则静默忽略）
      writeQuoteSnapshot(cart.id, result.quote);
      const session = result.session;
      if (isSessionBased && isStripe && session) {
        const clientSecret = session.external_data?.client_secret;
        if (typeof clientSecret !== "string") {
          router.replace(
            `${basePath}/payment-result/${targetOrderId}?session=${session.id}`,
          );
          return;
        }

        setProcessingStage("confirming");
        await cardFormRef.current?.confirmPayment(
          decodeURIComponent(clientSecret),
        );

        // Complete on both success and provider rejection so the server records
        // the authoritative terminal session state for the result page.
        await fetch("/api/checkout/start", {
          method: "PATCH",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            order_id: targetOrderId,
            session_id: session.id,
          }),
        }).catch(() => null);

        router.replace(
          `${basePath}/payment-result/${targetOrderId}?session=${session.id}`,
        );
        return;
      }

      router.replace(`${basePath}/payment-result/${targetOrderId}`);
    } catch (error) {
      const targetOrderId = orderIdRef.current;
      if (targetOrderId) {
        router.replace(`${basePath}/payment-result/${targetOrderId}`);
      } else {
        toast.error(
          error instanceof Error ? error.message : t("checkoutError"),
        );
      }
    } finally {
      setPayProcessing(false);
      setProcessingStage("idle");
    }
  };

  // D7：入口切换由 `PaymentSection` 直接回调 `setSelectedOptionId`；
  // 旧的 provider 级 setter 已不再需要（避免与入口粒度选择不一致）。

  return (
    <div className="mx-auto max-w-6xl px-4 sm:px-6 lg:px-8 py-8">
      <h1 className="text-3xl font-bold text-gray-900 mb-8">
        {t("orderConfirmation")}
      </h1>

      {/* PRD-20260914-checkout-quote-confirmation-loop FR-005：报价漂移的页内确认 */}
      {quoteDiff && (
        <div
          role="status"
          data-testid="checkout-quote-diff"
          className="mb-8 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3"
        >
          <p className="text-sm font-semibold text-amber-900">
            {t("quoteChangedTitle")}
          </p>
          <p className="mt-1 text-sm text-amber-800">{t("quoteChangedBody")}</p>
          {quoteDiff.rows.length > 0 && (
            <dl className="mt-3 space-y-1 text-sm">
              {quoteDiff.rows.map((row) => (
                <div
                  key={row.key}
                  data-testid={`quote-diff-${row.key}`}
                  data-changed={row.changed}
                  className="flex items-center justify-between gap-4"
                >
                  <dt className="text-amber-900">
                    {row.key === "shipping"
                      ? t("quoteRowShipping")
                      : row.key === "promotion"
                        ? t("quoteRowPromotion")
                        : t("quoteRowAmountDue")}
                  </dt>
                  <dd className="text-amber-900">
                    <span className="line-through opacity-70">
                      {row.before ?? "—"}
                    </span>
                    <span className="mx-1">→</span>
                    <span className="font-semibold">{row.after ?? "—"}</span>
                  </dd>
                </div>
              ))}
            </dl>
          )}
          <p className="mt-3 text-sm font-medium text-amber-900">
            {t("quoteConfirmAgain")}
          </p>
        </div>
      )}

      {/* PRD-20260913-checkout-txn-error-routing：库存类 / 未就绪错误的页内提示 */}
      {payError && (
        <div
          role="alert"
          data-testid="checkout-error-notice"
          className="mb-8 rounded-xl border border-red-200 bg-red-50 px-4 py-3"
        >
          <p className="text-sm font-semibold text-red-800">
            {t(STOCK_ERROR_TITLES[payError.kind] ?? "checkoutNotReady")}
          </p>
          <p className="mt-1 text-sm text-red-700">{payError.message}</p>
          {payError.kind === "insufficient-stock" && (
            <Button asChild variant="outline" size="sm" className="mt-3">
              <Link href={`${basePath}/cart`}>{t("returnToCart")}</Link>
            </Button>
          )}
          {payError.kind === "inventory-changed" && (
            <>
              <p className="mt-1 text-sm text-red-700">
                {t("stockChangedHint")}
              </p>
              <Button asChild variant="outline" size="sm" className="mt-3">
                <Link href={`${basePath}/cart`}>{t("reviewCart")}</Link>
              </Button>
            </>
          )}
          {payError.kind === "reservation-expired" && (
            <>
              <p className="mt-1 text-sm text-red-700">
                {t("reservationExpiredHint")}
              </p>
              <Button
                type="button"
                variant="outline"
                size="sm"
                className="mt-3"
                onClick={() => {
                  void handlePayNow();
                }}
              >
                {t("retryInventoryCheck")}
              </Button>
            </>
          )}
        </div>
      )}

      <div className="space-y-8">
        {/* 1 Contact — 邮箱 + 登录入口 + 营销订阅 */}
        <section className="bg-white rounded-xl border border-gray-200 p-6">
          <div className="flex items-baseline justify-between mb-4">
            <CheckoutSectionTitle step={1} title={t("contactInformation")} />
            {!isAuthenticated && (
              <div className="flex items-center gap-2.5 text-[13px]">
                <Link
                  href={`${basePath}/account?redirect=${encodeURIComponent(pathname)}`}
                  className="text-gray-700 underline underline-offset-2 hover:text-black"
                >
                  {t("signIn")}
                </Link>
                <span className="text-gray-300" aria-hidden="true">
                  /
                </span>
                <Link
                  href={`${basePath}/account/register`}
                  className="text-gray-700 underline underline-offset-2 hover:text-black"
                >
                  {t("signUp")}
                </Link>
              </div>
            )}
          </div>
          <Input
            type="email"
            value={email}
            onChange={(e) => {
              setEmail(e.target.value);
              if (emailError) setEmailError(null);
            }}
            onBlur={handleEmailBlur}
            placeholder={t("emailPlaceholder")}
            aria-label={t("email")}
            aria-invalid={!!emailError}
            data-testid="checkout-email"
          />
          {emailError && (
            <p
              className="mt-1 text-xs text-red-600"
              role="alert"
              data-testid="email-error"
            >
              {emailError}
            </p>
          )}
          {/* Marketing subscription — UI placeholder (backend not integrated) */}
          <label
            className="flex items-center gap-2.5 mt-3 cursor-pointer"
            data-testid="marketing-opt-in"
          >
            <Checkbox
              checked={marketingOptIn}
              onCheckedChange={(checked) => setMarketingOptIn(checked === true)}
            />
            <span className="text-[13px] text-gray-600">
              {t("marketingOptIn")}
            </span>
          </label>
        </section>

        {/* 2 Delivery address */}
        <section className="bg-white rounded-xl border border-gray-200 p-6">
          <CheckoutSectionTitle
            step={2}
            title={t("shippingAddress")}
            className="mb-4"
          />
          <AddressFormFields
            address={address}
            countries={countries}
            states={states}
            loadingStates={loadingStates}
            onChange={onAddressChange}
            idPrefix="unified"
            showSmsOptIn={SHOW_PLACEHOLDER_SECTIONS}
            smsOptIn={smsOptIn}
            onSmsOptInChange={setSmsOptIn}
          />
        </section>

        {/* 商品信息 */}
        <section className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-lg font-bold text-gray-900 mb-4">{t("items")}</h2>
          <div className="space-y-4 divide-y divide-gray-100">
            {cart.items.map((item) => (
              <div key={item.id} className="flex gap-4 pt-4 first:pt-0">
                <div className="relative w-16 h-16 bg-gray-100 rounded-lg overflow-hidden shrink-0">
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
                  {item.display_amount}
                </p>
              </div>
            ))}
          </div>
        </section>

        {/* 3 Shipping method */}
        {shippingMethods.length > 0 && (
          <section className="bg-white rounded-xl border border-gray-200 p-6">
            <CheckoutSectionTitle
              step={3}
              title={t("shippingMethod")}
              className="mb-4"
            />
            {/* PRD 3.4：配送选项变化黄色警告框（占位，后端推送变更信号后驱动） */}
            <div
              className="flex items-start gap-2.5 rounded-md border border-amber-200 bg-amber-50 px-4 py-3 mb-4"
              data-testid="shipping-options-changed"
            >
              <CircleAlert
                className="h-4 w-4 text-amber-500 shrink-0 mt-0.5"
                aria-hidden="true"
              />
              <span className="text-[13px] text-amber-800">
                {t("shippingOptionsChanged")}
              </span>
            </div>
            <div className="flex flex-col gap-3">
              {shippingMethods.map((method) => (
                <label
                  key={method.id}
                  className="flex items-center gap-3 p-3 rounded-lg border border-gray-200 cursor-pointer hover:border-indigo-300"
                >
                  <input
                    type="radio"
                    name="shipping-method"
                    checked={shippingMethodId === method.id}
                    onChange={() => setShippingMethodId(method.id ?? "")}
                    className="w-4 h-4 text-indigo-600 focus:ring-indigo-500"
                  />
                  <div className="flex-1">
                    <p className="font-medium text-gray-900">{method.name}</p>
                    {method.display_estimated_price && (
                      <p className="text-sm text-gray-500">
                        {method.display_estimated_price}
                      </p>
                    )}
                  </div>
                </label>
              ))}
            </div>
            <p className="text-xs text-gray-500 mt-2">
              {t("shippingRestrictionNote")}
            </p>
          </section>
        )}

        {/* 4 Add-ons — value-added service (UI placeholder) */}
        <section className="bg-white rounded-xl border border-gray-200 p-6">
          {SHOW_PLACEHOLDER_SECTIONS && <AddOnsSection />}
        </section>

        {/* 5 Payment — 支付方式选择 + 对应表单 */}
        <section className="bg-white rounded-xl border border-gray-200 p-6">
          <CheckoutSectionTitle step={5} title={t("paymentMethod")} />
          <p className="text-sm text-gray-500 mt-1 mb-4">
            {t("secureTransactions")}
          </p>
          {paymentMethods.length === 0 ? (
            <div className="rounded-sm border bg-gray-50 px-4 py-8 text-center">
              <CreditCard
                className="w-10 h-10 text-gray-300 mx-auto mb-3"
                strokeWidth={1.5}
              />
              <p className="text-sm text-gray-500">{t("noPaymentMethods")}</p>
            </div>
          ) : (
            <PaymentSection
              methods={paymentMethods}
              selectedOptionId={selectedOptionId}
              onSelect={(entry, method) => {
                // D7 补口 3：重新点已标注的入口 = **重试**（清除标注 + 重新探测）
                if (entry.option_id in unavailableEntries) {
                  setUnavailableEntries((prev) => {
                    const next = { ...prev };
                    delete next[entry.option_id];
                    return next;
                  });
                  setWalletProbeTokens((prev) => ({
                    ...prev,
                    [entry.option_id]: (prev[entry.option_id] ?? 0) + 1,
                  }));
                }
                setWalletProcessing(false);
                setSelectedOptionId(entry.option_id);
                void method;
              }}
              emptyLabel={t("noPaymentMethods")}
              unavailableEntries={unavailableEntries}
            >
              {/* 形态槽：express → 钱包按钮（cart 绑定，复用 canonical 编排）；
                  inline → 自绘卡字段；manual → 仅说明行 */}
              {selectedIsWallet &&
              selectedMethod &&
              selectedEntry &&
              isExpressWalletKind(selectedEntry.method_key) ? (
                <div className="mt-4 rounded-lg border border-gray-200 p-4">
                  {/* 钱包按钮是 cart 绑定组件（复用 canonical 编排）——两页拿到的都是
                      同一份服务端 cart 载荷（ShoppingCart/Cart 仅命名差异） */}
                  <ExpressCheckoutButton
                    key={`${selectedEntry.option_id}:${
                      walletProbeTokens[selectedEntry.option_id] ?? 0
                    }`}
                    cart={cart as unknown as Cart}
                    basePath={basePath}
                    maxColumns={1}
                    showDivider={false}
                    entryKind={selectedEntry.method_key}
                    clientConfig={selectedMethod.client_config ?? null}
                    onAvailabilityChange={(result) =>
                      handleWalletAvailability(selectedEntry.option_id, result)
                    }
                    onProcessingChange={setWalletProcessing}
                    onComplete={async () => {
                      router.push(`${basePath}/cart`);
                    }}
                  />
                </div>
              ) : null}
            </PaymentSection>
          )}

          {/* 选中入口后的对应表单 */}
          {selectedMethod ? (
            <div className="mt-4">
              {selectedIsInline && isSessionBased && isStripe ? (
                // Stripe 自绘卡字段（PRD-20260831-payments-stripe-自绘卡支付表单）：
                // 纯 HTML 卡字段立即渲染，不依赖 client_secret / js.stripe.com iframe。
                <div className="rounded-lg border border-gray-200 p-4">
                  {/* PALLAS-CUSTOM: D10 —— 服务端下发 client_config（回落 NEXT_PUBLIC_*） */}
                  <CardPaymentForm
                    onReady={handleCardReady}
                    clientConfig={selectedMethod?.client_config ?? null}
                  />
                  {/* PRD 3.6：Use shipping address as billing address（默认勾选） */}
                  <div className="mt-4">
                    <label
                      className="flex items-center gap-2.5 cursor-pointer"
                      data-testid="billing-use-shipping"
                    >
                      <Checkbox
                        checked={useShippingForBilling}
                        onCheckedChange={(checked) =>
                          setUseShippingForBilling(checked === true)
                        }
                      />
                      <span className="text-sm text-gray-900">
                        {t("sameAsShipping")}
                      </span>
                    </label>
                    {!useShippingForBilling && (
                      <div className="mt-4">
                        <h3 className="text-sm font-bold text-gray-900 mb-3">
                          {t("billingAddress")}
                        </h3>
                        <AddressFormFields
                          address={billAddress}
                          countries={countries}
                          states={billStates}
                          loadingStates={loadingBillStates}
                          onChange={onBillAddressChange}
                          idPrefix="bill"
                        />
                      </div>
                    )}
                  </div>
                </div>
              ) : selectedIsWallet ? null : isSessionBased ? (
                // 其他会话类支付方式（PayPal/Adyen 等）：同页支付或跳转由网关决定
                <p className="text-sm text-gray-500">{t("processing")}</p>
              ) : (
                // 非会话类（Check/Store Credit）：线下收款说明
                <div className="rounded-sm border border-gray-200 bg-gray-50 px-4 py-3 text-sm text-gray-600">
                  {t("manualPaymentInfo")}
                </div>
              )}
            </div>
          ) : null}

          {preparedOrder?.quote ? (
            <div
              data-testid="order-quote-confirm"
              className="mt-6 rounded-sm border border-gray-200 bg-gray-50 px-4 py-3"
            >
              <h3 className="text-sm font-bold text-gray-900">
                {t("quoteConfirmTitle")}
              </h3>
              <dl className="mt-2 space-y-1 text-sm">
                <div className="flex justify-between">
                  <dt className="text-gray-500">{t("quoteDelivery")}</dt>
                  <dd className="text-gray-900" data-testid="quote-delivery">
                    {preparedOrder.quote?.display_delivery_total ?? "—"}
                  </dd>
                </div>
                <div className="flex justify-between">
                  <dt className="text-gray-500">{t("quoteDiscount")}</dt>
                  <dd className="text-gray-900" data-testid="quote-discount">
                    {preparedOrder.quote?.display_discount_total ?? "—"}
                  </dd>
                </div>
                <div className="flex justify-between font-medium">
                  <dt className="text-gray-900">{t("quoteAmountDue")}</dt>
                  <dd className="text-gray-900" data-testid="quote-amount-due">
                    {preparedOrder.quote?.display_amount_due ?? "—"}
                  </dd>
                </div>
              </dl>
              <p className="mt-2 text-xs text-gray-500">
                {t("quoteConfirmNote")}
              </p>
            </div>
          ) : null}

          {/* D7 补口 2：选中钱包入口时，支付控件就是钱包按钮本身 ——
              与 or_ 页（`OrderPaymentContent` 的 `!selectedIsWallet`）保持一致；
              此前这里仍渲染 Pay Now，点它会在卡表单校验处**静默 return**（死路）。 */}
          {!selectedIsWallet ? (
            <Button
              size="lg"
              className="w-full mt-6"
              disabled={!canSubmit || payProcessing || walletProcessing}
              onClick={handlePayNow}
            >
              {payProcessing ? (
                <>
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                  {processingStage === "confirming"
                    ? t("processing")
                    : t("submitting")}
                </>
              ) : preparedOrder?.quote ? (
                t("confirmAndPay")
              ) : (
                t("payNow")
              )}
            </Button>
          ) : null}
        </section>

        {/* Save my information — UI placeholder */}
        <section className="bg-white rounded-xl border border-gray-200 p-6">
          {SHOW_PLACEHOLDER_SECTIONS && (
            <SaveInfoSection isAuthenticated={isAuthenticated} />
          )}
        </section>
      </div>
    </div>
  );
}
