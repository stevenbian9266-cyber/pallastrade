# REQ-20260818-p0-3-abandoned-cart — P0-3 邮件自动化-弃单恢复

> 关联 PRD：PRD-20260818-other-p0-3-邮件自动化-弃单恢复
> 关联任务：TASK-20260818055744-a9c9242e
> 类型：新功能（需求：前缀，用户"实施"确认）

---

## Step 0：跨层搜索（结果见 PRD §6，要点）

- Core：Order 状态机（cart?/incomplete/token）、事件/订阅、BaseMailer（append_token/DB 模板）、BackInStockMailer（营销邮件先例）、EmailTemplate/KNOWN_KEYS、EmailLog、BackInStockSubscription（幂等先例）、BaseJob/expire_job（扫描先例）
- API：cart_resolvable（token 认证）
- Admin：back_in_stock_subscriptions（13 处注册模板）、email_notification_scenarios（SCENARIOS）
- Storefront：checkout/[id]（恢复链接目标，无需改）
- Platform：SDK carts.get（guestToken 支持）
- **结论**：基础设施完备，缺 = last_activity_at + 扫描任务 + 通知模型 + 邮件 + Admin 页 + 调度

## Step 1：Skill 咨询

| Skill | 结论 |
|---|---|
| pallastrade-events-webhooks | 事件/订阅者注册模式（PallasTrade.subscribers <<）；BackInStockSubscriber 幂等模板 |
| pallastrade-admin | 新资源 13 处注册模板；EmailNotificationScenariosController SCENARIOS |
| pallastrade-data-model | 新模型/迁移规范（SingleStoreResource、前缀 ID、唯一索引） |

---

## 需求标题

弃单恢复：Order.last_activity_at + 定时扫描 + 恢复邮件（token 链接）+ Admin 通知页。

## 技术方案

1. 迁移：`add_last_activity_at_to_orders`（索引）+ `create_abandoned_cart_notifications`（cart_id/email/sent_at 唯一索引）。
2. `Order#touch_last_activity!`：cart 更新路径（Carts::Update/UpsertItems/Empty/Cart::Update/结账步进）调用。
3. `AbandonedCartNotification`（SingleStoreResource + `(cart,email)` 唯一 + `mark_sent!` 幂等）。
4. `AbandonedCartMailer#recovery_email(notification)`（模板 `abandoned_cart.recovery_email` + 商品列表 + 恢复链接 `{storefront_url}/{country}/{locale}/checkout/{cart_id}?token=`）。
5. `AbandonedCarts::SendNotificationsJob`（`in_batches`，条件=incomplete+email+line_items+last_activity_at 超阈值+未通知+场景开关开）。
6. 调度：引入 `sidekiq-cron` gem（worker 内 schedule 文件），每 5 分钟扫描。
7. Admin：`abandoned_cart_notifications` 页（index/manual_send/test_send，BackInStock 模板）+ EmailTemplate KNOWN_KEYS + scenarios。

## 验证

- 模型/Job/Mailer/Admin request specs + Order last_activity touch spec
- admin 全量 + quick check
- 浏览器 dev 验证

## 风险

- 调度新依赖 sidekiq-cron（worker 部署需重载）；回滚=revert 迁移+代码。
