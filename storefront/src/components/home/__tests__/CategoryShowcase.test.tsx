import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { getCategories } from "@/lib/data/categories";
import { CategoryShowcase } from "@/components/home/CategoryShowcase";

vi.mock("next-intl/server", () => ({
  getTranslations: async () => (key: string) => key,
}));

vi.mock("@/lib/data/categories", () => ({
  getCategories: vi.fn(async () => ({
    data: [
      { id: "c1", name: "Electronics", permalink: "electronics", children: [] },
      { id: "c2", name: "Books", permalink: "books", children: [] },
    ],
  })),
}));

// # PRD-20260810-storefront-对商城前台进行重新规划 AC-106
describe("CategoryShowcase", () => {
  it("renders root categories with links to category pages", async () => {
    const element = await CategoryShowcase({ basePath: "/us/en", locale: "en" });
    render(element);

    expect(screen.getByRole("heading", { name: "browseByCategory" })).toBeTruthy();
    const electronics = screen.getByRole("link", { name: /Electronics/ });
    expect(electronics.getAttribute("href")).toBe("/us/en/c/electronics");
    expect(screen.getByRole("link", { name: /Books/ })).toBeTruthy();
  });

  it("renders nothing when there are no categories", async () => {
    vi.mocked(getCategories).mockResolvedValueOnce({ data: [] });
    const element = await CategoryShowcase({ basePath: "/us/en", locale: "en" });
    const { container } = render(element);
    expect(container.querySelector("section")).toBeNull();
  });
});
