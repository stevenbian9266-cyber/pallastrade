"use server";

import type { Policy } from "@pallastrade/sdk";
import { POLICY_LINKS } from "@/lib/constants/policies";
import { getClient } from "@/lib/pallastrade";
import type { MerchantReturnPolicyTerms } from "@/lib/seo";

export async function getPolicy(slug: string): Promise<Policy | null> {
  const client = getClient();
  return client.policies.get(slug).catch(() => null);
}

/**
 * 店铺退货政策上的**结构化条款**（PRD-20260917-catalog-json-ld-phase2 FR-005）。
 *
 * 复用已有的 `policies#show` 端点（`client.policies.get`）与已有的
 * `POLICY_LINKS` slug，**不新增接口、不新增第二处硬编码**。
 *
 * 失败或未配置一律返回 `null`，PDP 据此**整体省略** `hasMerchantReturnPolicy` ——
 * 不输出好过输出一条编造的退货政策（残缺政策会被判为结构化数据错误）。
 */
export async function getReturnPolicy(): Promise<{
  slug: string;
  terms: MerchantReturnPolicyTerms;
} | null> {
  const slug = POLICY_LINKS.find(
    (policy) => policy.nameKey === "returnsPolicy",
  )?.slug;
  if (!slug) return null;

  const policy = await getPolicy(slug);
  const terms = policy?.merchant_return_policy;
  if (!terms) return null;

  return { slug: policy.slug, terms };
}
