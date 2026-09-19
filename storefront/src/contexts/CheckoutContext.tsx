"use client";

import {
  createContext,
  type ReactNode,
  useContext,
  useMemo,
  useState,
} from "react";

const PENDING = Symbol("pending");

/**
 * PRD-20260919-checkout-remove-items-block-mobile-summary-meta FR-003：
 * 订单摘要的**折叠态元数据**（移动端 `MobileSummaryToggle` 在收起时展示
 * 「N 件 · 金额」，避免删掉左栏商品区块后首屏看不到购物车概况）。
 *
 * 两个字段都取服务端权威值：件数 = `ShoppingCart.item_count`，
 * 金额 = `ShoppingCart.display_item_total`（**仅用于渲染**，不参与任何计算）。
 */
export interface CheckoutSummaryMeta {
  itemCount: number;
  displayTotal: string | null;
}

interface CheckoutContextValue {
  summaryContent: ReactNode | typeof PENDING;
  setSummaryContent: (content: ReactNode) => void;
  summaryMeta: CheckoutSummaryMeta | null;
  setSummaryMeta: (meta: CheckoutSummaryMeta | null) => void;
}

const CheckoutContext = createContext<CheckoutContextValue | undefined>(
  undefined,
);

export function CheckoutProvider({ children }: { children: ReactNode }) {
  const [summaryContent, setSummaryContent] = useState<
    ReactNode | typeof PENDING
  >(PENDING);
  const [summaryMeta, setSummaryMeta] = useState<CheckoutSummaryMeta | null>(
    null,
  );

  const value = useMemo<CheckoutContextValue>(
    () => ({ summaryContent, setSummaryContent, summaryMeta, setSummaryMeta }),
    [summaryContent, summaryMeta],
  );

  return (
    <CheckoutContext.Provider value={value}>
      {children}
    </CheckoutContext.Provider>
  );
}

export function useCheckout() {
  const context = useContext(CheckoutContext);
  if (context === undefined) {
    throw new Error("useCheckout must be used within a CheckoutProvider");
  }
  return context;
}

function CheckoutSummarySkeleton() {
  return (
    <div className="animate-pulse space-y-4">
      <div className="flex items-center gap-4">
        <div className="w-16 h-16 bg-gray-200 rounded-lg" />
        <div className="flex-1 space-y-2">
          <div className="h-4 bg-gray-200 rounded w-3/4" />
          <div className="h-3 bg-gray-200 rounded w-1/2" />
        </div>
        <div className="h-4 bg-gray-200 rounded w-16" />
      </div>
      <div className="border-t border-gray-200 pt-4 space-y-3">
        <div className="flex justify-between">
          <div className="h-4 bg-gray-200 rounded w-20" />
          <div className="h-4 bg-gray-200 rounded w-16" />
        </div>
        <div className="flex justify-between">
          <div className="h-4 bg-gray-200 rounded w-16" />
          <div className="h-4 bg-gray-200 rounded w-12" />
        </div>
        <div className="flex justify-between pt-3 border-t border-gray-200">
          <div className="h-5 bg-gray-200 rounded w-14" />
          <div className="h-6 bg-gray-200 rounded w-24" />
        </div>
      </div>
    </div>
  );
}

export function CheckoutSummary() {
  const { summaryContent } = useCheckout();
  if (summaryContent === PENDING) return <CheckoutSummarySkeleton />;
  return <>{summaryContent}</>;
}
