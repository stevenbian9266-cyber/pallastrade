import { act, fireEvent, render } from "@testing-library/react";
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
// # 修复：组件必须可见渲染（占位/加载/错误+重试），脚本加载失败不静默消失
describe("TurnstileWidget", () => {
  afterEach(() => {
    vi.unstubAllEnvs();
    vi.useRealTimers();
  });

  it("renders a visible wrapper with the Turnstile script and container when the site key is set (AC-001)", () => {
    vi.stubEnv("NEXT_PUBLIC_TURNSTILE_SITE_KEY", "0x4AAAAAADhWPvWYVdWLedL2");

    const { container } = render(<TurnstileWidget />);

    // The wrapper is always visible so the component never disappears silently.
    expect(
      container.querySelector('[data-testid="turnstile-wrapper"]'),
    ).not.toBeNull();
    const script = container.querySelector('script[id="cf-turnstile"]');
    expect(script).not.toBeNull();
    expect(script?.getAttribute("src")).toBe(
      "https://challenges.cloudflare.com/turnstile/api.js",
    );
    expect(
      container.querySelector('[data-testid="turnstile-widget"]'),
    ).not.toBeNull();
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
    expect(
      container.querySelector('[data-testid="turnstile-wrapper"]'),
    ).toBeNull();
  });

  it("shows a visible wrapper with loading state, then error + retry when the script never loads", () => {
    vi.stubEnv("NEXT_PUBLIC_TURNSTILE_SITE_KEY", "site-key");
    vi.useFakeTimers();

    const { container } = render(
      <TurnstileWidget
        labels={{
          loading: "Loading...",
          loadFailed: "Load failed",
          retry: "Retry",
        }}
      />,
    );

    // Wrapper is visible immediately with a loading hint.
    expect(
      container.querySelector('[data-testid="turnstile-wrapper"]'),
    ).not.toBeNull();
    expect(container.textContent).toContain("Loading...");

    // Advance past the load watchdog -> visible error + retry.
    act(() => {
      vi.advanceTimersByTime(8000);
    });

    expect(
      container.querySelector('[data-testid="turnstile-error"]'),
    ).not.toBeNull();
    expect(container.textContent).toContain("Load failed");
    expect(container.textContent).toContain("Retry");
  });

  it("reloads the script when retry is clicked after a load failure", () => {
    vi.stubEnv("NEXT_PUBLIC_TURNSTILE_SITE_KEY", "site-key");
    vi.useFakeTimers();

    const { container } = render(
      <TurnstileWidget labels={{ loadFailed: "failed", retry: "Retry" }} />,
    );

    act(() => {
      vi.advanceTimersByTime(8000);
    });

    const retryButton = container.querySelector<HTMLButtonElement>(
      '[data-testid="turnstile-error"] button',
    );
    expect(retryButton).not.toBeNull();

    act(() => {
      fireEvent.click(retryButton!);
    });

    // Retry injects a native <script> (id cf-turnstile-script) into <head>.
    expect(document.getElementById("cf-turnstile-script")).not.toBeNull();
  });
});
