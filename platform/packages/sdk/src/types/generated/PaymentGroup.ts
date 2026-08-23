// Typelizer digest d0acb74af1197e1b021d20c12fd82ea4
//
// NOTE: manually added for PRD-20260823-checkout-多订单拆分与合并支付 — regenerate
// with `pnpm --filter @pallastrade/sdk generate:types` after the OpenAPI spec lands.
import type { Order, PaymentSession } from '@/types'

interface PaymentGroup {
  id: string;
  status: string;
  currency: string;
  amount: string;
  completed_at: string | null;
  orders?: Order[];
  payment_sessions?: PaymentSession[];
}

export default PaymentGroup;
