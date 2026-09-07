// 注意：本模块是「渲染期服务端守卫」，刻意【不加】"use server"——
// 若注册为 server action，在 Server Component 渲染期间调用时 redirect()
// 不会按渲染期语义抛出 NEXT_REDIRECT 形成 HTTP 跳转（仅 action 请求边界生效）。
// 本文件只被服务端页面 import，禁止在客户端组件 import。

import { redirect } from "next/navigation";
import { getAccessToken } from "@/lib/pallastrade/cookies";
import { isJwtExpired } from "@/lib/pallastrade/jwt";

/**
 * 账户区（我的订单等）会话门控。
 *
 * 未登录 / JWT 已过期 → 重定向到登录页并携带 `redirect` 回跳，与 `/account` 的
 * 登录表单语义一致。修复：匿名访问订单历史时不再因后端 401 被 `withFallback`
 * 静默吞成空列表（误导为「无订单」），而是引导用户登录所属账户查看订单。
 *
 * 注意：本守卫不校验 JWT 签名，只做存在性 + 过期快速判断；签名校验由后端 API
 * 完成（失败仍会进入数据层错误路径）。
 */
export async function requireAccountSession(
  basePath: string,
  pathname: string,
): Promise<void> {
  const token = await getAccessToken();
  if (!token || isJwtExpired(token, 0)) {
    redirect(`${basePath}/account?redirect=${encodeURIComponent(pathname)}`);
  }
}
