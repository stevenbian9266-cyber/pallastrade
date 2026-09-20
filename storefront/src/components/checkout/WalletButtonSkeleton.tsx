/**
 * P1-a（PRD-20260920-checkout 支付核心统一 FR-011）—— 快捷支付区**首帧骨架**。
 *
 * 口径（与 `ExpressCheckoutButton` 的按钮槽同源）：
 * - **固定高度**：一根 `h-12`（48px，与容器 `min-h-12` 一致）占位条 = 真实钱包按钮的位置；
 *   元素就绪后原地替换（只切透明度），**不推动下方内容**（CLS 目标 < 0.02）。
 * - **列数 = `maxColumns`**（顶部快捷区 2 列 / 第 5 节钱包槽 1 列），与 Stripe
 *   `layout.maxColumns` 的排布一致，避免就绪后从 1 行变 2 行。
 * - **不表达可用性**：这里只占位。入口集合与「是否可用」仍由服务端 `entries`
 *   与设备探测（`wallet-availability`）决定，骨架不隐藏、不替换任何入口。
 *
 * 单独成文件的原因：`next/dynamic(..., { loading })` 的占位必须是**轻量、无依赖**的
 * 组件（放进 `ExpressCheckoutButton.tsx` 会把整块钱包组件再拉进首屏主包，失去动态加载的意义）。
 */
export function WalletButtonSkeleton({
  columns = 1,
  className,
}: {
  /** 期望的按钮列数（= 传给 Stripe 的 `maxColumns`）。 */
  columns?: number;
  /** 附加类名（布局微调用，骨架自身尺寸不可被覆盖）。 */
  className?: string;
}) {
  const count = columns >= 2 ? 2 : 1;
  return (
    <div
      data-testid="wallet-buttons-skeleton"
      aria-hidden="true"
      className={`grid gap-3 ${
        count === 2 ? "grid-cols-2" : "grid-cols-1"
      }${className ? ` ${className}` : ""}`}
    >
      {Array.from({ length: count }, (_, index) => (
        <div
          key={index}
          data-testid="wallet-skeleton-bar"
          className="h-12 animate-pulse rounded-lg bg-gray-200"
        />
      ))}
    </div>
  );
}
