// This file is auto-generated. Do not edit directly.
// NOTE: manually added for PRD-20260823-checkout-多订单拆分与合并支付 — regenerate
// with `pnpm --filter @pallastrade/sdk generate:types` after the OpenAPI spec lands.
import { z } from 'zod';
import { OrderSchema } from './Order';
import { PaymentSessionSchema } from './PaymentSession';

export const PaymentGroupSchema = z.object({
  id: z.string(),
  status: z.string(),
  currency: z.string(),
  amount: z.string(),
  completed_at: z.string().nullable(),
  orders: z.array(OrderSchema).optional(),
  payment_sessions: z.array(PaymentSessionSchema).optional(),
});

export type PaymentGroup = z.infer<typeof PaymentGroupSchema>;
