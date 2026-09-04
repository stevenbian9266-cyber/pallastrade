// This file is auto-generated. Do not edit directly.
import { z } from 'zod';

export const CartItemSchema = z.object({
  id: z.string(),
  variant_id: z.string(),
  currency: z.string(),
  quantity: z.number(),
  selected: z.boolean(),
  name: z.string(),
  slug: z.string(),
  options_text: z.string(),
  unit_price: z.string().nullable(),
  display_unit_price: z.string().nullable(),
  amount: z.string().nullable(),
  display_amount: z.string().nullable(),
  thumbnail_url: z.string().nullable(),
});

export type CartItem = z.infer<typeof CartItemSchema>;
