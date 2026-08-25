# PALLAS-CUSTOM: 多订单拆分（PRD-20260823 + PRD-20260824 增强）
#
# Splits an order into multiple new orders by partitioning its line items.
# Used by:
#   - admin manual split (POST /api/v3/admin/orders/:id/split)
#   - checkout-time auto split (by warehouse) — see Checkout::SplitOrders
#   - payment-success auto split（支付后系统拆单，allow_paid: true）
#
# The source order keeps the line items that were not assigned to any group.
# New orders inherit store/user/channel/currency/addresses, set parent/split_from
# (父子单结构), and start in `cart` state so the normal checkout pipeline rebuilds.
# 已支付订单拆分时按行项目继承已付状态（资金分摊，避免重复支付）。
module PallasTrade
  module Orders
    class Splitter
      # 拆单业务错误（如跨店铺目标缺商品）——事务回滚并转为 failure
      class SplitterError < StandardError; end

      prepend PallasTrade::ServiceModule::Base

      # @param order [PallasTrade::Order] the source order
      # @param groups [Hash<Symbol/String, Array<String,Integer>>, nil] group key → line item ids
      #   （nil 时用 by: 策略自动分组）
      # @param by [Symbol, nil] 分组策略 :warehouse | :store | :custom（groups 为空时使用）
      # @param allow_paid [Boolean] 是否允许拆分已支付订单（支付后系统拆单）
      # @return [ServiceResult<Array<PallasTrade::Order>>]
      def call(order:, groups: nil, by: nil, allow_paid: false)
        ApplicationRecord.transaction do
          return failure(order, { code: :order_not_splittable, message: PallasTrade.t(:order_not_splittable) }) unless splittable?(order, allow_paid: allow_paid)

          groups ||= resolve_groups(order, by)

          return failure(order, { code: :no_split_groups, message: PallasTrade.t(:no_split_groups) }) if groups.blank?

          paid = order.paid?
          new_orders = groups.filter_map do |_key, spec|
            ids, options = normalize_group(spec)
            build_split_order(order, Array(ids), store_id: options[:store_id],
                                                stock_location_id: options[:stock_location_id],
                                                paid: paid)
          end

          return failure(order, { code: :no_split_line_items, message: PallasTrade.t(:no_split_line_items) }) if new_orders.empty?

          # Recalculate source + children totals/shipments
          order.reload
          PallasTrade::OrderUpdater.new(order).update
          new_orders.each do |o|
            o.reload
            # PALLAS-CUSTOM: FR-039 订单级促销分摊 — OrderUpdater.recalculate_adjustments 通过
            # includes(:adjustable) 预加载 Order 实例读 DB 列，若 item_total 列仍是旧值 0 会把
            # 订单级促销金额重置为 0；先把 item_total 列预写为正确值，使促销按子订单金额分摊。
            o.update_columns(item_total: o.line_items.to_a.sum(&:amount))
            PallasTrade::OrderUpdater.new(o).update
            # 资金分摊在 OrderUpdater 重算之后执行（OrderUpdater 会基于 payments 重置 payment_total）
            allocate_payment(o, order) if paid
          end

          success(new_orders)
        end
      rescue SplitterError => e
        failure(order, { code: :split_error, message: e.message })
      end

      private

      # 兼容两种 group 形态：
      #   { "g1" => ["li_x"] }                                        —— 数组（继承源订单店铺）
      #   { "g1" => { "line_item_ids" => [...], "store_id" => "st_x",
      #               "stock_location_id" => "loc_y" } }              —— Hash（跨店/指定仓库，FR-027）
      def normalize_group(spec)
        if spec.is_a?(Hash) && spec.key?('line_item_ids')
          [
            Array(spec['line_item_ids']),
            {
              store_id: spec['store_id'],
              stock_location_id: spec['stock_location_id']
            }
          ]
        else
          [Array(spec), {}]
        end
      end

      def resolve_groups(order, by)
        return {} if by.blank?

        result = PallasTrade::Orders::Splitting::Grouper.call(order: order, by: by)
        result.success? ? result.value : {}
      end

      def splittable?(order, allow_paid: false)
        !order.completed? && !order.canceled? && (allow_paid || order.payments.completed.none?)
      end

      def build_split_order(source, line_item_ids, paid: false, store_id: nil, stock_location_id: nil)
        line_items = source.line_items.where(id: line_item_ids).to_a
        return nil if line_items.empty?

        target_store = resolve_target_store(source, store_id)
        # PALLAS-CUSTOM: 跨店铺拆单（FR-028）— 目标店铺必须有该商品，否则返回明确错误
        if target_store != source.store
          missing = line_items.reject { |li| li.variant&.product && li.variant.product.store_id == target_store.id }
          unless missing.empty?
            raise SplitterError,
                  PallasTrade.t(:order_split_store_missing_product,
                                 default: '商品 %{item} 在目标店铺不可用', item: missing.first.variant&.name || 'N/A')
          end
        end

        split_order = PallasTrade::Order.new(
          store: target_store,
          user: source.user,
          channel: source.channel,
          market: source.market,
          currency: source.currency,
          email: source.email,
          locale: source.locale,
          bill_address: source.bill_address,
          ship_address: source.ship_address,
          split_from: source,
          # PALLAS-CUSTOM: 父子单结构（PRD-20260824）— 拆出的子订单归入同一父订单
          parent: source,
          last_ip_address: source.last_ip_address,
          created_by: source.created_by
        )
        split_order.save!

        # Move the selected line items onto the new order (triggers inventory/adjustment recalc)
        line_items.each do |li|
          li.update!(order: split_order)
          # PALLAS-CUSTOM: 子订单售后（PRD-20260824 FR-034）— 库存单元跟随行项目转移，
          # 保证子订单发货后能对其发起 ReturnAuthorization（must_have_shipped_units 校验子订单自身库存单元）。
          # 拆单时订单未完成（splittable? 要求 !completed），不存在 shipped/returned 单元，转移安全。
          li.inventory_units.update_all(order_id: split_order.id) if li.inventory_units.any?
        end

        # PALLAS-CUSTOM: 订单级促销优惠拆单分摊（PRD-20260824 FR-039）— 复制源订单的
        # 订单级（adjustable = Order）促销 adjustment 到子订单（同一 PromotionAction source），
        # OrderUpdater 重算时 CreateAdjustment#compute_amount(child) 基于子订单金额计算折扣，
        # 自动按行项目金额比例分摊、总额守恒；源订单保留其 adjustment，重算后按剩余金额计算。
        allocate_order_level_promotions(source, split_order)

        # PALLAS-CUSTOM: 子订单可独立发货（PRD-20260824 FR-031/032）—
        # 从源订单复制 shipment（stock_location + shipping method），关联子订单 inventory_units，
        # 使子订单在管理后台可单独触发发货，父订单视图能展示各子订单发货进度。
        build_split_shipment(split_order, source)

        split_order
      end

      # PALLAS-CUSTOM: 订单级促销优惠拆单分摊（PRD-20260824 FR-039/AC-039）
      # 复制源订单的订单级（adjustable = Order）促销 adjustment 到子订单（同一 PromotionAction
      # source）；金额由 OrderUpdater 基于子订单 item_total 重算（CreateAdjustment#compute_amount
      # 基于子订单金额 → 自动按行项目金额比例分摊、总额守恒）。
      # 源订单保留其 adjustment（OrderUpdater 重算后按剩余金额计算）。
      def allocate_order_level_promotions(source, split_order)
        source.adjustments.promotion.eligible.where(adjustable_type: 'PallasTrade::Order').each do |adj|
          next if adj.source.blank?

          split_order.adjustments.create!(
            order: split_order,
            source: adj.source,
            label: adj.label,
            amount: 0,
            mandatory: adj.mandatory,
            included: adj.included,
            eligible: true
          )
        end
      end

      def build_split_shipment(split_order, source)
        return if split_order.ship_address.blank?

        source_shipment = source.shipments.order(:created_at).first
        return unless source_shipment
        return if split_order.inventory_units.none?

        # PALLAS-CUSTOM: 运费按行项目金额比例分摊（PRD-20260824 FR-038/AC-038）—
        # 子订单 shipment 承担拆走行项目比例对应的运费，父订单剩余 shipment 同步调减，
        # 保证拆单后运费总额守恒、不重复计算。
        split_item_total = split_order.line_items.sum { |li| li.price.to_d * li.quantity }
        remaining_item_total = source.line_items.sum { |li| li.price.to_d * li.quantity }
        total_item = split_item_total + remaining_item_total
        ratio = total_item > 0 ? split_item_total / total_item : 0

        source_cost = source_shipment.cost.to_d
        split_cost = (source_cost * ratio).round(2)
        remaining_cost = (source_cost * (1 - ratio)).round(2)

        shipment = PallasTrade::Shipment.create!(
          order: split_order,
          address: split_order.ship_address,
          stock_location: source_shipment.stock_location,
          cost: split_cost
        )
        shipping_method = source_shipment.shipping_method
        shipment.add_shipping_method(shipping_method, true) if shipping_method
        split_order.inventory_units.update_all(shipment_id: shipment.id)

        # 父订单 shipment 运费按剩余行项目比例调减（总额守恒）
        source_shipment.update_columns(cost: remaining_cost)

        shipment
      end

      def resolve_target_store(source, store_id)
        return source.store if store_id.blank?

        PallasTrade::Store.find_by_prefix_id!(store_id)
      end

      # PALLAS-CUSTOM: 资金分摊（FR-021）— 原订单已支付时，为子订单创建真实 Payment 记录
      # （Order#paid? 基于 payments.valid.completed），金额按行项目合计分摊，避免重复支付。
      def allocate_payment(split_order, source)
        amount = split_order.line_items.sum(&:amount)
        return if amount.to_f <= 0

        source_payment = source.payments.completed.first
        split_order.payments.create!(
          amount: amount,
          state: 'completed',
          payment_method: source_payment&.payment_method,
          source: source_payment&.source,
          response_code: source_payment&.response_code
        )
        split_order.update_columns(payment_total: amount, payment_state: 'paid')
      end
    end
  end
end
