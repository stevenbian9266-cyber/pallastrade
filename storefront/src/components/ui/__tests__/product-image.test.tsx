import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { ProductImage } from "@/components/ui/product-image";

describe("ProductImage", () => {
  it("renders a plain <img> with srcset when a multi-size srcset is provided", () => {
    const { container } = render(
      <ProductImage
        src="https://cdn.example.com/large.webp"
        srcSet="https://cdn.example.com/medium.webp 400w, https://cdn.example.com/large.webp 720w"
        alt="Product"
        fill
      />,
    );

    const img = container.querySelector("img");
    expect(img).not.toBeNull();
    expect(img?.getAttribute("src")).toBe("https://cdn.example.com/large.webp");
    expect(img?.getAttribute("srcset")).toContain("400w");
    expect(img?.getAttribute("srcset")).toContain("720w");
    expect(img?.getAttribute("class")).toContain("absolute inset-0");
  });

  it("renders next/image when no srcset is provided", () => {
    const { container } = render(
      <ProductImage src="https://example.com/img.jpg" alt="Product" />,
    );

    const img = container.querySelector("img");
    expect(img).not.toBeNull();
    expect(img?.getAttribute("srcset")).toBeNull();
  });

  it("renders placeholder when src is null", () => {
    render(<ProductImage src={null} alt="Product" />);
    expect(screen.getByRole("img")).toBeTruthy();
  });
});
