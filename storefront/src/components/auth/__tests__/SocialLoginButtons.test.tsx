import { fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import {
  type SocialCredentials,
  SocialLoginButtons,
} from "@/components/auth/SocialLoginButtons";

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
}));

// next/script renders only an empty placeholder for afterInteractive scripts in
// SSR output. Mock it to a plain <script> so we can assert the props passed.
vi.mock("next/script", () => ({
  default: ({ src, strategy }: { src?: string; strategy?: string }) => (
    <script src={src} data-nscript={strategy} />
  ),
}));

function renderWithProviders() {
  const onSuccess = vi.fn<(c: SocialCredentials) => void>();
  const onError = vi.fn<(m: string) => void>();
  const view = render(
    <SocialLoginButtons onSuccess={onSuccess} onError={onError} />,
  );
  return { onSuccess, onError, ...view };
}

// # PRD-20260818-other-p1-1-社交登录-google-facebook AC-005/AC-006
describe("SocialLoginButtons", () => {
  afterEach(() => {
    vi.unstubAllEnvs();
    vi.clearAllMocks();
  });

  it("renders nothing when no provider is configured (AC-005)", () => {
    const { container } = renderWithProviders();
    expect(container.querySelector("script")).toBeNull();
    expect(screen.queryByText("continueWithGoogle")).toBeNull();
    expect(screen.queryByText("continueWithFacebook")).toBeNull();
  });

  it("renders the Google button and GIS script when the Google client id is set (AC-005)", () => {
    vi.stubEnv(
      "NEXT_PUBLIC_GOOGLE_CLIENT_ID",
      "client-id.apps.googleusercontent.com",
    );

    const { container } = renderWithProviders();

    expect(screen.getByText("continueWithGoogle")).toBeTruthy();
    expect(screen.queryByText("continueWithFacebook")).toBeNull();
    const script = container.querySelector(
      'script[src="https://accounts.google.com/gsi/client"]',
    );
    expect(script).not.toBeNull();
    expect(script?.getAttribute("data-nscript")).toBe("afterInteractive");
  });

  it("renders the Facebook button and FB SDK script when the Facebook app id is set (AC-006)", () => {
    vi.stubEnv("NEXT_PUBLIC_FACEBOOK_APP_ID", "123456");

    const { container } = renderWithProviders();

    expect(screen.getByText("continueWithFacebook")).toBeTruthy();
    expect(screen.queryByText("continueWithGoogle")).toBeNull();
    const script = container.querySelector(
      'script[src*="connect.facebook.net"]',
    );
    expect(script).not.toBeNull();
  });

  it("renders both buttons when both providers are configured (AC-005/AC-006)", () => {
    vi.stubEnv("NEXT_PUBLIC_GOOGLE_CLIENT_ID", "g-client");
    vi.stubEnv("NEXT_PUBLIC_FACEBOOK_APP_ID", "f-app");

    renderWithProviders();

    expect(screen.getByText("continueWithGoogle")).toBeTruthy();
    expect(screen.getByText("continueWithFacebook")).toBeTruthy();
  });

  it("shows an error when Google is clicked before the SDK is available", () => {
    vi.stubEnv("NEXT_PUBLIC_GOOGLE_CLIENT_ID", "g-client");

    const { onError } = renderWithProviders();

    fireEvent.click(screen.getByText("continueWithGoogle"));
    expect(onError).toHaveBeenCalledWith("googleFailed");
  });

  it("calls onSuccess with a Google credential when GIS grants one", () => {
    vi.stubEnv("NEXT_PUBLIC_GOOGLE_CLIENT_ID", "g-client");

    const gis = {
      accounts: {
        id: {
          initialize: vi.fn(),
          prompt: vi.fn(),
        },
      },
    };
    (window as unknown as { google: unknown }).google = gis;

    const { onSuccess } = renderWithProviders();

    fireEvent.click(screen.getByText("continueWithGoogle"));
    expect(gis.accounts.id.prompt).toHaveBeenCalled();

    // Simulate the GIS callback delivering an ID token.
    const initOpts = gis.accounts.id.initialize.mock.calls[0][0] as {
      callback: (r: { credential: string }) => void;
    };
    initOpts.callback({ credential: "google-id-token" });
    expect(onSuccess).toHaveBeenCalledWith({
      provider: "google",
      token: "google-id-token",
    });
  });

  it("calls onSuccess with a Facebook credential when FB grants one", () => {
    vi.stubEnv("NEXT_PUBLIC_FACEBOOK_APP_ID", "123456");

    const fb = {
      init: vi.fn(),
      login: vi.fn(
        (cb: (r: { authResponse?: { accessToken: string } }) => void) => {
          cb({ authResponse: { accessToken: "fb-token" } });
        },
      ),
    };
    (window as unknown as { FB: unknown }).FB = fb;

    const { onSuccess } = renderWithProviders();

    fireEvent.click(screen.getByText("continueWithFacebook"));
    expect(fb.login).toHaveBeenCalled();
    expect(onSuccess).toHaveBeenCalledWith({
      provider: "facebook",
      token: "fb-token",
    });
  });
});
