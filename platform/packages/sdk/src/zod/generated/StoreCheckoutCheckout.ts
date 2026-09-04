// This file is auto-generated. Do not edit directly.
import { z } from 'zod';
import { AddressSchema } from './Address';
import { FulfillmentSchema } from './Fulfillment';
import { LineItemSchema } from './LineItem';

export const StoreCheckoutCheckoutSchema = z.object({
  id: z.string(),
  number: z.string(),
  state: z.string(),
  status: z.string(),
  payment_state: z.string().nullable(),
  shipment_state: z.string().nullable(),
  email: z.string().nullable(),
  currency: z.string(),
  submitted_at: z.string().nullable(),
  completed_at: z.string().nullable(),
  version: z.number(),
  price_version: z.string().nullable(),
  ready: z.boolean(),
  missing_requirements: z.array(z.string()),
  expires_at: z.string().nullable(),
  item_total: z.string().nullable(),
  display_item_total: z.string().nullable(),
  delivery_total: z.string().nullable(),
  display_delivery_total: z.string().nullable(),
  adjustment_total: z.string().nullable(),
  display_adjustment_total: z.string().nullable(),
  discount_total: z.string().nullable(),
  display_discount_total: z.string().nullable(),
  tax_total: z.string().nullable(),
  display_tax_total: z.string().nullable(),
  included_tax_total: z.string().nullable(),
  display_included_tax_total: z.string().nullable(),
  additional_tax_total: z.string().nullable(),
  display_additional_tax_total: z.string().nullable(),
  total: z.string().nullable(),
  display_total: z.string().nullable(),
  amount_due: z.string().nullable(),
  display_amount_due: z.string().nullable(),
  shipping_address: AddressSchema.nullable(),
  billing_address: AddressSchema.nullable(),
  items: z.array(LineItemSchema),
  fulfillments: z.array(FulfillmentSchema),
  discounts: z.array(z.object({ id: z.string(), amount: z.string().nullable(), currency: z.string() })),
  taxes: z.array(z.object({ id: z.string(), amount: z.string().nullable(), currency: z.string() })),
});

export type StoreCheckoutCheckout = z.infer<typeof StoreCheckoutCheckoutSchema>;
