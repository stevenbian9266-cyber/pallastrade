import type { Order } from "@pallastrade/sdk";

/**
 * PRD-20260919-checkout FR-013：**可补付判定以金额为权威**。
 *
 * 背景：`payment_state` 过去只在订单 completed 时落库（OrderUpdater 行为），
 * 已提交未支付订单的历史行为是 `payment_status = null` → 前台
 * `payment_status === 'balance_due'` 恒假 → 补付入口永不出现。
 * 现在服务端已补状态投影（提交时落 + 读侧兜底），前台仍以金额为单一判据：
 * 有应付金额、非子订单、未完成、未付清。
 */
export function isOrderPayable(order: Order | null | undefined): boolean {
  if (!order) return false;
  if (order.completed_at) return false;
  if (order.is_child) return false;
  if (order.payment_status === "paid") return false;

  return Number(order.amount_due ?? 0) > 0;
}
