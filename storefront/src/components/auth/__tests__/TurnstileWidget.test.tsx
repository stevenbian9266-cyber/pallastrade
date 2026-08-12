import { render } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { TurnstileWidget } from "@/components/auth/TurnstileWidget";

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

// # PRD-20260812-storefront-商城前台注册面板接入-turnstile-真人验证 AC-001
describe("TurnstileWidget", () => {
  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it("renders the Turnstile script and container when the site key is set (AC-001)", () => {
    vi.stubEnv("NEXT_PUBLIC_TURNSTILE_SITE_KEY", "0x4AAAAAADhWPvWYVdWLedL2");

    const { container } = render(<TurnstileWidget />);

    const script = container.querySelector('script[id="cf-turnstile"]');
    expect(script).not.toBeNull();
    expect(script?.getAttribute("src")).toBe(
      "https://challenges.cloudflare.com/turnstile/api.js",
    );
    expect(container.querySelector('[data-testid="turnstile-widget"]')).not.toBeNull();
  });

  it("loads the script with the afterInteractive strategy (AC-001)", () => {
    vi.stubEnv("NEXT_PUBLIC_TURNSTILE_SITE_KEY", "site-key");

    const { container } = render(<TurnstileWidget />);

    const script = container.querySelector('script[id="cf-turnstile"]');
    expect(script?.getAttribute("data-nscript")).toBe("afterInteractive");
  });

  it("renders nothing when the site key is not set (AC-001)", () => {
    const { container } = render(<TurnstileWidget />);

    expect(container.querySelector("script")).toBeNull();
    expect(container.querySelector('[data-testid="turnstile-widget"]')).toBeNull();
  });
});
