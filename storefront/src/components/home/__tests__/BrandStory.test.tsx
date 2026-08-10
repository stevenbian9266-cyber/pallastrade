import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { BrandStory } from "@/components/home/BrandStory";

vi.mock("next-intl/server", () => ({
  getTranslations: async () => (key: string) => key,
}));

// # PRD-20260810-storefront-对商城前台进行重新规划 AC-108/AC-115
describe("BrandStory", () => {
  it("renders a brand story heading, body and CTA", async () => {
    const element = await BrandStory({ basePath: "/us/en", locale: "en" });
    render(element);

    expect(screen.getByRole("heading", { name: "brandTitle" })).toBeTruthy();
    expect(screen.getByText("brandBody")).toBeTruthy();
    const cta = screen.getByRole("link", { name: /brandCta/ });
    expect(cta.getAttribute("href")).toBe("/us/en/products");
  });
});
