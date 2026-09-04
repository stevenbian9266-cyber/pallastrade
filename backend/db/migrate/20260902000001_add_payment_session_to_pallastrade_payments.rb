# frozen_string_literal: true

# P0-1 (2026-09-02): 建立 Payment ↔ PaymentSession 正式关联。
#
# 背景：现状依赖 Payment.response_code ↔ PaymentSession.external_id 字符串拼接，
# 在 Checkout Session 模式（session.external_id = cs_xxx 但 Payment.response_code = pi_xxx）
# 下已不可靠，且已实证 PaymentSession#payment has_one 在同一实例上可能返回 nil。
#
# 本迁移：
#   - 在 pallastrade_payments 增加可空 payment_session_id（正式 FK，第一阶段 nullable）
#   - 不删除 response_code 列（仍是 PSP reference）
#   - 不做 destructive 变更
class AddPaymentSessionToPallasTradePayments < ActiveRecord::Migration[8.1]
  def up
    add_reference :pallastrade_payments, :payment_session,
                  null: true,
                  foreign_key: { to_table: :pallastrade_payment_sessions }

    # 回填：仅回填可可靠确认的 pi_ 模式（payment.response_code == session.external_id 且
    # 同 order + 同 payment_method）。cs_ 模式或存在歧义的行保持 NULL（不强猜）。
    execute(<<~SQL)
      UPDATE pallastrade_payments p
      SET payment_session_id = s.id
      FROM pallastrade_payment_sessions s
      WHERE s.external_id = p.response_code
        AND s.order_id = p.order_id
        AND s.payment_method_id = p.payment_method_id
        AND p.payment_session_id IS NULL
        AND s.deleted_at IS NULL
    SQL
  end

  def down
    remove_reference :pallastrade_payments, :payment_session
  end
end
