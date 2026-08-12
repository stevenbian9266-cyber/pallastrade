"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import type { CookieConsent } from "@/lib/constants/cookies";
import {
  createAcceptedConsent,
  createConsentFromPreferences,
  createDeniedConsent,
  readConsentFromDocument,
  writeConsentToDocument,
  type ToggleablePreferences,
} from "@/lib/cookie-consent";

interface CookieConsentContextValue {
  /**
   * The persisted consent, or `null` while undecided / before the cookie has
   * been read on the client (SSR + first render always yield `null`).
   */
  consent: CookieConsent | null;
  hasDecided: boolean;
  acceptAll: () => void;
  /** Reject everything except strictly necessary cookies. */
  rejectAll: () => void;
  savePreferences: (prefs: ToggleablePreferences) => void;
}

const CookieConsentContext =
  createContext<CookieConsentContextValue | null>(null);

export function CookieConsentProvider({
  children,
}: {
  children: ReactNode;
}) {
  const [consent, setConsent] = useState<CookieConsent | null>(null);

  // Read the consent cookie only on the client to avoid SSR/hydration
  // mismatches. Consumers gate their own "client mounted" state locally (in
  // the same component/segment that conditionally renders) so the provider
  // effect never mutates the tree across streaming boundaries.
  useEffect(() => {
    setConsent(readConsentFromDocument());
  }, []);

  const persist = useCallback((next: CookieConsent) => {
    writeConsentToDocument(next);
    setConsent(next);
  }, []);

  const acceptAll = useCallback(() => persist(createAcceptedConsent()), [persist]);
  const rejectAll = useCallback(() => persist(createDeniedConsent()), [persist]);
  const savePreferences = useCallback(
    (prefs: ToggleablePreferences) => persist(createConsentFromPreferences(prefs)),
    [persist],
  );

  const value = useMemo<CookieConsentContextValue>(
    () => ({
      consent,
      hasDecided: consent !== null,
      acceptAll,
      rejectAll,
      savePreferences,
    }),
    [consent, acceptAll, rejectAll, savePreferences],
  );

  return (
    <CookieConsentContext.Provider value={value}>
      {children}
    </CookieConsentContext.Provider>
  );
}

export function useCookieConsent(): CookieConsentContextValue {
  const ctx = useContext(CookieConsentContext);
  if (!ctx) {
    throw new Error(
      "useCookieConsent must be used within a CookieConsentProvider",
    );
  }
  return ctx;
}
