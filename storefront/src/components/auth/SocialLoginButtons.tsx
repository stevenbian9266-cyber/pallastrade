"use client";

import Script from "next/script";
import { useTranslations } from "next-intl";
import { useCallback, useState } from "react";
import { Button } from "@/components/ui/button";

/** Credential payload passed up to the login flow after a provider grants it. */
export interface SocialCredentials {
  provider: "google" | "facebook";
  /** Google ID token (from GIS) or Facebook user access token. */
  token: string;
}

declare global {
  interface Window {
    google?: {
      accounts: {
        id: {
          initialize: (opts: {
            client_id: string;
            callback: (response: { credential: string }) => void;
            auto_select?: boolean;
          }) => void;
          prompt: () => void;
        };
      };
    };
    FB?: {
      init: (opts: {
        appId: string;
        version: string;
        cookie?: boolean;
        xfbml?: boolean;
      }) => void;
      login: (
        callback: (response: {
          authResponse?: { accessToken: string };
          status?: string;
        }) => void,
        opts?: { scope: string },
      ) => void;
    };
  }
}

const GOOGLE_SCRIPT_SRC = "https://accounts.google.com/gsi/client";
const FACEBOOK_SCRIPT_SRC =
  "https://connect.facebook.net/en_US/sdk.js#xfbml=1&version=v19.0";

/**
 * Social login buttons (Google + Facebook) for the account login/register pages.
 *
 * Each button is rendered ONLY when its public config var is present:
 *   - Google:  `NEXT_PUBLIC_GOOGLE_CLIENT_ID`
 *   - Facebook: `NEXT_PUBLIC_FACEBOOK_APP_ID`
 * These are PUBLIC values (like publishable keys) — safe for NEXT_PUBLIC_.
 * Provider SDK scripts are loaded lazily via next/script afterInteractive, so
 * nothing third-party loads when a provider is disabled.
 *
 * When a provider grants a credential, `onSuccess` is called with a normalized
 * `{ provider, token }` payload; the caller (login/register page) performs the
 * actual `auth.login` call so session finalization stays in one place.
 *
 * # PRD-20260818-other-p1-1-社交登录-google-facebook AC-005/AC-006
 */
export function SocialLoginButtons({
  onSuccess,
  onError,
}: {
  onSuccess: (credentials: SocialCredentials) => void;
  onError?: (message: string) => void;
}) {
  const t = useTranslations("socialLogin");
  const googleClientId = process.env.NEXT_PUBLIC_GOOGLE_CLIENT_ID;
  const facebookAppId = process.env.NEXT_PUBLIC_FACEBOOK_APP_ID;

  const showGoogle = Boolean(googleClientId);
  const showFacebook = Boolean(facebookAppId);

  const [loadingProvider, setLoadingProvider] = useState<
    "google" | "facebook" | null
  >(null);

  // Initialize Google Identity Services once the GIS script is loaded.
  const initGoogle = useCallback(() => {
    const g = (window as unknown as Window).google;
    if (!g?.accounts || !googleClientId) return;
    g.accounts.id.initialize({
      client_id: googleClientId,
      callback: (response) => {
        setLoadingProvider(null);
        if (response.credential) {
          onSuccess({ provider: "google", token: response.credential });
        } else {
          onError?.(t("googleFailed"));
        }
      },
    });
  }, [googleClientId, onSuccess, onError, t]);

  // Initialize the Facebook JS SDK once its script is loaded.
  const initFacebook = useCallback(() => {
    const fb = (window as unknown as Window).FB;
    if (!fb || !facebookAppId) return;
    fb.init({ appId: facebookAppId, version: "v19.0" });
  }, [facebookAppId]);

  const handleGoogle = useCallback(() => {
    if (loadingProvider) return;
    const g = (window as unknown as Window).google;
    if (!g?.accounts) {
      onError?.(t("googleFailed"));
      return;
    }
    // (Re)initialize on each click so a missing/raced script load doesn't leave
    // GIS in an unconfigured state; initialize() is idempotent in GIS.
    initGoogle();
    setLoadingProvider("google");
    g.accounts.id.prompt();
  }, [loadingProvider, onError, t, initGoogle]);

  const handleFacebook = useCallback(() => {
    if (loadingProvider) return;
    const fb = (window as unknown as Window).FB;
    if (!fb) {
      onError?.(t("facebookFailed"));
      return;
    }
    initFacebook();
    setLoadingProvider("facebook");
    fb.login(
      (response) => {
        setLoadingProvider(null);
        if (response.authResponse?.accessToken) {
          onSuccess({
            provider: "facebook",
            token: response.authResponse.accessToken,
          });
        } else {
          // User cancelled or the grant failed — treat as a soft cancel.
          onError?.(t("facebookCancelled"));
        }
      },
      { scope: "email" },
    );
  }, [loadingProvider, onError, t, onSuccess, initFacebook]);

  if (!showGoogle && !showFacebook) {
    return null;
  }

  return (
    <div className="space-y-3">
      <div className="relative">
        <div className="absolute inset-0 flex items-center">
          <span className="w-full border-t border-border" />
        </div>
        <div className="relative flex justify-center text-xs uppercase">
          <span className="bg-background px-2 text-muted-foreground">
            {t("orContinueWith")}
          </span>
        </div>
      </div>

      {showGoogle && (
        <>
          <Button
            type="button"
            variant="outline"
            size="lg"
            className="w-full"
            disabled={loadingProvider !== null}
            onClick={handleGoogle}
          >
            <GoogleIcon />
            {t("continueWithGoogle")}
          </Button>
          {/* Load the GIS script only when enabled; initialize once ready. */}
          <Script
            src={GOOGLE_SCRIPT_SRC}
            strategy="afterInteractive"
            onReady={initGoogle}
          />
        </>
      )}

      {showFacebook && (
        <>
          <Button
            type="button"
            variant="outline"
            size="lg"
            className="w-full"
            disabled={loadingProvider !== null}
            onClick={handleFacebook}
          >
            <FacebookIcon />
            {t("continueWithFacebook")}
          </Button>
          <Script
            src={FACEBOOK_SCRIPT_SRC}
            strategy="afterInteractive"
            onReady={initFacebook}
          />
        </>
      )}
    </div>
  );
}

function GoogleIcon() {
  return (
    <svg className="w-4 h-4 mr-2" viewBox="0 0 24 24" aria-hidden="true">
      <path
        fill="#4285F4"
        d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
      />
      <path
        fill="#34A853"
        d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
      />
      <path
        fill="#FBBC05"
        d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"
      />
      <path
        fill="#EA4335"
        d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"
      />
    </svg>
  );
}

function FacebookIcon() {
  return (
    <svg
      className="w-4 h-4 mr-2"
      viewBox="0 0 24 24"
      fill="#1877F2"
      aria-hidden="true"
    >
      <path d="M24 12.073C24 5.405 18.627 0 12 0S0 5.405 0 12.073C0 18.1 4.388 23.094 10.125 24v-8.437H7.078v-3.49h3.047v-2.66c0-3.026 1.792-4.697 4.533-4.697 1.313 0 2.686.236 2.686.236v2.971H15.83c-1.491 0-1.956.93-1.956 1.886v2.264h3.328l-.532 3.49h-2.796V24C19.612 23.094 24 18.1 24 12.073z" />
    </svg>
  );
}
