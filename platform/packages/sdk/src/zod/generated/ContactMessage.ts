// This file is auto-generated. Do not edit directly.
import { z } from 'zod';

export const ContactMessageSchema = z.object({
  id: z.string(),
  kind: z.string(),
  name: z.string().nullable(),
  email: z.string(),
  subject: z.string().nullable(),
  body: z.string(),
  status: z.string(),
  created_at: z.string(),
});

export type ContactMessage = z.infer<typeof ContactMessageSchema>;
