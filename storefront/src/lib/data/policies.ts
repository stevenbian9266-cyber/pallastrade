"use server";

import type { Policy } from "@pallastrade/sdk";
import { getClient } from "@/lib/pallastrade";

export async function getPolicy(slug: string): Promise<Policy | null> {
  const client = getClient();
  return client.policies.get(slug).catch(() => null);
}
