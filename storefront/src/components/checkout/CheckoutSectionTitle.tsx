"use client";

interface CheckoutSectionTitleProps {
  /** 1-based step number rendered in the numbered circle. */
  step: number;
  /** Section title text. */
  title: string;
  className?: string;
}

/**
 * Numbered checkout section title, matching the checkout demo
 * (e.g. "1 Contact", "2 Delivery address", "3 Shipping method").
 * The dark numbered circle + bold title keeps the one-page checkout
 * scannable without relying on color alone.
 */
export function CheckoutSectionTitle({
  step,
  title,
  className,
}: CheckoutSectionTitleProps) {
  return (
    <h2
      className={`flex items-center gap-2 text-lg font-bold text-gray-900 ${
        className ?? ""
      }`}
    >
      <span
        aria-hidden="true"
        className="inline-flex items-center justify-center w-6 h-6 rounded-full bg-gray-900 text-white text-xs font-bold shrink-0"
      >
        {step}
      </span>
      {title}
    </h2>
  );
}
