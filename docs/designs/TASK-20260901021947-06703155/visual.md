# 视觉设计 — 正向下单与支付关键链路强化

> Task：`TASK-20260901021947-06703155`  
> 遵循 Tailwind 与 Storefront design token；禁止 JSX inline style 和硬编码 hex。

## 1. Checkout

- 延续现有 Checkout 视觉，不做品牌级重设计。
- 右侧 Order Summary 使用现有卡片 token，桌面端 `sticky`，与顶部保留安全间距。
- 支付卡表单始终占据稳定高度，避免 Pay 后布局跳变。
- 阶段 loading 保持按钮宽高不变。

## 2. Result states

| 状态 | 语义视觉 | 强调操作 |
|---|---|---|
| success | success token + check icon | Continue Shopping |
| failed | destructive token + alert icon | Retry Payment |
| canceled | muted warning token | Retry Payment |
| pending | info token + progress indicator | Refresh status |

使用现有语义色和图标组件，不引入新的硬编码颜色。

## 3. Responsive

- `lg` 以上左右分栏，Summary sticky。
- `lg` 以下单列；Summary 不 sticky，避免遮挡支付表单。
- 结果页保持窄内容列，主操作在移动端全宽。

## 4. 兼容面

- 旧 `/order-placed` 与 `/checkout/[or_id]` 即使作为兼容入口，也复用新结果/支付组件，避免同一状态出现两套视觉语义。
