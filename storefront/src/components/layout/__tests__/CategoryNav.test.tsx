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
  it("renders home, all products and root categories with correct links", () => {
    render(<CategoryNav rootCategories={rootCategories} basePath="/us/en" />);

    expect(screen.getByRole("link", { name: "home" }).getAttribute("href")).toBe(
      "/us/en",
    );
    expect(
      screen.getByRole("link", { name: "allProducts" }).getAttribute("href"),
    ).toBe("/us/en/products");
    expect(
      screen.getByRole("link", { name: "Electronics" }).getAttribute("href"),
    ).toBe("/us/en/c/electronics");
  });

  it("opens the dropdown when clicking the chevron of a root category", () => {
    render(<CategoryNav rootCategories={rootCategories} basePath="/us/en" />);

    // Dropdown hidden before interaction
    expect(screen.queryByRole("link", { name: "Audio" })).toBeNull();

    fireEvent.click(
      screen.getByRole("button", { name: "categories: Electronics" }),
    );

    expect(screen.getByRole("link", { name: "Audio" })).toBeTruthy();
    expect(screen.getByRole("link", { name: "Computers" })).toBeTruthy();
  });

  it("shows three levels: root -> child -> grandchild", () => {
    render(<CategoryNav rootCategories={rootCategories} basePath="/us/en" />);

    fireEvent.click(
      screen.getByRole("button", { name: "categories: Electronics" }),
    );

    // Grandchild hidden until child is expanded
    expect(screen.queryByRole("link", { name: "Laptops" })).toBeNull();

    fireEvent.click(
      screen.getByRole("button", { name: "categories: Computers" }),
    );

    expect(
      screen.getByRole("link", { name: "Laptops" }).getAttribute("href"),
    ).toBe("/us/en/c/laptops");
  });
});


