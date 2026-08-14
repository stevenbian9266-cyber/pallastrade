import { type NextRequest, NextResponse } from "next/server";

const API_URL = process.env.PALLASTRADE_API_URL || "http://localhost:3000";
const PUBLISHABLE_KEY = process.env.PALLASTRADE_PUBLISHABLE_KEY || "";

/**
 * SEO 301 redirects middleware.
 *
 * Resolves the incoming pathname against the store's active redirects via the
 * Store API (`GET /api/v3/store/redirects/resolve?path=...`). On a hit it
 * issues a 301/302 redirect to the target; on a miss (or API failure) it
 * degrades to normal rendering — mirroring the Turnstile degrade-open pattern
 * (an unreachable redirect service must never take the storefront down).
 *
 * The resolve result is cached for 60s (`revalidate`), so a newly added
 * redirect takes effect within a minute.
 */
export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

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
        const targetUrl = new URL(target, request.nextUrl.origin);
        // Guard against redirect loops (A → A)
        if (targetUrl.pathname !== pathname) {
          return NextResponse.redirect(targetUrl, status);
        }
      }
    }
  } catch {
    // Degrade-open: continue normal rendering on any failure.
  }

  return NextResponse.next();
}

export const config = {
  matcher: [
    // Storefront pages only — skip _next internals, api routes and static assets.
    "/((?!_next/static|_next/image|favicon.ico|api|.*\\.(?:png|jpg|jpeg|gif|svg|webp|ico|css|js|txt|xml|woff2?)$).*)",
  ],
};
