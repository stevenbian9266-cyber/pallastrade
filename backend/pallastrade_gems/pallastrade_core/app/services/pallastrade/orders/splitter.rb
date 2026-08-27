# PALLAS-CUSTOM: 统一拆单引擎（PRD-20260826 P2）——能力层服务，默认不接入任何流程
module PallasTrade
  module Orders
    # 把一笔订单按分组拆成多笔子订单（挂同一父订单）。
    #
    # 能力层服务：只做「行项目迁移 + order 级调整分摊 + 已付金额分摊 + 金额重算」，
    # 不推进子订单 checkout（P5 自动拆单 / P6 手动拆单负责接入与流程推进）。
    #
    # 语义约定（与升级方案 §6.1 一致）：
    #   - 子订单 parent_id / split_from_id 指向源订单；
    #   - 源订单保留未分组行项目；全部分出时成为空父订单容器；
    #   - 拆单前后总额守恒（Σ子订单 + 源订单剩余 = 原订单）。
    #
    # @param order [PallasTrade::Order] 源订单
    # @param groups [Hash<Symbol,String => Array<Integer,String>>] 分组 → line item id（支持 li_ 前缀或整型）
    # @param parent_order [PallasTrade::Order, nil] 父订单（默认源订单自身作为父）
    # @return [PallasTrade::ServiceModule::Result] success(children) / failure(order, message)
    class Splitter
      prepend PallasTrade::ServiceModule::Base

      def call(order:, groups:, parent_order: nil)
        ApplicationRecord.transaction do
          order.with_lock do
            return failure(order, 'Order is not splittable') unless splittable?(order)

            groups = normalize_groups(order, groups)
            return failure(order, 'No valid split groups') if groups.blank?

            # 拆分前捕获行项目总额（迁移后源订单行项目会被清空）
            line_items_total = order.line_items.to_a.sum(&:amount).to_f

            children = groups.filter_map { |_key, ids| build_child(order, ids, parent_order) }
            return failure(order, 'No line items were split') if children.empty?

            reallocate_order_adjustments(order, children, line_items_total)
            children.each do |child|
              child.create_tax_charge! if order.completed?
              child.line_items.reload # OrderUpdater 会读取关联，确保不含缓存旧值
              PallasTrade::OrderUpdater.new(child).update
            end
            order.line_items.reload
            PallasTrade::OrderUpdater.new(order).update
            split_payments!(order, children, line_items_total)

            order.publish_event('order.splitted',
                                order.event_payload.merge(child_order_ids: children.map(&:prefixed_id)))

            success(children.map(&:reload))
          end
        end
      end

      private

      def splittable?(order)
        order.present? && !order.canceled? && order.line_items.exists?
      end

      # 规范化 groups：解析 prefixed/整型 id，剔除不属于源订单的行项目。
      def normalize_groups(order, groups)
        groups.each_with_object({}) do |(key, ids), out|
          line_item_ids = Array(ids).filter_map { |id| resolve_line_item_id(order, id) }
          out[key] = line_item_ids if line_item_ids.any?
        end
      end

      def resolve_line_item_id(order, id)
        return id.to_i if id.to_s.match?(/\A\d+\z/)

        line_item = PallasTrade::LineItem.find_by_prefix_id(id.to_s)
        line_item&.order_id == order.id ? line_item.id : nil
      end

      def build_child(order, line_item_ids, parent_order)
        line_items = order.line_items.where(id: line_item_ids).to_a
        return nil if line_items.empty?

        child = PallasTrade::Order.new(
          store: order.store,
          user: order.user,
          created_by: order.created_by,
          channel: order.channel,
          market: order.market,
          currency: order.currency,
          email: order.email,
          locale: order.locale,
          bill_address: order.bill_address,
          ship_address: order.ship_address,
          last_ip_address: order.last_ip_address,
          parent: parent_order || order,
          split_from: order
        )
        child.save!

        move_line_items(order, child, line_items)
        child
      end

      # 迁移行项目：同步其 line_item 级调整与库存单位的订单归属。
      def move_line_items(order, child, line_items)
        line_items.each do |line_item|
          line_item.adjustments.update_all(order_id: child.id)
          line_item.inventory_units.update_all(order_id: child.id)
          line_item.update!(order: child)
        end
      end

      # order 级非税 eligible 调整（promo 等）按行项目金额比例分摊重建到各子订单。
      # 原调整记录保留在源订单（不动），子订单新增同源 Adjustment。
      def reallocate_order_adjustments(order, children, line_items_total)
        adjustments = order.adjustments.eligible.non_tax.to_a
        return if adjustments.empty?
        return if line_items_total.zero?

        adjustments.each do |adjustment|
          children.each do |child|
            group_amount = child.line_items.to_a.sum(&:amount).to_f
            next if group_amount.zero?

            share = (adjustment.amount * (group_amount / line_items_total)).round(2)
            next if share.zero?

            # 分摊金额已定：save! 后强制冻结 amount + closed。
            # 不能依赖 close（after_create 会触发 AdjustmentsUpdater 用 source 重算 open 调整），
            # update_columns 绕过一切回调/状态机，确保分摊金额不被 adjuster 覆盖。
            split_adjustment = PallasTrade::Adjustment.new(
              order: child,
              adjustable: child,
              source: adjustment.source,
              amount: share,
              label: adjustment.label,
              eligible: true,
              mandatory: adjustment.mandatory,
              included: adjustment.included
            )
            split_adjustment.save!
            split_adjustment.update_columns(amount: share, state: 'closed')
          end
        end

        # 分摊后删除源订单的原 order 级调整：金额已按比例迁移到子订单，
        # 保留会造成父容器（行项目为空）金额重复计算。
        adjustments.each(&:destroy)
      end

      # 源订单存在 completed 支付时，按行项目金额比例把已付金额分摊为各子订单的
      # PaymentSplit（payment_combination 为空——记账分摊，P4 合并支付时归入组合）。
      def split_payments!(order, children, line_items_total)
        payments = order.payments.completed.to_a
        return if payments.empty?
        return if line_items_total.zero?

        payments.each do |payment|
          paid = payment.amount - payment.refunds.sum(:amount)
          next if paid <= 0

          children.each do |child|
            group_amount = child.line_items.to_a.sum(&:amount).to_f
            next if group_amount.zero?

            share = (paid * (group_amount / line_items_total)).round(2)
            PallasTrade::PaymentSplit.find_or_create_by!(order: child, payment: payment) do |split|
              split.authorized_amount = share
              split.captured_amount = share
              split.currency = payment.currency
            end
          end
        end
      end
    end
  end
end
