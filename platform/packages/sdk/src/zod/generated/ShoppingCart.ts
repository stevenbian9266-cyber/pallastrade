// This file is auto-generated. Do not edit directly.
import { z } from 'zod';
import { AddressSchema } from './Address';
import { PaymentMethodSchema } from './PaymentMethod';

export const ShoppingCartSchema = z.object({
  id: z.string(),
  token: z.string(),
  status: z.string(),
  email: z.string().nullable(),
  customer_note: z.string().nullable(),
  currency: z.string(),
  locale: z.string().nullable(),
  item_count: z.number(),
  converted_at: z.string().nullable(),
  shipping_method_id: z.string().nullable(),
  item_total: z.string().nullable(),
  display_item_total: z.string().nullable(),
  items: z.array(z.any()),
  billing_address: AddressSchema.nullable(),
  shipping_address: AddressSchema.nullable(),
  payment_methods: z.array(PaymentMethodSchema),
});

export type ShoppingCart = z.infer<typeof ShoppingCartSchema>;
