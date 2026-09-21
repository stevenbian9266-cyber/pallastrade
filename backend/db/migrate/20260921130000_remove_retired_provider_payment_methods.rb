# frozen_string_literal: true

# PALLAS-CUSTOM: 收敛切片 5 遗留数据清理（2026-09-21）
#
# 背景：切片 5 删除了 `pallastrade_adyen` / `pallastrade_paypal_checkout` 两个 gem
# （连同 STI 类）。**代码删了，数据没删** —— 库里仍存在 `type` 指向已删类的历史行。
# ActiveRecord 实例化这类行时抛 `ActiveRecord::SubclassNotFound`，且**整条查询一起失败**：
# dev 后台「支付方式」列表整页 500 且响应体为空（= 用户看到的空白页）。
#
# 处置选择（与「不得改写历史交易」一致）：
#   本表 `acts_as_paranoid`（`deleted_at`），且被 `pallastrade_payment_sources`
#   以 NO ACTION 外键引用。因此**软删除**是唯一同时满足下列三者的动作：
#     1. 行从应用层彻底消失（paranoid 默认作用域过滤）—— 满足「删行」意图；
#     2. 不破坏外键与资金记录的历史引用（`pallastrade_payments` /
#        `pallastrade_payment_sessions` 仍可按 id 追溯）；
#     3. 可回滚取证（必要时仍能从库里查到原行）。
#
# 只处理**显式列举**的已下线厂商，不使用「type 不在注册表」这类宽口径猜测，
# 以免误伤将来新增/尚未注册的类型。其余未知类型由读路径容错兜底
# （`PaymentMethod.loadable` + `PaymentMethod.sti_class_for`）。
class RemoveRetiredProviderPaymentMethods < ActiveRecord::Migration[8.1]
  RETIRED_TYPES = %w[
    PallasTradeAdyen::Gateway
    PallasTradePaypalCheckout::Gateway
  ].freeze

  def up
    quoted = RETIRED_TYPES.map { |t| connection.quote(t) }.join(', ')
    ids = select_values(
      "SELECT id FROM pallastrade_payment_methods " \
      "WHERE type IN (#{quoted}) AND deleted_at IS NULL"
    )

    if ids.empty?
      say 'No retired provider payment methods found; nothing to do.'
      return
    end

    id_list = ids.map(&:to_i).join(', ')
    execute(
      'UPDATE pallastrade_payment_methods ' \
      "SET deleted_at = NOW(), active = false, updated_at = NOW() " \
      "WHERE id IN (#{id_list})"
    )

    say "Soft-deleted #{ids.size} retired provider payment method(s): #{ids.join(', ')}"
  end

  # 不可逆：软删除行的「未删」状态无法安全还原（原始 `active` 值已丢失，
  # 且这些行本就不应再出现在应用中）。如需恢复，请从备份逐行处理。
  def down
    raise ActiveRecord::IrreversibleMigration,
          'Retired provider payment methods were soft-deleted; restore from backup if needed.'
  end
end
