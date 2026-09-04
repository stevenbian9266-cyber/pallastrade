# P0_BEFORE_REFACTOR_TEST_BASELINE（P0-0 回归安全网）

> 生成：2026-09-02 | 任务：Payment P0 Foundation Hardening（TASK-20260902152116-54e2b2a2）
> 目标：锁定 Payment P0 改造前当前生产语义，后续工作包（P0-1..P0-7）不得破坏下列测试。

## 运行环境

- 容器：`docker exec pallastrade-web-1 sh -c 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec <files>'`
- Host-app backend spec（可离线，bogus/Stripe factory + 网络 stub）；Stripe gem spec（gateway_spec STR-001..013）需 sandbox key（离线部分 STR-009/013 已覆盖 amount/currency tamper 与 retrieve args）。

## 基线测试集（P0-0 新增/扩充，全绿）

| Spec 文件 | 场景 | 例数 | 状态 |
| --- | --- | --- | --- |
| `spec/services/pallastrade/payment_sessions/start_spec.rb`（既有） | Start 会话复用 / 并发收敛 / operation_key attempt-N / 终态后新 attempt / 外部支付方式拒绝 | 5 | ✅ 绿 |
| `spec/services/pallastrade/carts/complete_spec.rb`（新增） | 标准订单完成（payment 已捕获）；**重复 complete 幂等**（不重复 finalize / 不重复 side-effect）；无有效 payment 拒绝完成 | 3 | ✅ 绿 |
| `spec/services/pallastrade/payments/handle_webhook_spec.rb`（新增） | **captured 单订单路径**：建唯一 Payment + 完成订单；**重复 webhook 幂等**；failed/canceled 终态不建 Payment；nil session 安全 | 5 | ✅ 绿 |
| `spec/services/pallastrade/payments/handle_webhook_combination_spec.rb`（既有） | 组合支付 webhook → PaymentCombinations::Complete；单订单路径不受影响 | 2 | ✅ 绿 |
| `spec/models/pallastrade/payment_session_payment_association_spec.rb`（新增） | **关联基线**：pi_ 模式（response_code==external_id）has_one 成立（fresh reload）；**cs_ 模式断裂基线**；`find_or_create_payment!` 唯一性 | 3 | ✅ 绿 |
| `spec/requests/api/v3/store/order_payment_sessions_controller_spec.rb`（扩充） | 创建/权限/嵌套路由/complete 驱动订单完成/**重复 complete 幂等**/show | 6 | ✅ 绿 |

**合计：新增 11 例 + 既有扩充 1 例 + 既有保留 12 例 → 基线 24 例全绿（18 服务/模型 + 6 controller）。**

## 关键锁定行为（不得回归）

1. **Start 幂等三连**：同方法同金额同 mode 复用 active 会话；`operation_key` 按 terminal attempt 计数递增；并发 Start 收敛为唯一 winner。
2. **Carts::Complete 单点完成**：已完成的订单再次 complete 无副作用（completed_at 不变、不重复建 state_changes、payment 不被重复处理）。
3. **HandleWebhook 幂等**：重复 webhook 对已 completed 会话短路 → 不重复建 Payment / 不重复完成订单；failed/canceled 只终态化会话。
4. **Payment 唯一创建**：同一 session 经 `find_or_create_payment!` 只产生一个 Payment。
5. **API complete 幂等**：同一会话 complete 两次 → 第二次直接返回（无重复 payment / 不重复 finalize）。
6. **Amount / Currency 校验**（stripe gem STR-009）：`verify_payment_intent_matches!` 拒绝 amount/currency 与本地不一致。
7. **关联现状（P0-1 依据）**：
   - pi_ 模式：`external_id == response_code` → has_one 在 **fresh reload 后**成立；
   - cs_ 模式：`external_id=cs_` 而 `Payment.response_code=pi_` → has_one **断裂**（`session.reload.payment == nil`）；
   - ⚠️ **重要实证**：`PaymentSession#payment` has_one 在**同一内存实例上不可靠**（即使 pi_ 匹配也可能缓存 nil）——须 reload 后按 DB 事实断言。此即 P0-1 引入正式 `payment_session_id` 的核心依据。

## 覆盖缺口（记录，后续工作包处理）

- Express/cart legacy 创建路径幂等（P0-3 实施时补 Express 重复/并发测试）
- Express 前端金额重算（P0-4 实施时改 + 测）
- Webhook Event Store / 去重 / retry / replay（P0-2 实施时新增）
- Stripe gem 在线 sandbox 场景（gateway_spec STR-001..008/010..012，需真实 key，CI 或本地配 key 时跑）
- Redirect fallback 竞争（confirm_payments_controller 无 host spec——P0-2 前后补）
