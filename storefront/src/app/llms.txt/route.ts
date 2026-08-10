import { getCategories } from "@/lib/data/categories";
import {
  getDefaultCountry,
  getDefaultLocale,
  getStoreDescription,
  getStoreName,
  getStoreUrl,
} from "@/lib/store";

/**
 * /llms.txt — machine-readable site overview for LLMs (llmstxt.org).
 * GEO: lets generative engines understand the store, its categories and key
 * pages (PRD-20260810-storefront-... AC-114).
 *
 * Note: route handlers are dynamic by default (no static caching), and Next.js
 * 16 Cache Components mode does not allow `export const dynamic`.
 */

export async function GET() {
  const storeName = getStoreName();
  const storeUrl = getStoreUrl();
  const origin = storeUrl?.replace(/\/$/, "") ?? "";
  const basePath = `/${getDefaultCountry()}/${getDefaultLocale()}`;
  const description = getStoreDescription();

  const categories = await getCategories({ depth_eq: 0 })
    .then((res) => res.data)
    .catch((error) => {
      console.error("llms.txt: failed to load categories", error);
      return [];
    });

  const lines: string[] = [
    `# ${storeName}`,
    "",
    `> ${description}`,
    "",
    "## About",
    `${storeName} is a self-hosted e-commerce store. Browse curated categories, discover products, and shop securely. Data stays on our own servers.`,
    "",
    "## Categories",
    ...(categories.length > 0
      ? categories.map(
          (category) =>
            `- [${category.name}](${origin}${basePath}/c/${category.permalink})`,
        )
      : ["- (categories unavailable)"]),
    "",
    "## Key pages",
    `- [All Products](${origin}${basePath}/products)`,
    `- [My Account](${origin}${basePath}/account)`,
    `- [Cart](${origin}${basePath}/cart)`,
    "",
    "## Structured data",
    "Pages include JSON-LD structured data (Organization, WebSite with SearchAction, Product, BreadcrumbList, ItemList, FAQPage) to describe the store's entities and relationships.",
    "",
  ];

  return new Response(lines.join("\n"), {
    headers: { "Content-Type": "text/plain; charset=utf-8" },
  });
}
