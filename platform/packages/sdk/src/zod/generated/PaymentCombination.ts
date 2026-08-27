// This file is auto-generated. Do not edit directly.
import { z } from 'zod';
import { OrderSchema } from './Order';
import { PaymentSessionSchema } from './PaymentSession';

export const PaymentCombinationSchema = z.object({
  id: z.string(),
  status: z.string(),
  currency: z.string(),
  expires_at: z.string().nullable(),
  completed_at: z.string().nullable(),
  amount: z.string(),
  orders: z.array(OrderSchema).optional(),
  payment_session: PaymentSessionSchema.optional(),
});

export type PaymentCombination = z.infer<typeof PaymentCombinationSchema>;
