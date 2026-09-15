import type { Product, Variant } from "@pallastrade/sdk";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { ProductDetails } from "../ProductDetails";

const replace = vi.fn();

vi.mock("next/navigation", () => ({
  useRouter: () => ({ replace, push: vi.fn(), prefetch: vi.fn() }),
  usePathname: () => "/us/en/products/shirt",
}));

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string, values?: Record<string, unknown>) =>
    values && "date" in values ? `${key}:${String(values.date)}` : key,
  useLocale: () => "en",
}));

vi.mock("@/contexts/CartContext", () => ({
  useCart: () => ({ addItem: vi.fn() }),
}));

vi.mock("@/contexts/StoreContext", () => ({
  useStore: () => ({ currency: "USD" }),
}));

vi.mock("@/lib/analytics/gtm", () => ({
  trackViewItem: vi.fn(),
  trackAddToCart: vi.fn(),
}));

vi.mock("@/lib/data/backInStock", () => ({
  createBackInStockSubscription: vi.fn(),
}));

vi.mock("@/lib/data/buy-now", () => ({
  createBuyNowCart: vi.fn(),
}));

vi.mock("@/lib/data/reviews", () => ({
  createProductReview: vi.fn(),
}));

vi.mock("@/components/products/MediaGallery", () => ({
  MediaGallery: () => <div data-testid="media-gallery" />,
}));

import { trackViewItem } from "@/lib/analytics/gtm";

function variant(overrides: Record<string, unknown> = {}): Variant {
  return {
    id: "variant_1",
    sku: "SKU-1",
    option_values: [],
    purchasable: false,
    in_stock: false,
    backorderable: false,
    preorder: false,
    preorder_ships_at: null,
    ...overrides,
  } as unknown as Variant;
}

function product(overrides: Record<string, unknown> = {}): Product {
  return {
    id: "prod_1",
    name: "Shirt",
    slug: "shirt",
    variants: [],
    option_types: [],
    media: [],
    ...overrides,
  } as unknown as Product;
}

function renderDetails(
  productOverrides: Record<string, unknown>,
  initialVariantId: string | null = null,
) {
  return render(
    <ProductDetails
      product={product(productOverrides)}
      basePath="/us/en"
      initialVariantId={initialVariantId}
    />,
  );
}

describe("ProductDetails PDP state (PRD-20260915-catalog-pdp-state-correctness)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  // AC-001：有效 ?variant= → 初始选中该 SKU
  it("selects the deep-linked variant and shows its SKU (AC-001)", () => {
    const first = variant({ id: "variant_1", sku: "SKU-1", purchasable: true });
    const second = variant({
      id: "variant_2",
      sku: "SKU-2",
      purchasable: true,
    });

    renderDetails(
      { variants: [first, second], default_variant: first },
      "variant_2",
    );

    expect(screen.getByText("SKU-2")).toBeTruthy();
    expect(screen.queryByText("SKU-1")).toBeNull();
  });

  // AC-002：无效 variant → 回退默认变体
  it("falls back to the default variant for an unknown deep link (AC-002)", () => {
    const first = variant({ id: "variant_1", sku: "SKU-1", purchasable: true });
    const second = variant({
      id: "variant_2",
      sku: "SKU-2",
      purchasable: true,
    });

    renderDetails(
      { variants: [first, second], default_variant: first },
      "variant_gone",
    );

    expect(screen.getByText("SKU-1")).toBeTruthy();
    expect(screen.queryByText("SKU-2")).toBeNull();
  });

  // AC-003：切换 SKU → router.replace 静默更新 variant 参数
  it("updates the URL variant param when the shopper switches SKU (AC-003)", async () => {
    const user = userEvent.setup();
    const red = variant({
      id: "variant_red",
      sku: "RED",
      purchasable: true,
      option_values: [
        { id: "ov_red", option_type_id: "ot_color", name: "Red", label: "Red" },
      ],
    });
    const blue = variant({
      id: "variant_blue",
      sku: "BLUE",
      purchasable: true,
      option_values: [
        {
          id: "ov_blue",
          option_type_id: "ot_color",
          name: "Blue",
          label: "Blue",
        },
      ],
    });

    renderDetails(
      {
        variants: [red, blue],
        default_variant: red,
        option_types: [{ id: "ot_color", label: "Color", kind: "buttons" }],
      },
      "variant_red",
    );

    await user.click(screen.getByRole("button", { name: "Blue" }));

    expect(replace).toHaveBeenCalledWith(
      "/us/en/products/shirt?variant=variant_blue",
      { scroll: false },
    );
  });

  // AC-004：view_item 以落地变体上报
  it("reports view_item with the deep-linked variant (AC-004)", () => {
    const first = variant({ id: "variant_1", sku: "SKU-1" });
    const second = variant({ id: "variant_2", sku: "SKU-2" });

    renderDetails(
      { variants: [first, second], default_variant: first },
      "variant_2",
    );

    expect(vi.mocked(trackViewItem)).toHaveBeenCalledWith(
      expect.objectContaining({ id: "prod_1" }),
      "USD",
      expect.objectContaining({ id: "variant_2" }),
    );
  });

  // AC-005：预售可购 → 徽标 + 预计发货日，且不显示到货订阅
  it("renders the pre-order state with the ship-by date (AC-005)", () => {
    const preorder = variant({
      id: "variant_pre",
      sku: "PRE-1",
      purchasable: true,
      preorder: true,
      preorder_ships_at: "2026-10-01T12:00:00Z",
    });

    renderDetails({ variants: [preorder], default_variant: preorder });

    expect(screen.getByText("preorder")).toBeTruthy();
    expect(screen.getByText(/preorderShipsBy:/)).toBeTruthy();
    expect(screen.queryByText("backInStockTitle")).toBeNull();

    const addToCart = screen.getByRole("button", { name: "addToCart" });
    expect((addToCart as HTMLButtonElement).disabled).toBe(false);
  });

  // AC-006：缺货可超卖 → 可订购提示，且不显示到货订阅
  it("renders the backorder state as purchasable with a delay note (AC-006)", () => {
    const backorder = variant({
      id: "variant_back",
      sku: "BACK-1",
      purchasable: true,
      backorderable: true,
    });

    renderDetails({ variants: [backorder], default_variant: backorder });

    expect(screen.getByText("backorder")).toBeTruthy();
    expect(screen.getByText("backorderNote")).toBeTruthy();
    expect(screen.queryByText("backInStockTitle")).toBeNull();
  });

  // AC-007：真正不可购 → 缺货样式 + 到货订阅表单（回归）
  it("keeps the sold-out state with the back-in-stock form (AC-007)", () => {
    const soldOut = variant({ id: "variant_out", sku: "OUT-1" });

    renderDetails({ variants: [soldOut], default_variant: soldOut });

    expect(screen.getAllByText("outOfStock").length).toBeGreaterThan(0);
    expect(screen.getByText("backInStockTitle")).toBeTruthy();
  });

  // 修复（2026-09-15）：Save（收藏）按钮不再与 Add to Cart / Buy Now 争抢同一行 ——
  // 它降级为轻量次级动作并移入库存状态行。
  it("keeps the wishlist toggle small and inside the availability row", () => {
    const inStock = variant({
      id: "variant_1",
      sku: "SKU-1",
      purchasable: true,
      in_stock: true,
    });

    renderDetails({ variants: [inStock], default_variant: inStock });

    const row = screen.getByTestId("availability-row");
    const toggle = screen.getByRole("button", { name: "add" });

    expect(row.contains(toggle)).toBe(true);
    expect(toggle.getAttribute("data-size")).toBe("sm");
    expect(row.textContent).toContain("inStock");

    const addToCart = screen.getByRole("button", { name: "addToCart" });
    expect(addToCart.closest('[data-testid="availability-row"]')).toBeNull();
  });
});
