// This file is auto-generated. Do not edit directly.
import { z } from 'zod';

export const BackInStockSubscriptionSchema = z.object({
  id: z.string(),
  product_id: z.string().nullable(),
  email: z.string(),
  status: z.string(),
  created_at: z.string(),
});

export type BackInStockSubscription = z.infer<typeof BackInStockSubscriptionSchema>;
