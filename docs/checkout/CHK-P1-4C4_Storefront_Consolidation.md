# CHK-P1-4C4 — Legacy 一页式支付页退役（Storefront Consolidation 收尾）

> Task：TASK-20260904015108-b59694e0；Gate：GATE-2026-09-04T01-51-35
> 关联 PRD：`PRD-20260903-checkout-chk-p1-1-order-checkout-application-layer-checkoutview` §12 CHK-P1-4C4（AC-705~709）
> REQ：`REQ-20260904-chk-p1-4c4`

## 背景

4C 轮将 legacy 一页式（`CheckoutPageContent` 子树）标注 DEFERRED（4C-4）。本轮实施退役。

**可达性依据**：`cart_` → UnifiedCheckout、`or_` → OrderPaymentContent 已捕获全部有效 id；后端对存量整数 id 兼容解析且序列化恒 `or_` 前缀 → 存量订单被 or_ 分支承接。legacy 兜底实为「不可解析 id」的错误路径。

## 改动清单

### 删除（9 文件，用户确认）

| 文件 | 说明 |
|---|---|
| `(checkout)/checkout/[id]/CheckoutPageContent.tsx` | legacy 一页式主体 |
| `(checkout)/checkout/[id]/CheckoutSidebar.tsx` | 右栏摘要（仅 legacy 页） |
| `components/checkout/AddressSection.tsx` | 地址/联系方式区块（仅 legacy） |
| `components/checkout/DeliveryMethodSection.tsx` | 物流方式区块（仅 legacy） |
| `components/checkout/PaymentSection.tsx` | 支付表单容器（仅 legacy） |
| `components/checkout/AddressSelector.tsx` | 已存地址选择（仅 AddressSection） |
| `components/checkout/Summary.tsx` | 金额摘要（仅 CheckoutSidebar） |
| `components/checkout/AdyenPaymentForm.tsx` | Adyen 内嵌表单（仅 PaymentSection；新流程走网关跳转 + confirm-payment） |
| `components/checkout/PayPalPaymentForm.tsx` | PayPal 内嵌表单（同上） |

### 修改

- `checkout/[id]/page.tsx`：删除 legacy 兜底渲染 + `getAddresses`/`CheckoutInitialData`/`current_step=complete` 重定向等配套；无前缀/不可解析 id → `redirect('/{urlCountry}/{locale}')`（首页）。cart_/or_ 分支行为不变。
- `lib/data/checkout.ts`：删 `applyCode`/`removeDiscountCode`/`removeGiftCard`（仅 legacy 页调用；UnifiedCheckout 折扣码走 BFF `/api/checkout/coupon`）+ 未用 import。
- `lib/data/payment.ts`：删 `createDirectPayment`（仅 PaymentSection）。
- `components/checkout/index.ts`（barrel）：移除已删导出；保留 `CouponCode`/`ExpressCheckoutButton`/`StripePaymentForm`。
- `lib/data/__tests__/checkout.test.ts`：移除对应 describe 块与 import。

### 保留（共享/现行）

- 组件：`AddOnsSection`、`SaveInfoSection`、`AddressEditModal`、`AddressFormFields`、`CouponCode`、`CardPaymentForm`、`StripePaymentForm`、`ExpressCheckoutButton`、`PolicyConsent`、`CheckoutSectionTitle`
- 数据：`updateOrderAddresses`/`selectDeliveryRate`/`completeCheckoutOrder`/`completeCheckoutPaymentSession`/`createCheckoutPaymentSession`（express-checkout-flow 现行）、`getCompletedOrder`（order-placed）、`updateCartMarket`（useCountrySwitch）、`getCheckoutOrder`（page）
- 路由/后端：Express（CartDrawer）/ confirm-payment / order-placed / UnifiedCheckout / OrderPaymentContent；后端与 SDK 零改动
- i18n keys 共享命名空间不清理；`@adyen/adyen-web`/`@paypal/react-paypal-js` 依赖已无 src 引用（可选后续清理 package.json）

## 验证结果

| 检查 | 结果 |
|---|---|
| 全仓 grep（storefront/src）9 文件 + 4 函数 + 类型 | 0 残留（.next/coverage 缓存除外） |
| `tsc --noEmit` | 0 |
| `biome check .`（含 --write 规范化历史格式漂移） | 0 error |
| `check:locales` | all keys match（5 locale） |
| vitest 受影响套件 | 7 files / 69 tests 全绿 |
| 共享组件保留断言 | 逐文件 grep 确认仍在 UnifiedCheckout/OrderPaymentContent/PaymentCheckoutModal/account/CartDrawer 使用 |

## 文档同步

- PRD §12 CHK-P1-4C4 实施块 + AC-705~709 + changelog 0.8
- `ai/skills/pallastrade-storefront/SKILL.md` changelog 追加
- 本总结文档

## 遗留（记录）

- `@adyen/adyen-web` / `@paypal/react-paypal-js` package.json 依赖未删（无引用，可选清理，需 pnpm install 更新 lock）
- i18n 独有 key 未强清（共享命名空间，风险>收益）
- git 提交归 owner（工作区大量未提交变更）
