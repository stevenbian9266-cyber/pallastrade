# frozen_string_literal: true

# PALLAS-CUSTOM: Admin 手动拆单编排（PRD-20260828 P6，flag 灰度）
#
# 复用 P2 Orders::Splitter 能力层（行项目迁移 + 调整/已付金额分摊 + 金额重算），
# 在此之上补齐 P6 语义：
#   - 仅允许拆分未发货行项目（已 shipped 的 inventory_units 拒绝拆分，避免已发货单位错乱）；
#   - 源订单为 completed 时，子订单补为 completed（绕过状态机直接落库，复用已完成金额），
#     并为子订单创建 shipment（stock_location 取自源订单首个未取消 shipment），
#     把子订单 inventory_units 迁移到新 shipment——子订单立即可发货（复用现有 ship 流程）。
#
# flag 由调用方（API controller / Admin controller）控制；本服务只做编排。
module PallasTrade
  module Orders
    class ManualSplit
      prepend PallasTrade::ServiceModule::Base

      # @param order [PallasTrade::Order] 源订单
      # @param groups [Hash<Symbol,String => Array<Integer,String>>] 分组 → line item id（支持 li_ 前缀或整型）
      # @param parent_order [PallasTrade::Order, nil] 父订单（默认源订单自身作为父）
      # @return [PallasTrade::ServiceModule::Result] success(children) / failure(order, message)
      def call(order:, groups:, parent_order: nil)
        return failure(order, 'Order is not splittable') unless splittable?(order)
        return failure(order, 'Cannot split shipped line items') if shipped_line_items?(order, groups)

        result = PallasTrade::Orders::Splitter.call(order: order, groups: groups, parent_order: parent_order)
        return result unless result.success?

        children = result.value
        children.each { |child| finalize_completed_child!(child) } if order.completed?

        success(children.map(&:reload))
      end

      private

      def splittable?(order)
        order.present? && !order.canceled? && order.line_items.exists?
      end

      # groups 中任一行的 inventory_units 已 shipped → 不可拆（安全边界，避免已发货单位错乱）
      def shipped_line_items?(order, groups)
        line_item_ids = Array(groups).flat_map { |_key, ids| Array(ids) }
                                    .filter_map { |id| resolve_line_item_id(order, id) }
        return false if line_item_ids.empty?

        PallasTrade::InventoryUnit.where(line_item_id: line_item_ids, state: 'shipped').exists?
      end

      def resolve_line_item_id(order, id)
        return id.to_i if id.to_s.match?(/\A\d+\z/)

        line_item = PallasTrade::LineItem.find_by_prefix_id(id.to_s)
        line_item&.order_id == order.id ? line_item.id : nil
      end

      # CORE-P5-2（2026-09-07）：ManualSplit 子单完成收口 —— 受控原语 + 完成事件 trace。
      #
      # 为何不走 Order#finalize!（canonical finalization）：子订单由已支付/已完成的父单
      # 拆出，物理库存已在父单 finalize! 时真实扣减（StockMovement），子单无本地 payment
      # （资金经 PaymentSplit 在组合/父单侧入账，P4 语义）。此处只补 order-level 完成态
      # （state/completed_at）与派生态（totals/shipment/state），**不重走** finalize! 的
      # 库存/支付/事件副作用（避免重复扣减与重复计费）。完成即发布
      # `order.split_child.completed`（事件总线 EventLogSubscriber 自动落 JSON trace；
      # 未来 P6 退款/审计可订阅此事件作为子单完成锚点）。
      def finalize_completed_child!(child)
        return if child.completed? # CORE-P5-2: 幂等保护（重入/重复拆单不重复完成）

        child.update_columns(
          state: 'complete',
          completed_at: child.completed_at.presence || Time.current
        )
        # CORE-P5-8: 直写完成（绕过状态机/事件）只能原位打点计数
        PallasTrade::OperationalMetrics.legacy('manual_split_complete', order_id: child.prefixed_id)
        build_child_shipment!(child)
        child.shipments.reload

        # Splitter 已按行项目比例建 PaymentSplit，但 payment_total 列未刷新（Splitter 内 OrderUpdater 在其前运行）
        split = child.payment_splits.order(:id).last
        payment_total = split ? (split.captured_amount - split.refunded_amount).to_f : child.payment_total.to_f

        child.update_columns(
          payment_total: payment_total,
          shipment_total: child.shipments.sum(&:cost).to_f,
          total: child.item_total.to_f + child.adjustment_total.to_f
        )
        child.update_columns(
          shipment_state: derive_shipment_state(child),
          payment_state: derive_payment_state(child)
        )
        publish_split_child_completed(child)
      end

      # CORE-P5-2: 子单完成事件（payload 含 child/parent prefixed id 与来源）
      def publish_split_child_completed(child)
        parent = child.split_from || child.parent
        child.publish_event(
          'order.split_child.completed',
          id: child.prefixed_id,
          parent_order_id: parent&.prefixed_id,
          source: 'admin_manual_split'
        )
      end

      def build_child_shipment!(child)
        source_shipment = child.split_from&.shipments&.not_canceled&.first
        stock_location = source_shipment&.stock_location || child.store.stock_locations.active.first
        return if stock_location.nil?

        PallasTrade::Shipment.create!(
          order: child,
          stock_location: stock_location,
          address: child.ship_address,
          cost: 0
        )
        child.inventory_units.update_all(shipment_id: child.shipments.reload.last.id)
      end

      # 复制 OrderUpdater#update_shipment_state（订单为 complete，无 backorder 分支）
      def derive_shipment_state(order)
        states = order.shipments.map(&:state).uniq
        if states.size > 1
          states.include?('shipped') ? 'partial' : (states.include?('pending') ? 'pending' : 'ready')
        else
          states.first
        end
      end

      # 复制 OrderUpdater#update_payment_state
      def derive_payment_state(order)
        if order.payments.present? && order.payments.valid.empty?
          'failed'
        elsif order.canceled? && order.payment_total.to_f.zero?
          'void'
        elsif order.outstanding_balance.to_f > 0
          'balance_due'
        elsif order.outstanding_balance.to_f < 0
          'credit_owed'
        else
          'paid'
        end
      end
    end
  end
end
