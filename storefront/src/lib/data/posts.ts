"use server";

import type { Post } from "@pallastrade/sdk";
import { getClient } from "@/lib/pallastrade";

export async function listPosts(params?: {
  page?: number;
  limit?: number;
}): Promise<Post[]> {
  const client = getClient();
  const response = await client.posts
    .list({ page: params?.page ?? 1, limit: params?.limit ?? 12 })
    .catch(() => null);
  return response?.data ?? [];
}

export async function getPost(slug: string): Promise<Post | null> {
  const client = getClient();
  return client.posts.get(slug).catch(() => null);
}
