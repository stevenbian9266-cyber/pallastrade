// This file is auto-generated. Do not edit directly.
import { z } from 'zod';

export const ReviewSchema = z.object({
  id: z.string(),
  product_id: z.string().nullable(),
  user_name: z.string().nullable(),
  rating: z.number(),
  title: z.string().nullable(),
  body: z.string().nullable(),
  verified_purchase: z.boolean(),
  created_at: z.string().nullable(),
});

export type Review = z.infer<typeof ReviewSchema>;
