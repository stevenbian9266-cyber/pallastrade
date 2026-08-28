# frozen_string_literal: true

# PALLAS-CUSTOM: 父订单批量售后（PRD-20260828 P7，flag 灰度）
#
# 对父订单（有 children）展开为「父订单自身 + 全部子订单」，为每个仍有
# 已发货 inventory_units（且未被既有 ReturnAuthorization 关联）的订单创建
# ReturnAuthorization + return_items（复用现有 RA 模型，金额/退款按子订单归集）。
#
# 幂等：已关联的 inventory_units 自动排除，重复调用不产生重复 RA。
# flag 由调用方（Admin controller）控制；本服务只做展开与创建。
module PallasTrade
  module Returns
    class ParentOrderReturns
      prepend PallasTrade::ServiceModule::Base

      # @param parent_order [PallasTrade::Order] 父订单（parent_order? 且未取消）
      # @param stock_location [PallasTrade::StockLocation]
      # @param reason [PallasTrade::ReturnAuthorizationReason]
      # @param memo [String, nil]
      # @return [PallasTrade::ServiceModule::Result] success(return_authorizations) / failure(parent_order, message)
      def call(parent_order:, stock_location:, reason:, memo: nil)
        return failure(parent_order, 'Order is not a parent order') unless splittable?(parent_order)

        orders = target_orders(parent_order)
        return failure(parent_order, 'No returnable orders') if orders.empty?

        created = orders.filter_map { |order| create_return_authorization(order, stock_location, reason, memo) }

        if created.any?
          success(created)
        else
          failure(parent_order, 'No return authorizations were created')
        end
      end

      private

      def splittable?(parent_order)
        parent_order.present? && parent_order.parent_order? && !parent_order.canceled?
      end

      # 父订单自身 + 全部子订单，仅保留有可退（shipped 且未关联 RA）inventory_units 的订单
      def target_orders(parent_order)
        [parent_order, *parent_order.children].select { |order| shippable_inventory_units(order).any? }
      end

      # shipped 且未被既有 RA return_items 关联的 inventory_units（幂等）
      def shippable_inventory_units(order)
        associated = order.return_authorizations.includes(:return_items).flat_map { |ra| ra.return_items.map(&:inventory_unit_id) }
        order.inventory_units.where(state: 'shipped').where.not(id: associated)
      end

      def create_return_authorization(order, stock_location, reason, memo)
        inventory_units = shippable_inventory_units(order)
        return nil if inventory_units.empty?

        ra = PallasTrade::ReturnAuthorization.new(
          order: order,
          stock_location: stock_location,
          reason: reason,
          memo: memo
        )
        inventory_units.each do |inventory_unit|
          ra.return_items.build(inventory_unit: inventory_unit).tap(&:set_default_pre_tax_amount)
        end
        ra.save!
        ra
      rescue StandardError => e
        # 单订单失败跳过，不阻断其余子订单（尽力而为）
        Rails.error.report(e, context: { order_id: order.id }, source: 'PallasTrade.returns.parent_order_returns')
        nil
      end
    end
  end
end
