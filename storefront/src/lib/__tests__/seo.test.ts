import { describe, expect, it } from "vitest";
import { buildWebsiteJsonLd } from "@/lib/seo";

// # PRD-20260810-storefront-对商城前台进行重新规划 AC-112
describe("buildWebsiteJsonLd", () => {
  it("builds a WebSite schema with a SearchAction pointing at the search endpoint", () => {
    const schema = buildWebsiteJsonLd(
      "https://pallastrade.cn",
      "https://pallastrade.cn/us/en/products",
    );

    expect(schema["@type"]).toBe("WebSite");
    expect(schema.url).toBe("https://pallastrade.cn");

    const action = schema.potentialAction as Record<string, unknown>;
    expect(action["@type"]).toBe("SearchAction");
    const target = action.target as Record<string, unknown>;
    expect(target.urlTemplate).toBe(
      "https://pallastrade.cn/us/en/products?q={search_term_string}",
    );
    expect(action["query-input"]).toBe("required name=search_term_string");
  });
});
