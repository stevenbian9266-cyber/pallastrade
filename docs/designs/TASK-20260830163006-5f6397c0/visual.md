# 视觉设计 — 下单链路统一化（TASK-20260830163006-5f6397c0）

> 关联 PRD：PRD-20260830-checkout-下单链路规范化统一化；Gate：GATE-2026-08-30T16-30-18
> 遵循 Storefront 样式规范：Tailwind 语义色、禁用内联样式（AP-001）、禁用硬编码 hex（AP-006）。

## 1. 统一下单页布局

- 容器：`max-w-6xl mx-auto px-4 py-8`；左右 `grid grid-cols-1 lg:grid-cols-3 gap-8`。
- 左列（`lg:col-span-2`）：区块卡片 `rounded-xl border border-gray-200 bg-white p-6`，区块间距 `mt-6`，各区块标题 `text-lg font-bold text-gray-900`。
  - 区块顺序：收件地址 → 商品信息 → 物流方式 → 支付方式。
  - Pay Now 按钮：主按钮 `data-variant="default" data-size="lg"`（w-full），位于支付方式区块下方。
- 右列：订单小结卡片 `rounded-xl border border-gray-200 bg-white p-6`（sticky top-6）。
  - 金额行：Subtotal/Shipping/Tax/优惠 用 `text-sm text-gray-500`；Total 用 `text-lg font-bold text-gray-900`。
- 商品行：`ProductImage`（禁止裸用 next/image）+ 名称 `text-sm font-medium` + 数量/单价 `text-sm text-gray-500`。

## 2. 收银台弹窗

- 组件：`Dialog`（radix / `components/ui/dialog`），`max-w-md`，圆角 `rounded-xl`，遮罩 `bg-black/50`。
- 标题区：`text-lg font-bold text-gray-900` + 关闭按钮（X）。
- 应付金额：`text-2xl font-bold`（主色 `text-gray-900`）。
- 多笔分摊列表：`text-sm text-gray-500`（每单 `#R…` + 分摊金额）。
- 支付方式 radio：复用 `PaymentSection` 样式（选中态 `border-gray-900`）。
- 底部按钮：`[Cancel]`（ghost）+ `[Pay Now]`（default，w-full 或等宽）。

## 3. 状态视觉

| 状态 | 表现 |
|---|---|
| 只读地址/物流（or_ 订单） | 区块灰底 `bg-gray-50` + 无编辑控件（与 OrderPaymentContent 一致） |
| Pay Now loading | `Loader2 animate-spin` + 禁用 |
| 错误提示 | `Alert`（`components/ui/alert`，destructive 变体）+ 表单字段 `aria-invalid` |
| 支付方式空 | `noPaymentMethods` 空态卡（灰底居中提示） |

## 4. 响应式

- `< lg`：左右堆叠（订单小结置顶或置底，建议 `order-first` 显示小结摘要），左列区块保持顺序。
- 弹窗在移动端 `w-full max-w-md` 保持可用。

## 5. 可访问性

- 弹窗：`role="dialog"` + `aria-modal` + 焦点管理（radix Dialog 内置）。
- 表单字段 label 关联、错误 `aria-describedby`；按钮可键盘操作。
