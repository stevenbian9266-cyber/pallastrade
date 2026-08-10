import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { PromoBanner } from "@/components/home/PromoBanner";

vi.mock("next-intl/server", () => ({
  getTranslations: async () => (key: string) => key,
}));

// # PRD-20260810-storefront-对商城前台进行重新规划 AC-108
describe("PromoBanner", () => {
  it("renders a promo heading, subtitle and CTA linking to products", async () => {
    const element = await PromoBanner({ basePath: "/us/en", locale: "en" });
    render(element);

    expect(screen.getByRole("heading", { name: "promoTitle" })).toBeTruthy();
    expect(screen.getByText("promoSubtitle")).toBeTruthy();
    const cta = screen.getByRole("link", { name: "promoCta" });
    expect(cta.getAttribute("href")).toBe("/us/en/products");
  });
});
