# REQ-20260815-back-in-stock

> 关联 PRD：PRD-20260815-shipping-补货通知-back-in-stock（approved）
> 任务：TASK-20260815061638-cd3f75ce

## Step 0：跨层搜索（已执行，结论见 PRD §6）

| 层 | 路径 | 关键词 | 找到的文件 | 是否满足 |
|---|---|---|---|---|
| App | `backend/app/` | back_in_stock | 无 | 否 |
| Core | `pallastrade_gems/pallastrade_core/app/` | back_in_stock/subscriber/mailer | `stock_movement/custom_events.rb`（`product.back_in_stock` 事件已有）；`subscribers/`（先例）；`base_mailer.rb` | 触发机制已有，模型/订阅/邮件需新建 |
| API | `pallastrade_gems/pallastrade_api/app/` | back_in_stock | 无 | 需新建 store 端点 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | back_in_stock | 无 | 需新建订阅列表 |
| Storefront | `storefront/src/` | back_in_stock/notify | 无 | 需新建缺货订阅组件 |
| Platform | `platform/packages/` | back_in_stock | 无 | SDK 可选 |

## Step 1：Skill 文件咨询

| Skill | 状态 | 关键结论引用 |
|---|---|---|
| `pallastrade-customization` | ✅ 已读 | 事件副作用 → Subscriber（决策树第 2 优先级）；模型新建 → generator/model |
| `pallastrade-events-webhooks` | ✅ 已读 | 事件总线：`product.back_in_stock` 由 StockMovement 发布；Subscriber 注册到 `PallasTrade::Subscriber` |
| `pallastrade-api-v3` | ✅ 已读 | Store API：v3 前缀 + prefixed ID + 扁平响应；新端点走 ResourceController |
| `pallastrade-deployment` | ✅ 已读 | 环境变量走 `.env`（服务器），`RESEND_API_KEY` 不提交 |
| `pallastrade-data-model` | ✅ 已读 | 新表迁移 core + backend 双份；`db/migrate` 禁止手改 |

## 实施内容

1. 迁移（core + backend）：`pallastrade_back_in_stock_subscriptions`（variant_id, email, status, store_id, timestamps + 唯一索引 [variant_id, email]）
2. `core/app/models/pallastrade/back_in_stock_subscription.rb`：store 作用域、active scope、唯一校验、幂等
3. `core/app/subscribers/pallastrade/back_in_stock_subscriber.rb`：订阅 `product.back_in_stock` → 查 product variants 的 active 订阅 → 发邮件 + notified
4. `core/app/mailers/pallastrade/back_in_stock_mailer.rb` + `core/.../services/.../resend_mailer.rb`（Resend HTTP API，ENV key）
5. `core/lib/pallastrade/core/dependencies.rb`：注册 serializer/service
6. `api/.../store/back_in_stock_subscriptions_controller.rb`：POST 创建（校验缺货 + 邮箱 + 幂等）
7. `admin/.../back_in_stock_subscriptions_controller.rb` + views + tables + navigation + locale
8. storefront：商品页缺货订阅组件（"Notify me"），调用 Store API
9. `.env.example`：+ RESEND_API_KEY（占位）
10. spec：model/API/subscriber/admin/storefront
11. api-docs store.yaml + skills + scenarios 同步

## 密钥安全

- `RESEND_API_KEY` 只写入服务器 `.env`（deploy 目录 `.env.dev`），不进代码、不提交
- 无 key 时邮件发送降级为日志（`Rails.logger`），不阻断库存/事件流程
