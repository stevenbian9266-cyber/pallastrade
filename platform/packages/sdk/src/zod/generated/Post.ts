// This file is auto-generated. Do not edit directly.
import { z } from 'zod';

export const PostSchema = z.object({
  id: z.string(),
  title: z.string(),
  slug: z.string(),
  excerpt: z.string().nullable(),
  author: z.string().nullable(),
  seo_title: z.string().nullable(),
  seo_description: z.string().nullable(),
  published_at: z.string().nullable(),
  cover_image_url: z.string().nullable(),
  body: z.string().nullable(),
  body_html: z.string().nullable(),
});

export type Post = z.infer<typeof PostSchema>;
