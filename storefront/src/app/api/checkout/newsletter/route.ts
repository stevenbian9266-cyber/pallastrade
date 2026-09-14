import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";
import { getClient } from "@/lib/pallastrade";

interface NewsletterBody {
  email?: string;
}

function sameOrigin(request: NextRequest): boolean {
  const origin = request.headers.get("origin");
  if (!origin) return false;

  const forwardedHost = request.headers.get("x-forwarded-host");
  const requestHost = forwardedHost ?? request.headers.get("host");
  if (!requestHost) return false;

  try {
    return new URL(origin).host === requestHost;
  } catch {
    return false;
  }
}

function errorBody(code: string, message: string) {
  return { error: { code, message } };
}

/**
 * Same-origin BFF for the checkout marketing opt-in
 * (PRD-20260914-checkout-placeholder-controls-governance FR-001).
 *
 * Keeps SDK credentials server-side and reuses the existing Store API endpoint
 * (`POST /api/v3/store/newsletter_subscribers`). Callers treat this as
 * **best-effort**: the checkout submit path must never fail because the
 * subscription could not be created, so provider failures answer `202 { ok: false }`
 * instead of an error status the client would surface to the buyer.
 */
export async function POST(request: NextRequest): Promise<NextResponse> {
  if (!sameOrigin(request)) {
    return NextResponse.json(
      errorBody("access_denied", "Cross-origin request rejected"),
      { status: 403 },
    );
  }

  const body = (await request.json().catch(() => ({}))) as NewsletterBody;
  const email = typeof body.email === "string" ? body.email.trim() : "";
  if (!email) {
    return NextResponse.json(errorBody("email_required", "Email is required"), {
      status: 422,
    });
  }

  try {
    await getClient().newsletterSubscribers.create({ email });
    return NextResponse.json({ ok: true }, { status: 201 });
  } catch (error) {
    // 订阅失败不影响下单（NFR-1）：不回错误状态，不暴露内部细节。
    console.warn("[checkout/newsletter] subscribe failed", error);
    return NextResponse.json({ ok: false }, { status: 202 });
  }
}
