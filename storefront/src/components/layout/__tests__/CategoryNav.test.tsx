import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { CategoryNav } from "@/components/layout/CategoryNav";

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
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
  it("renders home, all products and root category buttons with correct links", () => {
    render(<CategoryNav rootCategories={rootCategories} basePath="/us/en" />);

    expect(screen.getByRole("link", { name: "home" }).getAttribute("href")).toBe(
      "/us/en",
    );
    expect(
      screen.getByRole("link", { name: "allProducts" }).getAttribute("href"),
    ).toBe("/us/en/products");
    // Root categories are buttons (click opens the panel), not direct links.
    expect(screen.getByRole("button", { name: "Electronics" })).toBeTruthy();
  });

  it("opens the sub-category menu panel when clicking a root category name", () => {
    render(<CategoryNav rootCategories={rootCategories} basePath="/us/en" />);

    // Panel hidden before interaction
    expect(screen.queryByRole("link", { name: "Audio" })).toBeNull();

    fireEvent.click(screen.getByRole("button", { name: "Electronics" }));

    // Level-2 children appear in the panel
    expect(screen.getByRole("link", { name: "Audio" })).toBeTruthy();
    expect(screen.getByRole("link", { name: "Computers" })).toBeTruthy();
  });

  it("opens the panel when hovering a root category (mouse)", () => {
    render(<CategoryNav rootCategories={rootCategories} basePath="/us/en" />);

    expect(screen.queryByRole("link", { name: "Audio" })).toBeNull();

    fireEvent.mouseEnter(screen.getByRole("button", { name: "Electronics" }).closest("li")!);

    expect(screen.getByRole("link", { name: "Audio" })).toBeTruthy();
    expect(screen.getByRole("link", { name: "Computers" })).toBeTruthy();
  });

  it("shows three levels in the panel: root -> child -> grandchild", () => {
    render(<CategoryNav rootCategories={rootCategories} basePath="/us/en" />);

    fireEvent.click(screen.getByRole("button", { name: "Electronics" }));

    // Level-3 grandchildren are listed directly inside the panel
    expect(
      screen.getByRole("link", { name: "Laptops" }).getAttribute("href"),
    ).toBe("/us/en/c/laptops");

    // "View all" link navigates to the root category page
    expect(
      screen
        .getByRole("link", { name: /viewAllCategory/ })
        .getAttribute("href"),
    ).toBe("/us/en/c/electronics");
  });
});



