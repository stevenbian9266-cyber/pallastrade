import { type NextRequest, NextResponse } from "next/server";

const COUNTRY_COOKIE = "pallastrade_country";
const LOCALE_COOKIE = "pallastrade_locale";
const COOKIE_MAX_AGE = 365 * 24 * 60 * 60;

const API_URL = process.env.PALLASTRADE_API_URL || "http://localhost:3000";
const PUBLISHABLE_KEY = process.env.PALLASTRADE_PUBLISHABLE_KEY || "";

const HAS_COUNTRY_LOCALE = /^\/([a-z]{2})\/([a-z]{2})(\/|$)/i;

export interface PallasTradeMiddlewareConfig {
  /** Default country ISO code (default: 'us') */
  defaultCountry?: string;
  /** Default locale code (default: 'en') */
  defaultLocale?: string;
  /** Routes to skip — prefixes matched with startsWith (default: ['/_next', '/api', '/favicon.ico']) */
  staticRoutes?: string[];
}

/**
 * Set pallastrade_country / pallastrade_locale cookies on a response so that
 * `getLocaleOptions()` reads values matching the URL during SSR.
 */
function setLocaleCookies(
  response: NextResponse,
  country: string,
  locale: string,
): void {
  response.cookies.set(COUNTRY_COOKIE, country, {
    path: "/",
    maxAge: COOKIE_MAX_AGE,
  });
  response.cookies.set(LOCALE_COOKIE, locale, {
    path: "/",
    maxAge: COOKIE_MAX_AGE,
  });
}

/**
 * SEO 301 redirect resolution.
 *
 * Resolves a storefront pathname against the store's active redirects via the
 * Store API (`GET /api/v3/store/redirects/resolve?path=...`). On a hit it
 * returns the target path + status; on a miss or API failure it returns null
 * (degrade-open — an unreachable redirect service must never take the
 * storefront down, mirroring the Turnstile degrade pattern). The result is
 * cached for 60s (`revalidate`), so a newly added redirect takes effect
 * within a minute.
 */
async function resolveRedirect(
  pathname: string,
): Promise<{ path: string; status: number } | null> {
  try {
    const url = new URL("/api/v3/store/redirects/resolve", API_URL);
    url.searchParams.set("path", pathname);

    const res = await fetch(url, {
      headers: {
        ...(PUBLISHABLE_KEY
          ? { "X-PallasTrade-Api-Key": PUBLISHABLE_KEY }
          : {}),
      },
      next: { revalidate: 60 },
      signal: AbortSignal.timeout(3000),
    });

    if (res.ok) {
      const json = (await res.json()) as {
        data?: { path?: string; status_code?: number } | null;
      };
      const target = json?.data?.path;
      const status = json?.data?.status_code || 301;
      if (typeof target === "string" && target.startsWith("/")) {
        return { path: target, status };
      }
    }
  } catch {
    // Degrade-open: no redirect applied on any failure.
  }
  return null;
}

/**
 * Creates a Next.js middleware that handles:
 * - Redirecting bare paths to /{country}/{locale}/...
 * - Detecting country from cookies → geo headers → default
 * - Detecting locale from cookies → accept-language → default
 * - Syncing pallastrade_country / pallastrade_locale cookies with URL segments so
 *   server-side data fetching (via `getLocaleOptions()`) uses the correct market
 */
export function createPallasTradeMiddleware(
  config: PallasTradeMiddlewareConfig = {},
): (request: NextRequest) => Promise<NextResponse> {
  const defaultCountry = config.defaultCountry ?? "us";
  const defaultLocale = config.defaultLocale ?? "en";
  const staticRoutes = config.staticRoutes ?? [
    "/_next",
    "/api",
    "/dev",
    "/favicon.ico",
  ];

  return async function middleware(request: NextRequest) {
    const { pathname } = request.nextUrl;

    // Skip static routes
    if (staticRoutes.some((route) => pathname.startsWith(route))) {
      return NextResponse.next();
    }

    // Skip if pathname contains a file extension (static assets)
    if (/\.\w+$/.test(pathname)) {
      return NextResponse.next();
    }

    // SEO 301: resolve the full pathname (with /{country}/{locale} prefix)
    // against the store's redirects. Guarded against A→A loops.
    const redirectTarget = await resolveRedirect(pathname);
    if (redirectTarget) {
      const targetUrl = new URL(redirectTarget.path, request.nextUrl.origin);
      if (targetUrl.pathname !== pathname) {
        return NextResponse.redirect(targetUrl, redirectTarget.status);
      }
    }

    // Already has /{country}/{locale} prefix — sync cookies with URL segments
    const match = pathname.match(HAS_COUNTRY_LOCALE);
    if (match) {
      const response = NextResponse.next();
      setLocaleCookies(
        response,
        match[1].toLowerCase(),
        match[2].toLowerCase(),
      );
      return response;
    }

    // Detect country: cookie → geo headers → default
    const country =
      request.cookies.get(COUNTRY_COOKIE)?.value ??
      request.headers.get("x-vercel-ip-country")?.toLowerCase() ??
      request.headers.get("cf-ipcountry")?.toLowerCase() ??
      defaultCountry;

    // Detect locale: cookie → accept-language → default
    const locale =
      request.cookies.get(LOCALE_COOKIE)?.value ??
      request.headers
        .get("accept-language")
        ?.split(",")[0]
        ?.split("-")[0]
        ?.toLowerCase() ??
      defaultLocale;

    const url = request.nextUrl.clone();
    url.pathname = `/${country}/${locale}${pathname === "/" ? "" : pathname}`;

    const response = NextResponse.redirect(url);
    setLocaleCookies(response, country, locale);
    return response;
  };
}
