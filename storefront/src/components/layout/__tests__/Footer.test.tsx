import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { Footer } from "@/components/layout/Footer";

vi.mock("next-intl/server", () => ({
  getTranslations: async () => (key: string) => key,
}));

vi.mock("@/lib/store", () => ({
  getStoreName: () => "PallasTrade",
  getStoreDescription: () => "Premium store.",
}));

// # PRD-20260810-storefront-对商城前台进行重新规划 AC-104
describe("Footer", () => {
  it("renders brand, shop, account and policies sections with no demo links", async () => {
    const element = await Footer({
      rootCategories: [
        { id: "c1", name: "Electronics", permalink: "electronics" },
      ] as never[],
      basePath: "/us/en",
      locale: "en",
    });
    const { container } = render(element);

    // No demo links with href="#"
    expect(container.querySelector('a[href="#"]')).toBeNull();

    // Section headings present
    for (const heading of ["shop", "account", "policies"]) {
      expect(screen.getByText(heading)).toBeTruthy();
    }

    // Brand logo image present
    expect(container.querySelector("img[alt='PallasTrade']")).not.toBeNull();

    // Category link present
    const categoryLink = screen.getByRole("link", { name: "Electronics" });
    expect(categoryLink.getAttribute("href")).toBe("/us/en/c/electronics");
  });
});
