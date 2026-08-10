import { render } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { TawkToWidget } from "@/components/layout/TawkToWidget";

// next/script renders only an empty placeholder for afterInteractive scripts in
// SSR output (src is injected on client hydration). Mock it to a plain <script>
// so we can assert the props the component passes through.
vi.mock("next/script", () => ({
  default: ({
    id,
    src,
    strategy,
  }: {
    id?: string;
    src?: string;
    strategy?: string;
  }) => <script id={id} src={src} data-nscript={strategy} />,
}));

// # PRD-20260810-storefront-商城前台接入tawk-to作为客服工具 AC-001 / AC-002 / AC-004
describe("TawkToWidget", () => {
  afterEach(() => {
    vi.unstubAllEnvs();
  });

  const findTawkScript = (container: HTMLElement) =>
    container.querySelector('script[id="tawk-to"]');

  it("renders the tawk.to embed script when both IDs are set (AC-001)", () => {
    vi.stubEnv("NEXT_PUBLIC_TAWK_TO_PROPERTY_ID", "6a32b7a845840f1d49424bd9");
    vi.stubEnv("NEXT_PUBLIC_TAWK_TO_WIDGET_ID", "1jrb1qrcu");

    const { container } = render(<TawkToWidget />);

    const script = findTawkScript(container);
    expect(script).not.toBeNull();
    expect(script?.getAttribute("src")).toBe(
      "https://embed.tawk.to/6a32b7a845840f1d49424bd9/1jrb1qrcu",
    );
  });

  it("loads the script with the afterInteractive strategy (AC-004)", () => {
    vi.stubEnv("NEXT_PUBLIC_TAWK_TO_PROPERTY_ID", "prop-123");
    vi.stubEnv("NEXT_PUBLIC_TAWK_TO_WIDGET_ID", "widget-456");

    const { container } = render(<TawkToWidget />);

    const script = findTawkScript(container);
    expect(script?.getAttribute("data-nscript")).toBe("afterInteractive");
  });

  it("renders nothing when no env vars are set (AC-002)", () => {
    const { container } = render(<TawkToWidget />);
    expect(container.querySelector("script")).toBeNull();
  });

  it("renders nothing when only one ID is set (AC-002)", () => {
    vi.stubEnv("NEXT_PUBLIC_TAWK_TO_PROPERTY_ID", "prop-123");
    const { container } = render(<TawkToWidget />);
    expect(container.querySelector("script")).toBeNull();

    vi.unstubAllEnvs();
    vi.stubEnv("NEXT_PUBLIC_TAWK_TO_WIDGET_ID", "widget-456");
    const { container: second } = render(<TawkToWidget />);
    expect(second.querySelector("script")).toBeNull();
  });
});
