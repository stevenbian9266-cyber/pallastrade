import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { CategoryNav } from "@/components/layout/CategoryNav";

vi.mock("next-intl/server", () => ({
  getTranslations: async () => (key: string) => key,
}));

const rootCategories = [
  {
    id: "c1",
    name: "Electronics",
    permalink: "electronics",
    children: [
      { id: "c1a", name: "Audio", permalink: "audio", children: [] },
      {
        id: "c1b",
        name: "Computers",
        permalink: "computers",
        children: [
          { id: "c1b1", name: "Laptops", permalink: "laptops", children: [] },
        ],
      },
    ],
  },
  { id: "c2", name: "Books", permalink: "books", children: [] },
] as never[];

// # PRD-20260810-storefront-对商城前台进行重新规划 AC-102
describe("CategoryNav", () => {
  it("renders home, all products and root categories with correct links", async () => {
    const element = await CategoryNav({
      rootCategories,
      basePath: "/us/en",
      locale: "en",
    });
    render(element);

    const homeLink = screen.getByRole("link", { name: "home" });
    expect(homeLink.getAttribute("href")).toBe("/us/en");

    const allLink = screen.getByRole("link", { name: "allProducts" });
    expect(allLink.getAttribute("href")).toBe("/us/en/products");

    const electronics = screen.getByRole("link", { name: "Electronics" });
    expect(electronics.getAttribute("href")).toBe("/us/en/c/electronics");
  });
});
