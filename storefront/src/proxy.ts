import { createPallasTradeMiddleware } from "@/lib/pallastrade/middleware";
import { getDefaultCountry, getDefaultLocale } from "@/lib/store";

export const proxy = createPallasTradeMiddleware({
  defaultCountry: getDefaultCountry(),
  defaultLocale: getDefaultLocale(),
});

export const config = {
  matcher: ["/((?!api/|_next/static|_next/image|favicon.ico|.*\\..*$).*)"],
};
