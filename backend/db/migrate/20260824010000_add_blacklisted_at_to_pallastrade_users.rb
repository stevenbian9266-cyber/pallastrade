# PALLAS-CUSTOM: 下单前置校验-用户黑名单（PRD-20260824-checkout-正向订单-逆向订单链路重构或优化）
# blacklisted_at 非空 = 用户被列入黑名单，任何下单入口被拦截。
class AddBlacklistedAtToPallasTradeUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :pallastrade_users, :blacklisted_at, :datetime
  end
end
