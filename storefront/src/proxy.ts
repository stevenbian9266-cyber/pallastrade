import { type NextRequest, NextResponse } from "next/server";
import { createPallasTradeMiddleware } from "@/lib/pallastrade/middleware";
import { getDefaultCountry, getDefaultLocale } from "@/lib/store";

// 与 src/lib/pallastrade/cookies.ts 的默认 cookie 名保持一致。
const CART_TOKEN_COOKIE = "_pallastrade_cart_token";
const CART_ID_COOKIE = `${CART_TOKEN_COOKIE}_id`;
const CART_TOKEN_MAX_AGE = 60 * 60 * 24 * 30; // 30 days

const pallasTradeMiddleware = createPallasTradeMiddleware({
  defaultCountry: getDefaultCountry(),
  defaultLocale: getDefaultLocale(),
});

/**
 * E 场景（邮件订单回流补付）：弃单/待支付邮件链接携带 ?token= 访问 Checkout 页。
 *
 * Server Component 渲染期间不允许写 cookie（Next.js 16 限制：仅 Server Action
 * 或 Route Handler 可写），因此在这里（proxy 运行在请求入口，允许写 cookie）
 * 把 cart id + token 写入 HttpOnly cookie，并从 URL 移除 token 后重定向，
 * 避免页面渲染时再次尝试写 cookie（"Cookies can only be modified in a Server
 * Action or Route Handler"）。
 */
export function proxy(request: NextRequest) {
  const { pathname, searchParams } = request.nextUrl;
  const token = searchParams.get("token");

  // 仅处理 checkout 页带 token 的请求
  if (token && pathname.includes("/checkout/")) {
    const segments = pathname.split("/").filter(Boolean);
    const id = segments[segments.length - 1];
    if (id) {
      // 移除 URL 中的 token 后重定向（同时携带 cookie），
      // 避免 Server Component 渲染时重复写 cookie
      const url = request.nextUrl.clone();
      url.searchParams.delete("token");
      const response = NextResponse.redirect(url);
      const opts = {
        httpOnly: true,
        secure: process.env.NODE_ENV === "production",
        sameSite: "lax" as const,
        path: "/",
        maxAge: CART_TOKEN_MAX_AGE,
      };
      response.cookies.set(CART_ID_COOKIE, id, opts);
      response.cookies.set(CART_TOKEN_COOKIE, token, opts);
      return response;
    }
  }

  return pallasTradeMiddleware(request);
}

export const config = {
  matcher: ["/((?!api/|_next/static|_next/image|favicon.ico|.*\\..*$).*)"],
};
