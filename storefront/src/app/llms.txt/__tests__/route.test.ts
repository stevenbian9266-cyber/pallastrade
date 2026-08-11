import { describe, expect, it, vi } from "vitest";
import { GET } from "@/app/llms.txt/route";

vi.mock("@/lib/data/categories", () => ({
  getCategories: async () => ({
    data: [
      { id: "c1", name: "Electronics", permalink: "electronics", children: [] },
      {
        id: "c2",
        name: "Home & Garden",
        permalink: "home-garden",
        children: [],
      },
    ],
  }),
}));

vi.mock("@/lib/store", () => ({
  getStoreName: () => "PallasTrade",
  getStoreUrl: () => "https://pallastrade.cn",
  getStoreDescription: () => "Premium e-commerce store.",
  getDefaultCountry: () => "us",
  getDefaultLocale: () => "en",
}));

// # PRD-20260810-storefront-对商城前台进行重新规划 AC-114
describe("GET /llms.txt", () => {
  it("returns 200 with site title, about, categories and key pages", async () => {
    const response = await GET();
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toContain("text/plain");

    const body = await response.text();
    expect(body).toContain("# PallasTrade");
    expect(body).toContain("## About");
    expect(body).toContain(
      "[Electronics](https://pallastrade.cn/us/en/c/electronics)",
    );
    expect(body).toContain(
      "[Home & Garden](https://pallastrade.cn/us/en/c/home-garden)",
    );
    expect(body).toContain("[All Products]");
    expect(body).toContain("## Structured data");
  });
});
