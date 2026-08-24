# frozen_string_literal: true

# PALLAS-CUSTOM: 父订单售后（PRD-20260824 FR-035/036）
#
# 对整个父订单（含其下全部子订单）发起售后：
#   - 展开为 [父订单] + 全部子订单
#   - 为每个可售后的订单创建 ReturnAuthorization（金额/退款天然按子订单归集）
#   - 幂等：已有非 canceled 售后授权的订单跳过，不重复创建
#
# 未拆单时父订单即子订单（Order#parent_id 自引用，用户规则 2），
# 此时等价于对单个订单发起售后。
module PallasTrade
  module Returns
    class FromParent
      prepend PallasTrade::ServiceModule::Base

      # @param order [PallasTrade::Order] 父订单（未拆单时为单个订单）
      # @param reason [PallasTrade::ReturnAuthorizationReason]
      # @param stock_location [PallasTrade::StockLocation]
      # @param memo [String, nil]
      # @return [ServiceResult<Array<PallasTrade::ReturnAuthorization>>]
      def call(order:, reason:, stock_location:, memo: nil)
        ApplicationRecord.transaction do
          target_orders = ([order] + order.children.to_a).uniq

          created = []
          skipped = []
          target_orders.each do |target|
            # 幂等：已有非 canceled 售后授权（authorized 等）的子订单跳过
            next if target.return_authorizations.where.not(state: 'canceled').exists?

            ra = target.return_authorizations.build(
              reason: reason,
              stock_location: stock_location,
              memo: memo
            )
            if ra.save
              created << ra
            else
              skipped << { order_id: target.prefixed_id, errors: ra.errors.full_messages }
            end
          end

          if created.any?
            success(created)
          else
            failure(order, {
              code: :no_return_authorization_created,
              message: PallasTrade.t(:no_return_authorization_created),
              skipped: skipped
            })
          end
        end
      end
    end
  end
end
