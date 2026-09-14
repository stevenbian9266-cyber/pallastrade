// This file is auto-generated. Do not edit directly.
import { z } from 'zod';

export const StoreCommerceTransactionSchema = z.object({
  id: z.string(),
  state: z.string(),
  purpose: z.string(),
  currency: z.string(),
  amount: z.string(),
  checkout_version: z.number().nullable(),
  price_version: z.string().nullable(),
  snapshot_fingerprint: z.string().nullable(),
  recovery_attempts: z.number(),
  last_error_class: z.string().nullable(),
  last_error_code: z.string().nullable(),
  last_error_message: z.string().nullable(),
  started_at: z.string().nullable(),
  payment_confirmed_at: z.string().nullable(),
  finalizing_at: z.string().nullable(),
  completed_at: z.string().nullable(),
  recovery_required_at: z.string().nullable(),
  manual_review_at: z.string().nullable(),
  canceled_at: z.string().nullable(),
});

export type StoreCommerceTransaction = z.infer<typeof StoreCommerceTransactionSchema>;
